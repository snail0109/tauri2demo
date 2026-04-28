#!/usr/bin/env bash
# install_android_sdk_macos.sh — macOS Android SDK 自动安装脚本
# 通过 sdkmanager 安装 Tauri 2 Android 编译所需的全部 SDK 组件
#
# 前置条件：
#   - Xcode Command Line Tools（提供 curl / unzip 等）
#
# 用法：
#   ./install_android_sdk_macos.sh              # 交互式安装
#   ./install_android_sdk_macos.sh -y           # 静默安装（自动接受许可）
#   ./install_android_sdk_macos.sh --sdk-root <path>  # 指定 SDK 根目录

set -euo pipefail

source "$(dirname "$0")/_common.sh"

# ─── Parse args ───────────────────────────────────────────────────────────────
SDK_ROOT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      shift
      ;;
    --sdk-root)
      SDK_ROOT_ARG="${2:-}"
      shift 2
      ;;
    --sdk-root=*)
      SDK_ROOT_ARG="${1#--sdk-root=}"
      shift
      ;;
    -h|--help)
      echo "用法：$0 [-y|--yes] [--sdk-root <path>]"
      echo "  -y / --yes        静默模式（自动接受许可）"
      echo "  --sdk-root <path> 指定 Android SDK 根目录（默认 ~/Library/Android/sdk）"
      exit 0
      ;;
    *)
      echo "错误：未知参数 $1" >&2
      exit 1
      ;;
  esac
done

# SDK 根目录：命令行 > 环境变量 ANDROID_HOME > 默认路径
SDK_ROOT_DEFAULT="${SDK_ROOT_ARG:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"

# ─── Java JDK 17+ ─────────────────────────────────────────────────────────────

install_java() {
  echo -e "${CYAN}[*] 检查 Java JDK（17+）${RESET}"

  if check_java17; then
    return 0
  fi

  if command -v brew &>/dev/null; then
    if confirm_install "通过 Homebrew 安装 openjdk@17"; then
      echo -e "${CYAN}  brew install openjdk@17 ...${RESET}"
      brew install openjdk@17 2>&1 || {
        fail "brew install openjdk@17 失败"
        return 1
      }
      ok "openjdk@17 安装成功"
      export JAVA_HOME="$(brew --prefix openjdk@17 2>/dev/null || echo "")"
      if [[ -n "$JAVA_HOME" ]]; then
        export PATH="$JAVA_HOME/bin:$PATH"
      fi
      return 0
    fi
  fi

  fail "请手动安装 JDK 17+"
  fail "  • brew install openjdk@17"
  fail "  • 或从 https://adoptium.net 下载"
  return 1
}

# ─── Bootstrap sdkmanager ─────────────────────────────────────────────────────
# 下载 Android 命令行工具包并解压到 SDK 根目录

