#!/usr/bin/env bash
# test_env_android_bywin.sh — Windows (Git Bash / MSYS2) Android dev/build helper for Tauri 2
# 用法：
#   ./test_env_android_bywin.sh dev     # 启动 Android 开发模式
#   ./test_env_android_bywin.sh build   # 构建 Android APK/AAB

set -euo pipefail

COMMAND="${1:-}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*"; FAILED=1; }

# ─── Usage ────────────────────────────────────────────────────────────────────
if [[ "$COMMAND" != "dev" && "$COMMAND" != "build" ]]; then
  echo -e "${CYAN}用法：${RESET} $0 <dev|build>"
  echo ""
  echo "  dev    启动 Tauri Android 开发模式（热重载）"
  echo "  build  构建 Android APK/AAB 发布包"
  exit 1
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  Android 环境检查（Windows Git Bash）    ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

FAILED=0

# ─── 1. MSVC Build Tools (cl.exe) ────────────────────────────────────────────
echo -e "${CYAN}[1/8] MSVC 编译工具（cl.exe）${RESET}"
# 检查是否能找到 cl.exe（可能在 Developer Command Prompt 或 VS 环境中）
if command -v cl.exe &>/dev/null; then
  ok "cl.exe 已找到：$(which cl.exe)"
elif command -v cc &>/dev/null && cc --version &>/dev/null; then
  ok "C 编译器已找到：$(which cc) — $(cc --version 2>&1 | head -1)"
else
  fail "未找到 MSVC 编译器（cl.exe）。"
  fail "请安装 Visual Studio Build Tools："
  fail "  https://visualstudio.microsoft.com/visual-cpp-build-tools/"
  fail "安装时勾选「使用 C++ 的桌面开发」工作负载。"
fi

# ─── 2. Java (JDK 17+) ────────────────────────────────────────────────────────
echo -e "${CYAN}[2/8] Java JDK（17+）${RESET}"
if command -v java &>/dev/null; then
  JAVA_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
  if [[ "$JAVA_VER" -ge 17 ]]; then
    ok "Java $JAVA_VER 已安装：$(which java)"
  else
    fail "检测到 Java $JAVA_VER，但需要 JDK 17+。"
    fail "请从 https://adoptium.net/ 下载 JDK 17+，或通过 winget 安装：winget install EclipseAdoptium.Temurin.17.JDK"
  fi
else
  fail "未找到 Java，请从 https://adoptium.net/ 下载 JDK 17+"
  fail "或运行：winget install EclipseAdoptium.Temurin.17.JDK"
fi

# ─── 3. ANDROID_HOME ──────────────────────────────────────────────────────────
echo -e "${CYAN}[3/8] ANDROID_HOME${RESET}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -n "$ANDROID_HOME" && -d "$ANDROID_HOME" ]]; then
  ok "ANDROID_HOME=$ANDROID_HOME"
else
  # Windows 默认 Android SDK 路径
  WIN_SDK_PATH="$LOCALAPPDATA/Android/Sdk"
  if [[ -z "$WIN_SDK_PATH" ]]; then
    WIN_SDK_PATH="$(cygpath -u "$LOCALAPPDATA/Android/Sdk" 2>/dev/null || echo "$USERPROFILE/AppData/Local/Android/Sdk")"
  fi
  if [[ -d "$WIN_SDK_PATH" ]]; then
    export ANDROID_HOME="$WIN_SDK_PATH"
    warn "ANDROID_HOME 未设置，使用默认路径：$ANDROID_HOME"
    warn "建议添加到系统环境变量：ANDROID_HOME=%LOCALAPPDATA%\\Android\\Sdk"
  else
    fail "ANDROID_HOME 未设置且默认路径不存在。"
    fail "请通过 Android Studio 安装 Android SDK，再设置 ANDROID_HOME 环境变量。"
  fi
fi

# ─── 4. Android SDK Tools ─────────────────────────────────────────────────────
echo -e "${CYAN}[4/8] Android SDK 工具（adb、sdkmanager）${RESET}"
# Windows 下可执行文件带 .exe 后缀
if [[ -f "${ANDROID_HOME}/platform-tools/adb.exe" ]]; then
  ok "adb 已找到：${ANDROID_HOME}/platform-tools/adb.exe"
else
  fail "未找到 adb.exe（路径：${ANDROID_HOME}/platform-tools/adb.exe），请在 Android Studio SDK Manager 中安装 platform-tools。"
fi

SDKMANAGER="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager.bat"
if [[ -f "$SDKMANAGER" ]]; then
  ok "sdkmanager 已找到：${SDKMANAGER}"
else
  warn "sdkmanager 未找到：${SDKMANAGER}"
  warn "请在 Android Studio SDK Manager > SDK Tools > Android SDK Command-line Tools 中安装"
  warn "或运行：sdkmanager --install 'cmdline-tools;latest'"
