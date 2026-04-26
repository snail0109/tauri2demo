#!/usr/bin/env bash
# remove_android_sdk_bywin.sh — install_android_sdk_bywin.sh 的反向操作
# 功能：
#   按用户选择卸载以下任一组合：
#     1) Rust Android 编译目标（保留 Android SDK）
#     2) Android SDK 目录 + 环境变量（保留 Rust Android targets）
#     3) 全部卸载（Rust targets + Android SDK + 环境变量）
#
# 运行环境：Windows Git Bash / MSYS2。
# 注意：所有破坏性操作默认需用户确认；可通过 -y / --yes 自动确认（请谨慎）。

set -euo pipefail

AUTO_YES=0
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  AUTO_YES=1
fi

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

FAILED=0

ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*"; FAILED=1; }

# 卸载默认 NO（与安装脚本相反），避免误操作
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

# ─── 探测 cargo bin 路径（与 install_c_compile_bywin.sh 的 check_rust 对齐） ─
probe_cargo_bin() {
  if ! command -v rustup &>/dev/null && [[ -f "$HOME/.cargo/bin/rustup.exe" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
}

# ─── 解析 Android SDK 根目录 ────────────────────────────────────────────────
# 顺序：环境变量 ANDROID_HOME / ANDROID_SDK_ROOT → 默认安装路径 → 备选路径
# 返回值通过全局变量 ANDROID_HOME_DETECTED 暴露
ANDROID_HOME_DETECTED=""
detect_android_home() {
  local cand="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  # 清理引号
  cand="${cand#\"}"
  cand="${cand%\"}"
  # Windows 路径转 Unix
  if [[ -n "$cand" ]]; then
    if [[ "$cand" == *'\\'* ]] || [[ "$cand" =~ ^[A-Za-z]: ]]; then
      cand="$(cygpath -u "$cand" 2>/dev/null || echo "$cand")"
    fi
  fi
  if [[ -n "$cand" && -d "$cand" ]]; then
    ANDROID_HOME_DETECTED="$cand"
    return 0
  fi

  local candidates=(
    "C:/DevDisk/DevTools/AndroidSDK"
    "$LOCALAPPDATA/Android/Sdk"
    "$HOME/AppData/Local/Android/Sdk"
  )
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      ANDROID_HOME_DETECTED="$c"
      return 0
    fi
  done
  return 1
}

# ─── 卸载 Rust Android 编译目标 ─────────────────────────────────────────────
REQUIRED_TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "i686-linux-android"
  "x86_64-linux-android"
)

remove_rust_android_targets() {
  if ! command -v rustup &>/dev/null; then
    warn "未检测到 rustup，跳过 Rust Android 编译目标卸载"
    return 0
  fi

  local installed
  installed=$(rustup target list --installed 2>/dev/null)
  local present=()
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

# ─── 强制结束 Android 相关进程（避免文件被占用导致 rm 失败） ───────────────
kill_android_processes() {
  warn "正在结束 adb / Android Studio / Gradle 相关进程..."

  # 按进程名直接 taskkill（/F 强制 /T 含子进程）
  local procs=(adb.exe studio64.exe studio.exe gradle.exe fsnotifier.exe)
  for p in "${procs[@]}"; do
    if cmd.exe /c "tasklist /FI \"IMAGENAME eq $p\" /NH" 2>/dev/null | grep -qi "$p"; then
      if cmd.exe /c "taskkill /F /IM $p /T" >/dev/null 2>&1; then
        ok "已结束 $p"
      else
        warn "结束 $p 失败（可能权限不足）"
      fi
    fi
  done

  # Gradle daemon 是 java.exe 子进程，按命令行特征匹配
  powershell -NoProfile -Command "
    Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" |
      Where-Object { \$_.CommandLine -match 'GradleDaemon|gradle-launcher|kotlin-compiler' } |
      ForEach-Object {
        try { Stop-Process -Id \$_.ProcessId -Force -ErrorAction Stop; Write-Host \"  killed java.exe PID=\$(\$_.ProcessId)\" } catch {}
      }
  " 2>/dev/null || true

  # 等待 Windows 释放文件句柄
  sleep 1
  ok "进程清理完成"
}

# ─── 删除 Android SDK 目录 ──────────────────────────────────────────────────
remove_android_sdk_dir() {
  if ! detect_android_home; then
    warn "未检测到 Android SDK 安装目录，跳过"
    return 0
  fi
  local sdk="$ANDROID_HOME_DETECTED"

  warn "删除 SDK 目录将移除以下组件：platform-tools / cmdline-tools / ndk / platforms / build-tools"
  if ! confirm_remove "删除整个 Android SDK 目录：${sdk}"; then
    warn "已跳过 Android SDK 目录删除"
    return 0
  fi

  # 主动结束占用文件的进程
  kill_android_processes

  if rm -rf "$sdk" 2>&1; then
    if [[ -d "$sdk" ]]; then
      fail "rm -rf 后目录仍存在：$sdk"
      fail "请手动删除（PowerShell 管理员）："
      local sdk_win
      sdk_win="$(cygpath -w "$sdk" 2>/dev/null || echo "$sdk")"
      fail "  Remove-Item -Recurse -Force \"$sdk_win\""
    else
      ok "Android SDK 目录已删除：$sdk"
    fi
  else
    fail "rm -rf $sdk 失败（可能仍有文件被占用）"
  fi
}

# ─── 清理 Android 相关环境变量 ──────────────────────────────────────────────
# 清理：ANDROID_HOME / ANDROID_NDK_HOME / 用户 PATH 中的 platform-tools 段
remove_android_env_vars() {
  if ! confirm_remove "清理 ANDROID_HOME / ANDROID_NDK_HOME 用户环境变量及 PATH 中的 platform-tools 段"; then
    warn "已跳过环境变量清理"
    return 0
  fi

  # 删除 ANDROID_HOME（用户级）
  if powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable('ANDROID_HOME', \$null, 'User')" 2>/dev/null; then
    ok "ANDROID_HOME 已从用户环境变量移除"
  else
    fail "移除 ANDROID_HOME 失败，请手动到「环境变量」中删除"
  fi

  # 删除 ANDROID_NDK_HOME（用户级）
  if powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable('ANDROID_NDK_HOME', \$null, 'User')" 2>/dev/null; then
    ok "ANDROID_NDK_HOME 已从用户环境变量移除"
  else
    fail "移除 ANDROID_NDK_HOME 失败，请手动到「环境变量」中删除"
  fi

  # 从用户 PATH 中过滤掉 platform-tools 段
  local user_path new_path
  user_path="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('PATH','User')" 2>/dev/null | tr -d '\r')"
  if [[ -n "$user_path" ]]; then
    # 用 PowerShell 一次性过滤含 "platform-tools" 的段，避免 bash 处理 Windows 反斜杠的麻烦
    if powershell -NoProfile -Command "
      \$p = [Environment]::GetEnvironmentVariable('PATH','User');
      if (\$p) {
        \$kept = (\$p -split ';' | Where-Object { \$_ -and (\$_ -notmatch 'platform-tools') }) -join ';';
        [Environment]::SetEnvironmentVariable('PATH', \$kept, 'User')
      }
    " 2>/dev/null; then
      ok "用户 PATH 中的 platform-tools 段已清理"
    else
      fail "清理用户 PATH 失败，请手动到「环境变量」中编辑 PATH"
    fi
  else
    warn "用户 PATH 为空，跳过"
  fi

  ok "环境变量清理完成（新开终端窗口后生效）"
}

# ─── 检测安装状态（与 install_android_sdk_bywin.sh 的检测口径一致） ────────
# 全局变量：
#   INSTALLED_SDK_ROOT   — Android SDK 根目录（空表示未装）
#   INSTALLED_RUST_COUNT — 已安装的 Android Rust target 数量
#   INSTALLED_ENV_AH     — 用户环境变量 ANDROID_HOME 的值
#   INSTALLED_ENV_NDK    — 用户环境变量 ANDROID_NDK_HOME 的值
INSTALLED_SDK_ROOT=""
INSTALLED_RUST_COUNT=0
INSTALLED_ENV_AH=""
INSTALLED_ENV_NDK=""

print_installation_status() {
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  echo -e "${CYAN}  当前安装状态检测                         ${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"

  # ─── 1) Android SDK 根目录 + 各组件 ──────────────────────────────────────
  echo -e "${CYAN}[1/3] Android SDK${RESET}"
  if detect_android_home; then
    INSTALLED_SDK_ROOT="$ANDROID_HOME_DETECTED"
    ok "ANDROID_HOME=$INSTALLED_SDK_ROOT"
    # 与 install 脚本中 SDK_PACKAGES 列表对齐
    [[ -f "${INSTALLED_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager.bat" ]] \
      && ok "  cmdline-tools;latest" || warn "  cmdline-tools;latest（未装）"
    [[ -f "${INSTALLED_SDK_ROOT}/platform-tools/adb.exe" ]] \
      && ok "  platform-tools" || warn "  platform-tools（未装）"
    if [[ -d "${INSTALLED_SDK_ROOT}/ndk" ]] && [[ -n "$(ls "${INSTALLED_SDK_ROOT}/ndk" 2>/dev/null)" ]]; then
      ok "  ndk → $(ls "${INSTALLED_SDK_ROOT}/ndk" | sort -V | tail -1)"
    elif [[ -d "${INSTALLED_SDK_ROOT}/ndk-bundle" ]]; then
      ok "  ndk-bundle（旧版）"
    else
      warn "  ndk（未装）"
    fi
    if [[ -d "${INSTALLED_SDK_ROOT}/platforms" ]] && [[ -n "$(ls "${INSTALLED_SDK_ROOT}/platforms" 2>/dev/null)" ]]; then
      ok "  platforms → $(ls "${INSTALLED_SDK_ROOT}/platforms" | tr '\n' ' ')"
    else
      warn "  platforms（未装）"
    fi
    if [[ -d "${INSTALLED_SDK_ROOT}/build-tools" ]] && [[ -n "$(ls "${INSTALLED_SDK_ROOT}/build-tools" 2>/dev/null)" ]]; then
      ok "  build-tools → $(ls "${INSTALLED_SDK_ROOT}/build-tools" | tr '\n' ' ')"
    else
      warn "  build-tools（未装）"
    fi
  else
    warn "未检测到 Android SDK 根目录"
  fi

  # ─── 2) Rust Android 编译目标 ─────────────────────────────────────────────
  echo -e "${CYAN}[2/3] Rust Android 编译目标${RESET}"
  if command -v rustup &>/dev/null; then
    local installed
    installed=$(rustup target list --installed 2>/dev/null)
    INSTALLED_RUST_COUNT=0
    for t in "${REQUIRED_TARGETS[@]}"; do
      if echo "$installed" | grep -q "^${t}$"; then
        ok "  $t"
        ((INSTALLED_RUST_COUNT++))
      else
        warn "  $t（未装）"
      fi
    done
  else
    warn "未检测到 rustup"
  fi

  # ─── 3) 用户环境变量 ─────────────────────────────────────────────────────
  echo -e "${CYAN}[3/3] 用户环境变量${RESET}"
  INSTALLED_ENV_AH="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('ANDROID_HOME','User')" 2>/dev/null | tr -d '\r')"
  INSTALLED_ENV_NDK="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME','User')" 2>/dev/null | tr -d '\r')"
  [[ -n "$INSTALLED_ENV_AH" ]]  && ok "ANDROID_HOME=$INSTALLED_ENV_AH"        || warn "ANDROID_HOME 未设置"
  [[ -n "$INSTALLED_ENV_NDK" ]] && ok "ANDROID_NDK_HOME=$INSTALLED_ENV_NDK"   || warn "ANDROID_NDK_HOME 未设置"

  # 是否完全没装
  if [[ -z "$INSTALLED_SDK_ROOT" && "$INSTALLED_RUST_COUNT" -eq 0 \
        && -z "$INSTALLED_ENV_AH" && -z "$INSTALLED_ENV_NDK" ]]; then
    echo ""
    echo -e "${GREEN}  未检测到任何 install_android_sdk_bywin.sh 装过的内容，无需卸载。${RESET}"
    exit 0
  fi
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

probe_cargo_bin

echo ""
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo -e "${RED}  Android SDK 卸载（Windows Git Bash）   ${RESET}"
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo ""

# 卸载前先做安装检测，逻辑与 install_android_sdk_bywin.sh 对齐
print_installation_status

warn "本脚本会卸载 Android 开发工具，可能影响其它项目。请确认你了解每一步。"
echo ""

select_option "请选择要卸载的内容：" \
  "Rust Android 编译目标（保留 Android SDK）" \
  "Android SDK 目录 + 环境变量（保留 Rust Android targets）" \
  "全部卸载（Rust targets + Android SDK + 环境变量）"

case "$SELECTED_OPTION" in
  1)
    remove_rust_android_targets
    ;;
  2)
    remove_android_sdk_dir
    remove_android_env_vars
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
    remove_android_env_vars
    ;;
  0)
    echo ""
    echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
    exit 0
    ;;
