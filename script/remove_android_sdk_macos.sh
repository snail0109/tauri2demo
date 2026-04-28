#!/usr/bin/env bash
# remove_android_sdk_macos.sh — install_android_sdk_macos.sh 的反向操作
# 功能：
#   按用户选择卸载以下任一组合：
#     1) Rust Android 编译目标（保留 Android SDK）
#     2) Android SDK 目录 + 环境变量（保留 Rust Android targets）
#     3) 全部卸载（Rust targets + Android SDK + 环境变量）
#
# 用法：
#   ./remove_android_sdk_macos.sh              # 交互式
#   ./remove_android_sdk_macos.sh -y           # 静默模式（自动确认）

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✓ ${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠ ${RESET} $*"; }
fail() { echo -e "${RED}  ✗ ${RESET} $*"; FAILED=1; }

AUTO_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES=1; shift ;;
    -h|--help)
      echo "用法：$0 [-y]"
      echo "  -y / --yes  静默模式"
      exit 0
      ;;
    *) shift ;;
  esac
done

# 卸载默认确认 NO
confirm_remove() {
  local desc="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    echo -e "${YELLOW}  自动确认卸载：${desc}${RESET}"
    return 0
  fi
  echo -e "${YELLOW}  ? ${desc} —— 是否卸载？[y/N]${RESET}"
  read -r answer
  case "$answer" in
    y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

SELECTED_OPTION=0
select_option() {
  local prompt="$1"
  shift
  local options=("$@")

  echo -e "${CYAN}${prompt}${RESET}"
  local i=1
  for opt in "${options[@]}"; do
    echo -e "  ${CYAN}${i})${RESET} ${opt}"
    ((i++))
  done
  echo -e "  ${CYAN}0)${RESET} 退出（不卸载）"
  echo ""
  echo -ne "${YELLOW}  请选择 [0-$((i-1))]：${RESET}"
  read -r choice

  if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] 2>/dev/null; then
    SELECTED_OPTION="$choice"
  else
    SELECTED_OPTION=0
  fi
}

# ─── Detect Android SDK ──────────────────────────────────────────────────────
ANDROID_HOME_DETECTED=""

detect_android_home() {
  local cand="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$cand" && -d "$cand" ]]; then
    ANDROID_HOME_DETECTED="$cand"
    return 0
  fi

  local default_path="$HOME/Library/Android/sdk"
  if [[ -d "$default_path" ]]; then
    ANDROID_HOME_DETECTED="$default_path"
    return 0
  fi

  return 1
}

# ─── Rust Android targets ────────────────────────────────────────────────────

REQUIRED_TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "i686-linux-android"
  "x86_64-linux-android"
)

