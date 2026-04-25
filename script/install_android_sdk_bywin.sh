#!/usr/bin/env bash
# install_android_sdk_bywin.sh — Windows (Git Bash / MSYS2) Android SDK 自动安装脚本
# 通过 sdkmanager 安装 Tauri 2 Android 编译所需的全部 SDK 组件
#
# 前置条件：
#   - 已安装 JDK 17+
#   - 已存在 sdkmanager.bat（默认路径：C:\DevDisk\DevTools\AndroidSDK\cmdline-tools\latest\bin\sdkmanager.bat）
#
# 用法：
#   ./install_android_sdk_bywin.sh              # 交互式安装（会提示确认）
#   ./install_android_sdk_bywin.sh -y           # 静默安装（自动确认所有许可）

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*"; }

# ─── Parse args ───────────────────────────────────────────────────────────────
AUTO_ACCEPT=0
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  AUTO_ACCEPT=1
fi

# ─── Confirm helper ──────────────────────────────────────────────────────────
confirm_install() {
  local desc="$1"
  if [[ "$AUTO_ACCEPT" -eq 1 ]]; then
    echo -e "${YELLOW}  自动确认：${desc}${RESET}"
    return 0
  fi
  echo -e "${YELLOW}  ? ${desc} 是否继续？[Y/n]${RESET}"
  read -r answer
  case "$answer" in
    n|N|no|No|NO) return 1 ;;
    *) return 0 ;;
  esac
}

# ─── Bootstrap sdkmanager（自动下载 Android 命令行工具包） ───────────────────
# 参数：$1 = SDK 根目录（如 C:/DevDisk/DevTools/AndroidSDK）
# 完成后：${sdk_root}/cmdline-tools/latest/bin/sdkmanager.bat 可用
bootstrap_sdkmanager() {
  local sdk_root="$1"
  # Android 官方命令行工具包（Windows 版本）
  # 版本 11076708 = cmdline-tools 12.0（稳定版本，2024 年发布）
  local zip_name="commandlinetools-win-11076708_latest.zip"
  # 多镜像源（按顺序尝试）：华为云 → 腾讯云 → Google 官方
  local zip_urls=(
    "https://mirrors.huaweicloud.com/android/repository/${zip_name}"
    "https://mirrors.cloud.tencent.com/AndroidSDK/${zip_name}"
    "https://dl.google.com/android/repository/${zip_name}"
  )

  mkdir -p "${sdk_root}/cmdline-tools"

  local tmp_zip tmp_extract
  tmp_zip="$(mktemp /tmp/cmdline-tools_XXXXXX.zip)"
  tmp_extract="$(mktemp -d /tmp/cmdline-tools_extract_XXXXXX)"

  # 依次尝试镜像源；--ssl-no-revoke 解决 Windows schannel CRYPT_E_REVOCATION_OFFLINE
  local downloaded=0
  for url in "${zip_urls[@]}"; do
    echo -e "${CYAN}  尝试下载：${url}${RESET}"
    if curl -fSL --ssl-no-revoke --connect-timeout 15 -o "$tmp_zip" "$url"; then
      ok "下载完成（来源：${url}）"
      downloaded=1
      break
    else
      warn "下载失败，尝试下一个镜像 ..."
    fi
  done

  if [[ "$downloaded" -ne 1 ]]; then
    fail "所有镜像源下载失败"
    rm -rf "$tmp_zip" "$tmp_extract"
    return 1
  fi

  echo -e "${CYAN}  解压到临时目录 ...${RESET}"
  if command -v unzip &>/dev/null; then
    if ! unzip -q "$tmp_zip" -d "$tmp_extract"; then
      fail "unzip 解压失败"
      rm -rf "$tmp_zip" "$tmp_extract"
      return 1
    fi
  else
    # 退路：PowerShell Expand-Archive
    local zip_win extract_win
    zip_win="$(cygpath -w "$tmp_zip")"
    extract_win="$(cygpath -w "$tmp_extract")"
    if ! powershell -NoProfile -Command "Expand-Archive -LiteralPath '$zip_win' -DestinationPath '$extract_win' -Force"; then
      fail "PowerShell Expand-Archive 解压失败"
      rm -rf "$tmp_zip" "$tmp_extract"
      return 1
    fi
  fi

  # 解压后结构：${tmp_extract}/cmdline-tools/{bin,lib,...}
  # 需移到：${sdk_root}/cmdline-tools/latest/{bin,lib,...}
  if [[ ! -d "${tmp_extract}/cmdline-tools" ]]; then
    fail "解压后未找到 cmdline-tools 目录"
    rm -rf "$tmp_zip" "$tmp_extract"
    return 1
  fi

  rm -rf "${sdk_root}/cmdline-tools/latest"
  mv "${tmp_extract}/cmdline-tools" "${sdk_root}/cmdline-tools/latest"
  rm -rf "$tmp_zip" "$tmp_extract"

  if [[ -f "${sdk_root}/cmdline-tools/latest/bin/sdkmanager.bat" ]]; then
    ok "sdkmanager 已安装：${sdk_root}/cmdline-tools/latest/bin/sdkmanager.bat"
    return 0
  fi
  fail "安装后仍未找到 sdkmanager.bat"
  return 1
}

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}  Android SDK 自动安装脚本（Windows Git Bash）         ${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo ""

# ─── 1. Locate sdkmanager ─────────────────────────────────────────────────────
echo -e "${CYAN}[1/4] 定位 sdkmanager${RESET}"

# 优先使用用户指定的路径
SDKMANAGER="C:/DevDisk/DevTools/AndroidSDK/cmdline-tools/latest/bin/sdkmanager.bat"

# 如果指定路径不存在，尝试 ANDROID_HOME 下的路径
if [[ ! -f "$SDKMANAGER" ]]; then
  ANDROID_HOME_CANDIDATE="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$ANDROID_HOME_CANDIDATE" ]]; then
    ALT_SDKMANAGER="${ANDROID_HOME_CANDIDATE}/cmdline-tools/latest/bin/sdkmanager.bat"
    if [[ -f "$ALT_SDKMANAGER" ]]; then
      SDKMANAGER="$ALT_SDKMANAGER"
    fi
  fi