esac

# ─── 卸载摘要 ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  卸载结束摘要                            ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"

# Android SDK 目录
detect_android_home && SDK_NOW="$ANDROID_HOME_DETECTED" || SDK_NOW=""
if [[ -n "$SDK_NOW" && -d "$SDK_NOW" ]]; then
  echo -e "  Android SDK    ：${YELLOW}仍存在 ($SDK_NOW)${RESET}"
else
  echo -e "  Android SDK    ：${GREEN}已移除${RESET}"
fi

# Rust Android targets
if command -v rustup &>/dev/null; then
  REMAIN=$(rustup target list --installed 2>/dev/null | grep -E "linux-android" | wc -l | tr -d ' ')
  if [[ "$REMAIN" -eq 0 ]]; then
    echo -e "  Rust targets   ：${GREEN}已移除${RESET}"
  else
    echo -e "  Rust targets   ：${YELLOW}仍存在 ($REMAIN 个)${RESET}"
  fi
else
  echo -e "  Rust targets   ：${YELLOW}rustup 未检测到，无法确认${RESET}"
fi

# 环境变量
ENV_AH="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('ANDROID_HOME','User')" 2>/dev/null | tr -d '\r')"
ENV_NDK="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME','User')" 2>/dev/null | tr -d '\r')"
echo -e "  ANDROID_HOME   ：$([[ -z "$ENV_AH" ]]  && echo -e "${GREEN}已移除${RESET}" || echo -e "${YELLOW}仍存在 ($ENV_AH)${RESET}")"
echo -e "  ANDROID_NDK_HOME：$([[ -z "$ENV_NDK" ]] && echo -e "${GREEN}已移除${RESET}" || echo -e "${YELLOW}仍存在 ($ENV_NDK)${RESET}")"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  卸载完成！${RESET}"
else
  echo -e "${YELLOW}  卸载流程已结束，但部分步骤失败或未完成，请查看上方日志手动处理。${RESET}"
fi