fi

# ─── 5. NDK ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}[5/8] Android NDK${RESET}"
NDK_DIR="${ANDROID_HOME}/ndk"
if [[ -d "$NDK_DIR" ]]; then
  NDK_VER=$(ls "$NDK_DIR" | sort -V | tail -1)
  NDK_PATH="${NDK_DIR}/${NDK_VER}"
  export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$NDK_PATH}"
  if [[ -z "${NDK_VER}" ]]; then
    fail "NDK 目录存在但为空，请在 Android Studio SDK Manager → NDK (Side by side) 中安装。"
  else
    ok "NDK 版本：$NDK_VER → $NDK_PATH"
  fi
else
  fail "未找到 NDK（路径：$NDK_DIR），请在 Android Studio SDK Manager → NDK (Side by side) 中安装。"
fi

# ─── 6. Rust Android targets ──────────────────────────────────────────────────
echo -e "${CYAN}[6/8] Rust Android 编译目标${RESET}"
REQUIRED_TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "i686-linux-android"
  "x86_64-linux-android"
)

if ! command -v rustup &>/dev/null; then
  fail "未找到 rustup，请从 https://rustup.rs 安装"
else
  INSTALLED_TARGETS=$(rustup target list --installed 2>/dev/null)
  MISSING_TARGETS=()
  for t in "${REQUIRED_TARGETS[@]}"; do
    if echo "$INSTALLED_TARGETS" | grep -q "$t"; then
      ok "  $t"
    else
      MISSING_TARGETS+=("$t")
      fail "  $t（未安装）"
    fi
  done

  if [[ ${#MISSING_TARGETS[@]} -gt 0 ]]; then
    echo ""
    warn "请运行以下命令安装缺失的编译目标："
    for t in "${MISSING_TARGETS[@]}"; do
      echo "    rustup target add $t"
    done
  fi
fi

# ─── 7. pnpm ──────────────────────────────────────────────────────────────────
echo -e "${CYAN}[7/8] pnpm${RESET}"
if command -v pnpm &>/dev/null; then
  ok "pnpm $(pnpm --version) 已安装"
else
  fail "未找到 pnpm，请安装：npm install -g pnpm"
fi

# ─── 8. keystore.properties ───────────────────────────────────────────────────
echo -e "${CYAN}[8/8] keystore.properties${RESET}"
KEYSTORE_PROPS="$(dirname "$0")/backend/src-tauri/gen/android/keystore.properties"
if [[ -f "$KEYSTORE_PROPS" ]]; then
  ok "keystore.properties 已找到：$KEYSTORE_PROPS"
else
  fail "keystore.properties 未找到：$KEYSTORE_PROPS"
  warn "请创建该文件，内容如下："
  echo "    storeFile=C:/path/to/release.keystore"
  echo "    storePassword=your_store_password"
  echo "    keyAlias=your_key_alias"
  echo "    keyPassword=your_key_password"
  warn "生成 keystore："
  echo "    keytool -genkeypair -v -keystore release.keystore -alias my-key -keyalg RSA -keysize 2048 -validity 10000"
fi


# ─── Result ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
if [[ "$FAILED" -ne 0 ]]; then
  echo -e "${RED}  环境检查未通过，请修复以上问题后重试。${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  exit 1
fi
echo -e "${GREEN}  所有检查通过！${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

# ─── Export common env vars ───────────────────────────────────────────────────
export ANDROID_HOME
export ANDROID_NDK_HOME
export PATH="${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/tools:${PATH}"

# Windows 下 NDK 的编译器路径 — 优先使用 NDK bundled clang
if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
  NDK_TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/windows-x86_64/bin"
  if [[ -d "$NDK_TOOLCHAIN" ]]; then
    export CC="${NDK_TOOLCHAIN}/clang.exe"
    export CXX="${NDK_TOOLCHAIN}/clang++.exe"
    echo -e "${YELLOW}  使用 NDK clang：${NDK_TOOLCHAIN}${RESET}"
  else
    warn "NDK toolchain 目录未找到：$NDK_TOOLCHAIN"
    warn "将使用系统默认编译器"
  fi
fi

# ─── Limit parallelism to avoid OOM ──────────────────────────────────────────
export CARGO_BUILD_JOBS=1
export GRADLE_OPTS="-Dorg.gradle.workers.max=1"
echo -e "${YELLOW}  CARGO_BUILD_JOBS=1, Gradle workers=1（避免内存溢出）${RESET}"
echo ""

# ─── Run ──────────────────────────────────────────────────────────────────────
echo -e "${CYAN}执行：pnpm tauri android ${COMMAND}${RESET}"
echo ""
exec pnpm tauri android "$COMMAND"