fi

# 尝试 Windows 默认 SDK 路径
if [[ ! -f "$SDKMANAGER" ]]; then
  WIN_SDK_PATH="$LOCALAPPDATA/Android/Sdk"
  if [[ -z "$WIN_SDK_PATH" ]]; then
    WIN_SDK_PATH="$(cygpath -u "$LOCALAPPDATA/Android/Sdk" 2>/dev/null || echo "$USERPROFILE/AppData/Local/Android/Sdk")"
  fi
  ALT_SDKMANAGER="${WIN_SDK_PATH}/cmdline-tools/latest/bin/sdkmanager.bat"
  if [[ -f "$ALT_SDKMANAGER" ]]; then
    SDKMANAGER="$ALT_SDKMANAGER"
  fi
fi

if [[ -f "$SDKMANAGER" ]]; then
  ok "sdkmanager 已找到：$SDKMANAGER"
else
  warn "sdkmanager 未找到：$SDKMANAGER"
  # 默认 SDK 根目录（与脚本顶部默认路径一致）
  SDK_ROOT_DEFAULT="C:/DevDisk/DevTools/AndroidSDK"
  if confirm_install "自动下载 Android 命令行工具包到 ${SDK_ROOT_DEFAULT}"; then
    if bootstrap_sdkmanager "$SDK_ROOT_DEFAULT"; then
      SDKMANAGER="${SDK_ROOT_DEFAULT}/cmdline-tools/latest/bin/sdkmanager.bat"
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