remove_rust_android_targets() {
  if ! command -v rustup &>/dev/null; then
    if [[ -f "$HOME/.cargo/bin/rustup" ]]; then
      export PATH="$HOME/.cargo/bin:$PATH"
    else
      warn "未检测到 rustup，跳过 Rust Android 编译目标卸载"
      return 0
    fi
  fi

  local installed present=()
  installed=$(rustup target list --installed 2>/dev/null)
  for t in "${REQUIRED_TARGETS[@]}"; do
    if echo "$installed" | grep -q "^${t}$"; then
      present+=("$t")
    fi
  done

  if [[ ${#present[@]} -eq 0 ]]; then
    warn "未检测到任何 Android Rust 编译目标，跳过"
    return 0
  fi

  if confirm_remove "卸载 ${#present[@]} 个 Rust Android 编译目标"; then
    for t in "${present[@]}"; do
      if rustup target remove "$t" 2>&1; then
        ok "已卸载 $t"
      else
        fail "rustup target remove $t 失败"
      fi
    done
  else
    warn "已跳过 Rust Android 编译目标卸载"
  fi
}

# ─── Remove Android SDK directory ────────────────────────────────────────────

remove_android_sdk_dir() {
  if ! detect_android_home; then
    warn "未检测到 Android SDK 安装目录，跳过"
    return 0
  fi
  local sdk="$ANDROID_HOME_DETECTED"

  warn "删除 SDK 目录将移除所有组件：platform-tools / cmdline-tools / ndk / platforms / build-tools"
  if ! confirm_remove "删除整个 Android SDK 目录：${sdk}"; then
    warn "已跳过"
    return 0
  fi

  if rm -rf "$sdk" 2>&1; then
    if [[ -d "$sdk" ]]; then
      fail "rm -rf 后目录仍存在：$sdk，请手动删除"
    else
      ok "Android SDK 目录已删除：$sdk"
    fi
  else
    fail "删除 $sdk 失败"
  fi
}

# ─── Clean environment variables from ~/.zshrc ────────────────────────────────

clean_env_vars() {
  if ! confirm_remove "清理 ~/.zshrc 中的 Android 环境变量配置"; then
    warn "已跳过"
    return 0
  fi

  local zshrc="$HOME/.zshrc"
  if [[ ! -f "$zshrc" ]]; then
    warn "~/.zshrc 不存在，跳过"
    return 0
  fi

  # 使用 sed 删除 install_android_sdk_macos.sh 添加的配置块
  # 删除包含 "Android SDK（由 install_android_sdk_macos.sh 添加）" 的行及其后续 ANDROID_HOME/ANDROID_NDK_HOME/PATH 行
  local tmp
  tmp=$(mktemp /tmp/zshrc_clean_XXXXXX)

  local skip=0
  while IFS= read -r line; do
    if [[ "$line" == *"Android SDK（由 install_android_sdk_macos.sh 添加）"* ]]; then
      skip=1
      continue
    fi
    if [[ "$skip" -eq 1 ]]; then
      # 跳过连续的 export ANDROID_* 和 export PATH=*platform-tools* 行
      if [[ "$line" =~ ^export\ ANDROID_ ]] || [[ "$line" == *platform-tools* ]]; then
        continue
      else
        skip=0
      fi
    fi
    echo "$line" >> "$tmp"
  done < "$zshrc"

  mv "$tmp" "$zshrc"
  ok "~/.zshrc 中 Android 环境变量已清理"
  ok "请运行 source ~/.zshrc 使更改生效"
}

# ─── Print installation status ────────────────────────────────────────────────

print_installation_status() {
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  echo -e "${CYAN}  当前安装状态                            ${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"

  echo -e "${CYAN}[1/3] Android SDK${RESET}"
  if detect_android_home; then
    ok "ANDROID_HOME=$ANDROID_HOME_DETECTED"
    [[ -f "${ANDROID_HOME_DETECTED}/cmdline-tools/latest/bin/sdkmanager" ]] \
      && ok "  cmdline-tools;latest" || warn "  cmdline-tools;latest（未装）"
    [[ -f "${ANDROID_HOME_DETECTED}/platform-tools/adb" ]] \
      && ok "  platform-tools" || warn "  platform-tools（未装）"
    if [[ -d "${ANDROID_HOME_DETECTED}/ndk" ]] && [[ -n "$(ls "${ANDROID_HOME_DETECTED}/ndk" 2>/dev/null)" ]]; then
      ok "  ndk → $(ls "${ANDROID_HOME_DETECTED}/ndk" | sort -V | tail -1)"
    else
      warn "  ndk（未装）"
    fi
    if [[ -d "${ANDROID_HOME_DETECTED}/platforms" ]] && [[ -n "$(ls "${ANDROID_HOME_DETECTED}/platforms" 2>/dev/null)" ]]; then
      ok "  platforms → $(ls "${ANDROID_HOME_DETECTED}/platforms" | tr '\n' ' ')"
    else
      warn "  platforms（未装）"
    fi
    if [[ -d "${ANDROID_HOME_DETECTED}/build-tools" ]] && [[ -n "$(ls "${ANDROID_HOME_DETECTED}/build-tools" 2>/dev/null)" ]]; then
      ok "  build-tools → $(ls "${ANDROID_HOME_DETECTED}/build-tools" | tr '\n' ' ')"
    else
      warn "  build-tools（未装）"
    fi
  else
    warn "未检测到 Android SDK 根目录"
  fi

  echo -e "${CYAN}[2/3] Rust Android 编译目标${RESET}"
  if command -v rustup &>/dev/null || [[ -f "$HOME/.cargo/bin/rustup" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH" 2>/dev/null || true
    local installed
    installed=$(rustup target list --installed 2>/dev/null || echo "")
    local count=0
    for t in "${REQUIRED_TARGETS[@]}"; do
      if echo "$installed" | grep -q "^${t}$"; then
        ok "  $t"
        count=$((count + 1))
      else
        warn "  $t（未装）"
      fi
    done
  else
    warn "未检测到 rustup"
  fi

  echo -e "${CYAN}[3/3] 环境变量（~/.zshrc）${RESET}"
  if [[ -f "$HOME/.zshrc" ]] && grep -q "ANDROID_HOME" "$HOME/.zshrc" 2>/dev/null; then
    ok "ANDROID_HOME 已配置"
  else
    warn "ANDROID_HOME 未在 ~/.zshrc 中配置"
  fi
  if [[ -f "$HOME/.zshrc" ]] && grep -q "ANDROID_NDK_HOME" "$HOME/.zshrc" 2>/dev/null; then
    ok "ANDROID_NDK_HOME 已配置"
  else
    warn "ANDROID_NDK_HOME 未在 ~/.zshrc 中配置"
  fi

  # 是否完全没装
  if ! detect_android_home && ! (command -v rustup &>/dev/null && rustup target list --installed 2>/dev/null | grep -q "linux-android"); then
    if [[ ! -f "$HOME/.zshrc" ]] || ! grep -q "ANDROID_HOME" "$HOME/.zshrc" 2>/dev/null; then
      echo ""
      echo -e "${GREEN}  未检测到任何 install_android_sdk_macos.sh 装过的内容，无需卸载。${RESET}"
      exit 0
    fi
  fi
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

FAILED=0

echo ""
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo -e "${RED}  Android SDK 卸载（macOS）              ${RESET}"
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo ""

print_installation_status

warn "本脚本会卸载 Android 开发工具，可能影响其它项目。"
echo ""

select_option "请选择要卸载的内容：" \
  "Rust Android 编译目标（保留 Android SDK）" \
  "Android SDK 目录 + 环境变量（保留 Rust Android targets）" \
  "全部卸载（Rust targets + Android SDK + 环境变量）"

case "$SELECTED_OPTION" in
  1) remove_rust_android_targets ;;
  2)
    remove_android_sdk_dir
    clean_env_vars
    ;;
  3)
    warn "即将依次卸载：Rust Android targets → Android SDK 目录 → 环境变量"
    if ! confirm_remove "确认执行全部卸载（请慎重）"; then
      echo ""
      echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
      exit 0
    fi
    remove_rust_android_targets
    remove_android_sdk_dir
    clean_env_vars
    ;;
  0)
    echo ""
    echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
    exit 0
    ;;
esac

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  卸载结束摘要                            ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"

detect_android_home && SDK_NOW="$ANDROID_HOME_DETECTED" || SDK_NOW=""
if [[ -n "$SDK_NOW" && -d "$SDK_NOW" ]]; then
  echo -e "  Android SDK    ：${YELLOW}仍存在 ($SDK_NOW)${RESET}"
else
  echo -e "  Android SDK    ：${GREEN}已移除${RESET}"
fi

if command -v rustup &>/dev/null; then
  REMAIN=$(rustup target list --installed 2>/dev/null | grep "linux-android" | wc -l | tr -d ' ')
  if [[ "$REMAIN" -eq 0 ]]; then
    echo -e "  Rust targets   ：${GREEN}已移除${RESET}"
  else
    echo -e "  Rust targets   ：${YELLOW}仍存在 ($REMAIN 个)${RESET}"
  fi
else
  echo -e "  Rust targets   ：${YELLOW}rustup 未检测到，无法确认${RESET}"
fi

if [[ -f "$HOME/.zshrc" ]] && grep -q "ANDROID_HOME" "$HOME/.zshrc" 2>/dev/null; then
  echo -e "  ~/.zshrc       ：${YELLOW}仍含 ANDROID 配置${RESET}"
else
  echo -e "  ~/.zshrc       ：${GREEN}已清理${RESET}"
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  卸载完成！${RESET}"
else
  echo -e "${YELLOW}  卸载流程已结束，但部分步骤失败，请查看上方日志。${RESET}"
fi

exit "$FAILED"