bootstrap_sdkmanager() {
  local sdk_root="$1"
  local zip_name="commandlinetools-mac-11076708_latest.zip"
  local zip_urls=(
    "https://mirrors.huaweicloud.com/android/repository/${zip_name}"
    "https://mirrors.cloud.tencent.com/AndroidSDK/${zip_name}"
    "https://dl.google.com/android/repository/${zip_name}"
  )

  mkdir -p "${sdk_root}/cmdline-tools"

  local tmp_zip tmp_extract
  tmp_zip="$(mktemp /tmp/cmdline-tools_XXXXXX.zip)"
  tmp_extract="$(mktemp -d /tmp/cmdline-tools_extract_XXXXXX)"

  local downloaded=0
  for url in "${zip_urls[@]}"; do
    echo -e "${CYAN}  尝试下载：${url}${RESET}"
    if curl -fSL --connect-timeout 15 -o "$tmp_zip" "$url" 2>/dev/null; then
      ok "下载完成（来源：${url}）"
      downloaded=1
      break
    else
      warn "下载失败，尝试下一个镜像 ..."
    fi
  done

  if [[ "$downloaded" -ne 1 ]]; then
    fail "所有镜像源下载失败"
    rm -rf "$tmp_zip" "$tmp_extract" 2>/dev/null || true
    return 1
  fi

  echo -e "${CYAN}  解压到 SDK 目录 ...${RESET}"
  if ! unzip -q "$tmp_zip" -d "$tmp_extract" 2>/dev/null; then
    fail "unzip 解压失败"
    rm -rf "$tmp_zip" "$tmp_extract" 2>/dev/null || true
    return 1
  fi

  if [[ ! -d "${tmp_extract}/cmdline-tools" ]]; then
    fail "解压后未找到 cmdline-tools 目录"
    rm -rf "$tmp_zip" "$tmp_extract" 2>/dev/null || true
    return 1
  fi

  rm -rf "${sdk_root}/cmdline-tools/latest"
  mv "${tmp_extract}/cmdline-tools" "${sdk_root}/cmdline-tools/latest"
  rm -rf "$tmp_zip" "$tmp_extract" 2>/dev/null || true

  if [[ -f "${sdk_root}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    ok "SDKManager 已安装：${sdk_root}/cmdline-tools/latest/bin/sdkmanager"
    return 0
  fi
  fail "安装后仍未找到 sdkmanager"
  return 1
}

# ─── Install SDK packages ─────────────────────────────────────────────────────

install_sdk_packages() {
  local sdkmanager="$1"
  local android_home="$2"
  shift 2
  local packages=("$@")

  if [[ "$AUTO_YES" -eq 1 ]]; then
    echo -e "${YELLOW}  静默模式：自动接受所有许可协议${RESET}"
    echo ""
    (
      set +o pipefail
      yes | "$sdkmanager" --sdk_root="$android_home" "${packages[@]}" 2>&1
    ) || {
      fail "Android SDK 组件安装失败"
      return 1
    }
  else
    echo -e "${YELLOW}  交互模式：安装过程中需要手动接受许可协议${RESET}"
    echo -e "${YELLOW}  （如需自动接受，请使用 -y 参数重新运行）${RESET}"
    echo ""
    "$sdkmanager" --sdk_root="$android_home" "${packages[@]}" 2>&1 || {
      fail "Android SDK 组件安装失败"
      return 1
    }
  fi
  return 0
}

# ─── Install Rust Android targets ─────────────────────────────────────────────

install_rust_android_targets() {
  echo -e "${CYAN}[*] 安装 Rust Android 编译目标${RESET}"

  ensure_cargo_bin

  if ! command -v rustup &>/dev/null; then
    warn "未找到 rustup，跳过 Rust Android 编译目标安装"
    warn "请从 https://rustup.rs 安装 Rust 后手动执行："
    for t in "${ANDROID_RUST_TARGETS[@]}"; do
      echo "    rustup target add $t"
    done
    return 0
  fi

  local installed_targets missing=()
  installed_targets=$(rustup target list --installed 2>/dev/null)

  for t in "${ANDROID_RUST_TARGETS[@]}"; do
    if echo "$installed_targets" | grep -q "$t"; then
      ok "  $t（已安装）"
    else
      missing+=("$t")
      warn "  $t（未安装）"
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}  正在安装缺失的 Rust 编译目标...${RESET}"
    for t in "${missing[@]}"; do
      echo -e "${CYAN}  rustup target add $t${RESET}"
      rustup target add "$t" || warn "  $t 安装失败，请手动运行：rustup target add $t"
    done
    ok "Rust Android 编译目标安装完成"
  else
    ok "所有 Rust Android 编译目标已就绪"
  fi
}

# ─── Configure environment variables ──────────────────────────────────────────

configure_env_vars() {
  local android_home="$1"

  echo -e "${CYAN}[*] 配置环境变量${RESET}"

  local ndk_ver=""
  if [[ -d "${android_home}/ndk" ]]; then
    ndk_ver=$(ls "${android_home}/ndk" | sort -V | tail -1)
  fi

  local zshrc="$HOME/.zshrc"
  local updated=0

  local content=""
  if [[ -f "$zshrc" ]]; then
    content=$(cat "$zshrc")
  fi

  # ── ANDROID_HOME ──
  if ! echo "$content" | grep -q "export ANDROID_HOME="; then
    echo "" >> "$zshrc"
    echo "# Android SDK（由 install_android_sdk_macos.sh 添加）" >> "$zshrc"
    echo "export ANDROID_HOME=\"$android_home\"" >> "$zshrc"
    ok "ANDROID_HOME 已写入 ~/.zshrc：$android_home"
    updated=1
  else
    local current_ah
    current_ah=$(echo "$content" | grep "export ANDROID_HOME=" | tail -1 | sed 's/.*=//' | tr -d '"')
    if [[ "$current_ah" != "$android_home" ]]; then
      warn "~/.zshrc 中 ANDROID_HOME 已存在但值为 $current_ah，与当前 $android_home 不同"
      warn "请手动检查并更新 ~/.zshrc"
    else
      ok "ANDROID_HOME 已在 ~/.zshrc 中配置：$android_home"
    fi
  fi

  # ── ANDROID_NDK_HOME ──
  if [[ -n "$ndk_ver" ]]; then
    local ndk_home="${android_home}/ndk/${ndk_ver}"
    if ! echo "$content" | grep -q "export ANDROID_NDK_HOME="; then
      echo "export ANDROID_NDK_HOME=\"$ndk_home\"" >> "$zshrc"
      ok "ANDROID_NDK_HOME 已写入 ~/.zshrc：$ndk_home"
      updated=1
    else
      ok "ANDROID_NDK_HOME 已在 ~/.zshrc 中配置"
    fi
  else
    warn "未检测到 NDK，跳过 ANDROID_NDK_HOME 配置"
  fi

  # ── PATH (platform-tools) ──
  local platform_tools="${android_home}/platform-tools"
  if ! echo "$content" | grep -q "platform-tools" 2>/dev/null; then
    echo "export PATH=\"${platform_tools}:\$PATH\"" >> "$zshrc"
    ok "PATH 已追加 platform-tools：$platform_tools"
    updated=1
  else
    ok "PATH 已包含 platform-tools"
  fi

  if [[ "$updated" -eq 1 ]]; then
    echo ""
    warn "~/.zshrc 已更新，请运行以下命令使其生效："
    echo "    source ~/.zshrc"
  fi

  export ANDROID_HOME="$android_home"
  if [[ -n "$ndk_ver" ]]; then
    export ANDROID_NDK_HOME="${android_home}/ndk/${ndk_ver}"
  fi
  export PATH="${android_home}/platform-tools:${PATH}"
  ok "当前 shell 环境变量已生效（export）"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  Android SDK 自动安装（macOS）           ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

# ─── 1. Install Java ──────────────────────────────────────────────────────────
if ! install_java; then
  exit 1
fi

# ─── 2. Locate / bootstrap sdkmanager ─────────────────────────────────────────
echo -e "${CYAN}[*] 定位 SDKManager${RESET}"

SDKMANAGER="${SDK_ROOT_DEFAULT}/cmdline-tools/latest/bin/sdkmanager"

if [[ ! -f "$SDKMANAGER" ]]; then
  ah="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$ah" && -f "${ah}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    SDKMANAGER="${ah}/cmdline-tools/latest/bin/sdkmanager"
    SDK_ROOT_DEFAULT="$ah"
  fi
fi

if [[ -f "$SDKMANAGER" ]]; then
  ok "SDKManager 已找到：$SDKMANAGER"
  sdk_ver=$("$SDKMANAGER" --version 2>/dev/null | grep -E '^[0-9]' | head -1 || true)
  if [[ -n "$sdk_ver" ]]; then
    ok "    版本：$sdk_ver"
  fi
else
  warn "SDKManager 未找到：$SDKMANAGER"
  if confirm_install "自动下载 Android 命令行工具包到 ${SDK_ROOT_DEFAULT}"; then
    if bootstrap_sdkmanager "$SDK_ROOT_DEFAULT"; then
      SDKMANAGER="${SDK_ROOT_DEFAULT}/cmdline-tools/latest/bin/sdkmanager"
    else
      fail "命令行工具包下载/安装失败"
      fail "请手动下载：https://developer.android.com/studio#command-tools"
      exit 1
    fi
  else
    fail "已跳过命令行工具包下载，无法继续"
    exit 1
  fi
fi

SDKMANAGER_DIR="$(cd "$(dirname "$SDKMANAGER")" && pwd)"
ANDROID_HOME="$(cd "$SDKMANAGER_DIR/../../.." && pwd)"
ok "ANDROID_HOME 推导为：$ANDROID_HOME"

# ─── 3. Define SDK packages ──────────────────────────────────────────────────
echo -e "${CYAN}[*] 准备安装的 Android SDK 组件${RESET}"

SDK_PACKAGES=(
  "platform-tools"
  "ndk;27.0.12077973"
  "platforms;android-34"
  "build-tools;34.0.0"
)

if [[ -d "${ANDROID_HOME}/cmdline-tools/latest-2" ]]; then
  warn "检测到遗留目录 cmdline-tools/latest-2，正在清理 ..."
  rm -rf "${ANDROID_HOME}/cmdline-tools/latest-2"
  ok "已清理"
fi

for pkg in "${SDK_PACKAGES[@]}"; do
  echo "    $pkg"
done
echo ""

# ─── 4. Install SDK packages ─────────────────────────────────────────────────
echo -e "${CYAN}[*] 安装 Android SDK 组件${RESET}"
if ! install_sdk_packages "$SDKMANAGER" "$ANDROID_HOME" "${SDK_PACKAGES[@]}"; then
  exit 1
fi

echo ""
ok "Android SDK 组件安装完成！"
echo ""

# ─── 5. Install Rust Android targets ─────────────────────────────────────────
install_rust_android_targets

# ─── 6. Configure environment variables ──────────────────────────────────────
configure_env_vars "$ANDROID_HOME"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}  Android SDK 安装 & 配置完成！${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""
echo -e "${YELLOW}  注意：请运行 source ~/.zshrc 使环境变量永久生效${RESET}"
echo ""
echo -e "${CYAN}  现在可以运行：${RESET}"
echo "    ./script/build_macos.sh dev android"
echo "    ./script/build_macos.sh build android"
echo ""

exit 0