# 推导 ANDROID_HOME（sdkmanager 所在 SDK 根目录）
# 路径格式：.../AndroidSDK/cmdline-tools/latest/bin/sdkmanager.bat
#   从 bin/ 向上 3 级：bin → latest → cmdline-tools → AndroidSDK（SDK 根目录）
SDKMANAGER_DIR="$(cd "$(dirname "$SDKMANAGER")" && pwd)"
ANDROID_HOME="$(cd "$SDKMANAGER_DIR/../../.." && pwd)"
ok "ANDROID_HOME 推导为：$ANDROID_HOME"

# ─── 2. Check Java ────────────────────────────────────────────────────────────
echo -e "${CYAN}[2/4] 检查 Java 环境${RESET}"
if command -v java &>/dev/null; then
  JAVA_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
  if [[ "$JAVA_VER" -ge 17 ]]; then
    ok "Java $JAVA_VER 已安装：$(which java)"
  else
    fail "检测到 Java $JAVA_VER，但 sdkmanager 需要 JDK 17+。"
    fail "请从 https://adoptium.net/ 下载 JDK 17+"
    exit 1
  fi
else
  fail "未找到 Java，sdkmanager 需要 JDK 17+ 才能运行。"
  fail "请从 https://adoptium.net/ 下载 JDK 17+"
  exit 1
fi

# ─── 3. Define SDK packages ──────────────────────────────────────────────────
echo -e "${CYAN}[3/4] 准备安装的 SDK 组件${RESET}"

# Tauri 2 Android 编译所需组件（对应 build_bywin.sh 的检查项）
# - platform-tools: 提供 adb（检查项 4）
# - cmdline-tools;latest: 提供 sdkmanager（检查项 4）
# - ndk;27.0.12077973: 提供 NDK（检查项 5）— 指定版本，ndk-bundle 已废弃且版本过旧
# - platforms;android-34: Android API 34 平台（Gradle 编译依赖）
# - build-tools;34.0.0: Android 构建工具（Gradle 编译依赖）

SDK_PACKAGES=(
  "platform-tools"
  "cmdline-tools;latest"
  "ndk;27.0.12077973"
  "platforms;android-34"
  "build-tools;34.0.0"
)

for pkg in "${SDK_PACKAGES[@]}"; do
  echo "    $pkg"
done
echo ""

# ─── 4. Install ───────────────────────────────────────────────────────────────
echo -e "${CYAN}[4/4] 安装 SDK 组件${RESET}"

# sdkmanager 是 .bat 文件，在 Git Bash 中需要通过 cmd.exe /c 调用
# 但 MSYS2/Git Bash 会自动将 /c /s 等参数转成 Windows 路径，导致 cmd.exe 行为异常
# 解决方案：设置 MSYS_NO_PATHCONV=1 禁止 MSYS 路径自动转换
export MSYS_NO_PATHCONV=1

# 将 Unix 路径转换为 Windows 路径
SDKMANAGER_WIN="$(cygpath -w "$SDKMANAGER" 2>/dev/null || echo "$SDKMANAGER")"
SDK_ROOT_WIN="$(cygpath -w "$ANDROID_HOME" 2>/dev/null || echo "$ANDROID_HOME")"

# 构建安装参数（空格分隔）
INSTALL_ARGS="${SDK_PACKAGES[*]}"

# sdkmanager 需要接受许可协议：
#   - 交互模式：用户手动输入 y
#   - 静默模式：通过 yes 管道自动输入 y
# 注意：使用 yes 管道而非 <<< "y"，因为 cmd.exe 不支持 bash stdin 重定向

if [[ "$AUTO_ACCEPT" -eq 1 ]]; then
  echo -e "${YELLOW}  静默模式：自动接受所有许可协议${RESET}"
  echo ""
  yes | cmd.exe /c "$SDKMANAGER_WIN" --sdk_root="$SDK_ROOT_WIN" $INSTALL_ARGS || {
    fail "SDK 组件安装失败"
    exit 1
  }
else
  echo -e "${YELLOW}  交互模式：安装过程中需要手动接受许可协议${RESET}"
  echo -e "${YELLOW}  （如需自动接受，请使用 -y 参数重新运行）${RESET}"
  echo ""
  cmd.exe /c "$SDKMANAGER_WIN" --sdk_root="$SDK_ROOT_WIN" $INSTALL_ARGS || {
    fail "SDK 组件安装失败"
    exit 1
  }
fi

echo ""
echo -e "${GREEN}  ✓ SDK 组件安装完成！${RESET}"
echo ""

# ─── 5. Install Rust Android targets ─────────────────────────────────────────
echo -e "${CYAN}[额外] 安装 Rust Android 编译目标${RESET}"
REQUIRED_TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "i686-linux-android"
  "x86_64-linux-android"
)

# 探测 cargo bin 路径（与 install_c_compile_bywin.sh 对齐）：
# Windows 用户 PATH 已更新但当前 shell 未刷新时，bare `command -v rustup` 会误判
if ! command -v rustup &>/dev/null && [[ -f "$HOME/.cargo/bin/rustup.exe" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

if command -v rustup &>/dev/null; then
  INSTALLED_TARGETS=$(rustup target list --installed 2>/dev/null)
  MISSING_TARGETS=()
  for t in "${REQUIRED_TARGETS[@]}"; do
    if echo "$INSTALLED_TARGETS" | grep -q "$t"; then
      ok "  $t（已安装）"
    else
      MISSING_TARGETS+=("$t")
      warn "  $t（未安装）"
    fi
  done

  if [[ ${#MISSING_TARGETS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}  正在安装缺失的 Rust 编译目标...${RESET}"
    for t in "${MISSING_TARGETS[@]}"; do
      echo -e "${CYAN}  rustup target add $t${RESET}"
      rustup target add "$t" || warn "  $t 安装失败，请手动运行：rustup target add $t"
    done
    ok "Rust Android 编译目标安装完成"
  else
    ok "所有 Rust Android 编译目标已就绪"
  fi
else
  warn "未找到 rustup，跳过 Rust Android 编译目标安装"
  warn "请从 https://rustup.rs 安装 Rust 后手动执行："
  for t in "${REQUIRED_TARGETS[@]}"; do
    echo "    rustup target add $t"
  done
fi

# ─── 6. Set environment variables ─────────────────────────────────────────────
echo -e "${CYAN}[6/6] 配置环境变量${RESET}"

# 获取 Windows 格式的路径
ANDROID_HOME_WIN="$(cygpath -w "$ANDROID_HOME" 2>/dev/null || echo "$ANDROID_HOME")"

# 检测 NDK 版本，用于设置 ANDROID_NDK_HOME
# NDK 可能安装在 ndk/<version>/ 或 ndk-bundle/ 中
NDK_DIR="${ANDROID_HOME}/ndk"
NDK_BUNDLE_DIR="${ANDROID_HOME}/ndk-bundle"
NDK_VER=""
if [[ -d "$NDK_DIR" ]]; then
  NDK_VER=$(ls "$NDK_DIR" | sort -V | tail -1)
fi
if [[ -z "$NDK_VER" && -d "$NDK_BUNDLE_DIR" ]]; then
  # 从 source.properties 读取版本号
  if [[ -f "${NDK_BUNDLE_DIR}/source.properties" ]]; then
    NDK_VER=$(grep 'Pkg.Revision' "${NDK_BUNDLE_DIR}/source.properties" 2>/dev/null | awk '{print $NF}' || echo "")
  fi
fi

# --- 设置 ANDROID_HOME ---
NEED_SET_ANDROID_HOME=0
# 检查当前系统环境变量是否已正确设置
CURRENT_ANDROID_HOME_WIN="$(cmd.exe /c "echo %ANDROID_HOME%" 2>/dev/null | tr -d '\r')"
if [[ "$CURRENT_ANDROID_HOME_WIN" == "%ANDROID_HOME%" || "$CURRENT_ANDROID_HOME_WIN" != "$ANDROID_HOME_WIN" ]]; then
  NEED_SET_ANDROID_HOME=1
fi

if [[ "$NEED_SET_ANDROID_HOME" -eq 1 ]]; then
  # setx 写入用户级永久环境变量（重启后生效）
  MSYS_NO_PATHCONV=1 cmd.exe /c "setx ANDROID_HOME $ANDROID_HOME_WIN" &>/dev/null && {
    ok "ANDROID_HOME 已写入用户环境变量：$ANDROID_HOME_WIN"
    ok "（新开终端窗口后生效）"
  } || {
    warn "setx 设置 ANDROID_HOME 失败，请手动设置"
    warn "  系统设置 → 环境变量 → 用户变量 → 新建 ANDROID_HOME = $ANDROID_HOME_WIN"
  }
else
  ok "ANDROID_HOME 环境变量已正确设置：$ANDROID_HOME_WIN"
fi

# --- 设置 ANDROID_NDK_HOME ---
if [[ -n "$NDK_VER" ]]; then
  # 确定 NDK 实际路径（ndk/<version>/ 或 ndk-bundle/）
  if [[ -d "${ANDROID_HOME}/ndk/${NDK_VER}" ]]; then
    NDK_HOME_WIN="${ANDROID_HOME_WIN}\\ndk\\${NDK_VER}"
  else
    NDK_HOME_WIN="${ANDROID_HOME_WIN}\\ndk-bundle"
  fi
  NEED_SET_NDK_HOME=0
  CURRENT_NDK_HOME_WIN="$(cmd.exe /c "echo %ANDROID_NDK_HOME%" 2>/dev/null | tr -d '\r')"
  if [[ "$CURRENT_NDK_HOME_WIN" == "%ANDROID_NDK_HOME%" || "$CURRENT_NDK_HOME_WIN" != "$NDK_HOME_WIN" ]]; then
    NEED_SET_NDK_HOME=1
  fi

  if [[ "$NEED_SET_NDK_HOME" -eq 1 ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c "setx ANDROID_NDK_HOME $NDK_HOME_WIN" &>/dev/null && {
      ok "ANDROID_NDK_HOME 已写入用户环境变量：$NDK_HOME_WIN"
      ok "（新开终端窗口后生效）"
    } || {
      warn "setx 设置 ANDROID_NDK_HOME 失败，请手动设置"
      warn "  系统设置 → 环境变量 → 用户变量 → 新建 ANDROID_NDK_HOME = $NDK_HOME_WIN"
    }
  else
    ok "ANDROID_NDK_HOME 环境变量已正确设置：$NDK_HOME_WIN"
  fi
else
  warn "未检测到 NDK 版本，跳过 ANDROID_NDK_HOME 设置"
fi

# --- 设置 PATH（追加 platform-tools）---
PLATFORM_TOOLS_WIN="${ANDROID_HOME_WIN}\\platform-tools"
CURRENT_PATH="$(cmd.exe /c "echo %PATH%" 2>/dev/null | tr -d '\r')"
if [[ "$CURRENT_PATH" != *"$PLATFORM_TOOLS_WIN"* ]]; then
  # 追加到用户 PATH（setx 有 1024 字符限制，需谨慎）
  # 获取当前用户 PATH（不含系统 PATH）
  USER_PATH="$(powershell -Command "[Environment]::GetEnvironmentVariable('PATH','User')" 2>/dev/null | tr -d '\r')"
  if [[ -n "$USER_PATH" ]]; then
    NEW_USER_PATH="${USER_PATH};${PLATFORM_TOOLS_WIN}"
  else
    NEW_USER_PATH="$PLATFORM_TOOLS_WIN"
  fi
  # setx 限制 1024 字符，超出则跳过
  if [[ ${#NEW_USER_PATH} -le 1024 ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c "setx PATH $NEW_USER_PATH" &>/dev/null && {
      ok "PATH 已追加：$PLATFORM_TOOLS_WIN"
      ok "（新开终端窗口后生效）"
    } || {
      warn "setx 设置 PATH 失败，请手动添加"
      warn "  系统设置 → 环境变量 → 用户变量 → 编辑 PATH → 添加 $PLATFORM_TOOLS_WIN"
    }
  else
    warn "用户 PATH 过长（${#NEW_USER_PATH} 字符），超出 setx 1024 字符限制"
    warn "请手动添加到 PATH：$PLATFORM_TOOLS_WIN"
  fi
else
  ok "PATH 已包含 platform-tools：$PLATFORM_TOOLS_WIN"
fi

# --- 修复已损坏的环境变量（值中包含多余引号）---
# 之前版本的脚本使用 setx ANDROID_HOME "path"，导致值中包含双引号字符
# 需要检测并重新设置，去掉引号
echo -e "${CYAN}[修复] 检查并修复环境变量中的引号问题${RESET}"

FIX_NEEDED=0
CURRENT_ANDROID_HOME_RAW="$(cmd.exe /c "echo %ANDROID_HOME%" 2>/dev/null | tr -d '\r')"
if [[ "$CURRENT_ANDROID_HOME_RAW" == \"*\" ]]; then
  warn "ANDROID_HOME 值包含多余引号：$CURRENT_ANDROID_HOME_RAW"
  FIX_NEEDED=1
fi

CURRENT_NDK_HOME_RAW="$(cmd.exe /c "echo %ANDROID_NDK_HOME%" 2>/dev/null | tr -d '\r')"
if [[ -n "${NDK_VER:-}" && "$CURRENT_NDK_HOME_RAW" == \"*\" ]]; then
  warn "ANDROID_NDK_HOME 值包含多余引号：$CURRENT_NDK_HOME_RAW"
  FIX_NEEDED=1
fi

if [[ "$FIX_NEEDED" -eq 1 ]]; then
  echo -e "${YELLOW}  正在修复环境变量（去掉引号）...${RESET}"
  # 重新设置 ANDROID_HOME（不带引号）
  MSYS_NO_PATHCONV=1 cmd.exe /c "setx ANDROID_HOME $ANDROID_HOME_WIN" &>/dev/null && {
    ok "ANDROID_HOME 已修复：$ANDROID_HOME_WIN"
  } || {
    warn "修复 ANDROID_HOME 失败，请手动检查"
  }
  # 重新设置 ANDROID_NDK_HOME（不带引号）
  if [[ -n "${NDK_VER:-}" ]]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c "setx ANDROID_NDK_HOME $NDK_HOME_WIN" &>/dev/null && {
      ok "ANDROID_NDK_HOME 已修复：$NDK_HOME_WIN"
    } || {
      warn "修复 ANDROID_NDK_HOME 失败，请手动检查"
    }
  fi
  ok "环境变量引号问题已修复（新开终端窗口后生效）"
else
  ok "环境变量值无引号问题"
fi

# --- 当前 shell 立即生效 ---
export ANDROID_HOME="$ANDROID_HOME"
if [[ -n "$NDK_VER" ]]; then
  if [[ -d "${ANDROID_HOME}/ndk/${NDK_VER}" ]]; then
    export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${NDK_VER}"
  else
    export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk-bundle"
  fi
fi
export PATH="${ANDROID_HOME}/platform-tools:${PATH}"
ok "当前 shell 环境变量已生效（export）"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  Android SDK 安装 & 配置完成！${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${YELLOW}  注意：setx 设置的环境变量需要新开终端窗口才会生效${RESET}"
echo ""
echo -e "${CYAN}  现在可以运行构建脚本：${RESET}"
echo "    ./script/build_bywin.sh dev"
echo "    ./script/build_bywin.sh build"
echo ""
