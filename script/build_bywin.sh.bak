#!/usr/bin/env bash
# test_env_android_bywin.sh — Windows (Git Bash / MSYS2) Android dev/build helper for Tauri 2
# 用法：
#   ./test_env_android_bywin.sh dev     # 启动 Android 开发模式
#   ./test_env_android_bywin.sh build   # 构建 Android APK/AAB

set -euo pipefail

COMMAND="${1:-}"
AUTO_YES=0
if [[ "${2:-}" == "-y" || "${2:-}" == "--yes" ]]; then
  AUTO_YES=1
fi

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*"; FAILED=1; }

# ─── Confirm & helpers ────────────────────────────────────────────────────────
confirm_install() {
  local desc="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    echo -e "${YELLOW}  自动确认：${desc}${RESET}"
    return 0
  fi
  echo -e "${YELLOW}  ? ${desc} 是否自动安装？[Y/n]${RESET}"
  read -r answer
  case "$answer" in
    n|N|no|No|NO) return 1 ;;
    *) return 0 ;;
  esac
}

refresh_path() {
  # 从 Windows 用户环境变量重新读取 PATH，使新安装的工具在当前 shell 可用
  local win_path
  win_path="$(powershell -Command "[Environment]::GetEnvironmentVariable('PATH','User')" 2>/dev/null | tr -d '\r')"
  if [[ -n "$win_path" ]]; then
    local unix_path
    unix_path="$(cygpath -u "$win_path" 2>/dev/null || echo "$win_path")"
    export PATH="${PATH}:${unix_path}"
  fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────
if [[ "$COMMAND" != "dev" && "$COMMAND" != "build" ]]; then
  echo -e "${CYAN}用法：${RESET} $0 <dev|build> [-y]"
  echo ""
  echo "  dev    启动 Tauri Android 开发模式（热重载）"
  echo "  build  构建 Android APK/AAB 发布包"
  echo "  -y     自动确认所有安装提示（静默模式）"
  exit 1
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  Android 环境检查（Windows Git Bash）    ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

FAILED=0

# ─── 1. C/C++ Build Tools ────────────────────────────────────────────────────
echo -e "${CYAN}[1/8] C/C++ 编译工具${RESET}"
# 检查策略：
#   1. 直接可用的 MSVC (cl.exe) 或 GNU (gcc/g++)
#   2. Rust GNU 工具链自带的 gcc（位于 rustup toolchain 深层目录，不在 PATH 中）
#   3. 通过 rustc 编译测试验证工具链可用性
FOUND_CC=0

if command -v cl.exe &>/dev/null; then
  ok "MSVC cl.exe 已找到：$(which cl.exe)"
  FOUND_CC=1
elif command -v gcc &>/dev/null && gcc --version &>/dev/null; then
  GCC_INFO=$(gcc --version 2>&1 | head -1)
  ok "GNU gcc 已找到：$(which gcc) — $GCC_INFO"
  if command -v g++ &>/dev/null && g++ --version &>/dev/null; then
    ok "GNU g++ 已找到：$(which g++) — $(g++ --version 2>&1 | head -1)"
  else
    warn "gcc 已找到但 g++ 未找到，部分 C++ 依赖可能编译失败"
  fi
  FOUND_CC=1
elif command -v cc &>/dev/null && cc --version &>/dev/null; then
  ok "C 编译器已找到：$(which cc) — $(cc --version 2>&1 | head -1)"
  FOUND_CC=1
fi

# 即使 gcc 不在 PATH 中，Rust GNU 工具链也自带了 gcc（x86_64-w64-mingw32-gcc）
# Rust 的 cc crate 会自动找到它，所以只需验证 rustc 能正常编译即可
if [[ "$FOUND_CC" -eq 0 ]]; then
  if command -v rustc &>/dev/null; then
    RUSTC_INFO=$(rustc --version --verbose 2>&1 | head -2 | tr '\n' ' ')
    ok "Rust 编译器已找到：$RUSTC_INFO"
    # 验证 Rust 能否正常编译链接（间接验证 gcc 可用）
    TEST_SRC=$(mktemp /tmp/test_rust_XXXXXX.rs)
    TEST_BIN=$(mktemp /tmp/test_rust_XXXXXX.exe)
    echo 'fn main() {}' > "$TEST_SRC"
    if rustc "$TEST_SRC" -o "$TEST_BIN" 2>/dev/null; then
      ok "Rust GNU 工具链编译链接正常（gcc 由 Rust 自带，无需手动安装）"
      FOUND_CC=1
      rm -f "$TEST_SRC" "$TEST_BIN"
    else
      fail "Rust 编译链接失败，GNU 工具链可能不完整"
      rm -f "$TEST_SRC" "$TEST_BIN"
    fi
  else
    fail "未找到 C/C++ 编译器，也未找到 Rust 编译器。"
  fi
fi

if [[ "$FOUND_CC" -eq 0 ]]; then
  # 尝试自动安装
  if command -v pacman &>/dev/null; then
    if confirm_install "通过 pacman 安装 mingw-w64-x86_64-gcc"; then
      pacman -S --noconfirm mingw-w64-x86_64-gcc && {
        ok "mingw-w64-x86_64-gcc 安装成功"
        FOUND_CC=1
      } || warn "pacman 安装失败"
    fi
  fi

  if [[ "$FOUND_CC" -eq 0 ]] && command -v rustup &>/dev/null; then
    if confirm_install "通过 rustup 安装 stable-x86_64-pc-windows-gnu 工具链"; then
      rustup toolchain install stable-x86_64-pc-windows-gnu && {
        ok "Rust GNU 工具链安装成功"
        # 重新验证编译
        TEST_SRC=$(mktemp /tmp/test_rust_XXXXXX.rs)
        TEST_BIN=$(mktemp /tmp/test_rust_XXXXXX.exe)
        echo 'fn main() {}' > "$TEST_SRC"
        if rustc "$TEST_SRC" -o "$TEST_BIN" 2>/dev/null; then
          ok "Rust GNU 工具链编译链接验证通过"
          FOUND_CC=1
        else
          warn "Rust GNU 工具链安装后编译链接仍失败"
        fi
        rm -f "$TEST_SRC" "$TEST_BIN"
      } || warn "rustup 工具链安装失败"
    fi
  fi
fi

if [[ "$FOUND_CC" -eq 0 ]]; then
  fail "未找到 C/C++ 编译器，且自动安装失败或被跳过。"
  fail "请手动安装以下任一工具链："
  fail "  • MSVC: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
  fail "    安装时勾选「使用 C++ 的桌面开发」工作负载"
  fail "  • GNU: https://www.mingw-w64.org/ 或通过 MSYS2 安装"
  fail "    pacman -S mingw-w64-x86_64-gcc"
  fail "  • Rust + GNU: https://rustup.rs 安装时选择 x86_64-pc-windows-gnu"
fi

# ── 检查 GNU 汇编器 as.exe（dlltool 依赖） ──
# Rust GNU 工具链的 dlltool 需要 as.exe（GNU 汇编器）来创建导入库，
# 但 Rust 自带的 self-contained 目录不包含 as.exe，导致编译时 CreateProcess 失败。
MSYS2_MINGW_BIN="/c/msys64/mingw64/bin"
FOUND_AS=0
if command -v as &>/dev/null; then
  FOUND_AS=1
  ok "GNU 汇编器 as 已在 PATH 中"
elif [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
  export PATH="${MSYS2_MINGW_BIN}:${PATH}"
  FOUND_AS=1
  ok "GNU 汇编器 as 已找到：${MSYS2_MINGW_BIN}/as.exe（已添加到 PATH）"
fi

if [[ "$FOUND_AS" -eq 0 ]]; then
  warn "未找到 GNU 汇编器 as.exe，Rust dlltool 将无法创建导入库（编译会报 CreateProcess 错误）"
  if [[ -d "/c/msys64" ]]; then
    # MSYS2 已安装但缺少 binutils 包
    if confirm_install "通过 MSYS2 pacman 安装 mingw-w64-x86_64-binutils"; then
      /c/msys64/usr/bin/bash.exe -lc "pacman -S --noconfirm --needed mingw-w64-x86_64-binutils" 2>&1
      if [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
        export PATH="${MSYS2_MINGW_BIN}:${PATH}"
        FOUND_AS=1
        ok "mingw-w64-x86_64-binutils 安装成功，as.exe 已添加到 PATH"
      else
        warn "pacman 安装完成但未找到 as.exe，可能需要更新 MSYS2："
        warn "  /c/msys64/usr/bin/bash.exe -lc 'pacman -Syu --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-binutils'"
      fi
    fi
  else
    # MSYS2 未安装，需要先安装
    if confirm_install "通过 winget 安装 MSYS2，然后安装 mingw-w64-x86_64-binutils"; then
      winget install MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements 2>&1
      if [[ -d "/c/msys64" ]]; then
        # 初始化 MSYS2 并安装 binutils
        /c/msys64/usr/bin/bash.exe -lc "pacman-key --init && pacman-key --populate msys2 && pacman -Sy --noconfirm archlinux-msys2-keyring && pacman -Su --noconfirm && pacman -S --noconfirm --needed mingw-w64-x86_64-binutils" 2>&1
        if [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
          export PATH="${MSYS2_MINGW_BIN}:${PATH}"
          FOUND_AS=1
          ok "MSYS2 + binutils 安装成功，as.exe 已添加到 PATH"
        else
          warn "MSYS2 已安装但 binutils 安装可能不完整，请手动执行："
          warn "  /c/msys64/usr/bin/bash.exe -lc 'pacman -S --noconfirm mingw-w64-x86_64-binutils'"
        fi
      else
        warn "winget 安装 MSYS2 后未在 C:\\msys64 找到安装目录"
      fi
    fi
  fi

  if [[ "$FOUND_AS" -eq 0 ]]; then
    fail "缺少 GNU 汇编器 as.exe，Android 交叉编译将失败。"
    fail "请安装 MSYS2（https://www.msys2.org/）并运行："
    fail "  pacman -S mingw-w64-x86_64-binutils"
    fail "然后将 C:\\msys64\\mingw64\\bin 添加到 PATH"
  fi
fi

# ─── 2. Java (JDK 17+) ────────────────────────────────────────────────────────
echo -e "${CYAN}[2/8] Java JDK（17+）${RESET}"
if command -v java &>/dev/null; then
  JAVA_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
  if [[ "$JAVA_VER" -ge 17 ]]; then
    ok "Java $JAVA_VER 已安装：$(which java)"
  else
    fail "检测到 Java $JAVA_VER，但需要 JDK 17+。"
    if confirm_install "通过 winget 安装 Eclipse Adoptium Temurin JDK 17"; then
      winget install EclipseAdoptium.Temurin.17.JDK --accept-package-agreements --accept-source-agreements && {
        refresh_path
        # 验证安装
        if command -v java &>/dev/null; then
          JAVA_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
          ok "Java $JAVA_VER 安装成功：$(which java)"
        else
          warn "JDK 已安装但当前 shell 未生效，请重新运行此脚本"
        fi
      } || warn "winget 安装 JDK 失败"
    else
      fail "请从 https://adoptium.net/ 下载 JDK 17+，或通过 winget 安装：winget install EclipseAdoptium.Temurin.17.JDK"
    fi
  fi
else
  fail "未找到 Java"
  if confirm_install "通过 winget 安装 Eclipse Adoptium Temurin JDK 17"; then
    winget install EclipseAdoptium.Temurin.17.JDK --accept-package-agreements --accept-source-agreements && {
      refresh_path
      if command -v java &>/dev/null; then
        JAVA_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
        ok "Java $JAVA_VER 安装成功：$(which java)"
      else
        warn "JDK 已安装但当前 shell 未生效，请重新运行此脚本"
      fi
    } || warn "winget 安装 JDK 失败"
  else
    fail "请从 https://adoptium.net/ 下载 JDK 17+"
    fail "或运行：winget install EclipseAdoptium.Temurin.17.JDK"
  fi
fi

# ─── 3. ANDROID_HOME ──────────────────────────────────────────────────────────
echo -e "${CYAN}[3/8] ANDROID_HOME${RESET}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

# 清理值中可能存在的引号（setx 命令可能将引号写入环境变量值）
ANDROID_HOME="${ANDROID_HOME#\"}"
ANDROID_HOME="${ANDROID_HOME%\"}"

# 将 Windows 格式路径转换为 Unix 格式（Git Bash 环境）
if [[ -n "$ANDROID_HOME" ]]; then
  # 检测是否为 Windows 格式路径（包含反斜杠或 X:\ 格式）
  if [[ "$ANDROID_HOME" == *'\\'* ]] || [[ "$ANDROID_HOME" =~ ^[A-Za-z]: ]]; then
    AH_UNIX="$(cygpath -u "$ANDROID_HOME" 2>/dev/null || echo "")"
    if [[ -n "$AH_UNIX" ]]; then
      ANDROID_HOME="$AH_UNIX"
    fi
  fi
fi

if [[ -n "$ANDROID_HOME" && -d "$ANDROID_HOME" ]]; then
  ok "ANDROID_HOME=$ANDROID_HOME"
else
  # 如果仍未找到，尝试已知的 SDK 安装路径
  CANDIDATE_PATHS=(
    "C:/DevDisk/DevTools/AndroidSDK"
    "$LOCALAPPDATA/Android/Sdk"
    "$HOME/AppData/Local/Android/Sdk"
  )

  FOUND_SDK=0
  for CANDIDATE in "${CANDIDATE_PATHS[@]}"; do
    if [[ -d "$CANDIDATE" ]]; then
      export ANDROID_HOME="$CANDIDATE"
      warn "ANDROID_HOME 未设置，使用检测到的路径：$ANDROID_HOME"
      warn "建议运行 ./script/install_android_sdk_bywin.sh 设置环境变量"
      FOUND_SDK=1
      break
    fi
  done

  if [[ "$FOUND_SDK" -eq 0 ]]; then
    fail "ANDROID_HOME 未设置且未检测到 Android SDK 安装路径。"
    if confirm_install "运行 ./script/install_android_sdk_bywin.sh 安装 SDK"; then
      SCRIPT_DIR_TMP="$(cd "$(dirname "$0")" && pwd)"
      bash "${SCRIPT_DIR_TMP}/install_android_sdk_bywin.sh" -y && {
        # 安装脚本可能设置了 ANDROID_HOME，重新检测候选路径
        for CANDIDATE in "${CANDIDATE_PATHS[@]}"; do
          if [[ -d "$CANDIDATE" ]]; then
            export ANDROID_HOME="$CANDIDATE"
            FOUND_SDK=1
            break
          fi
        done
        # 也检查环境变量
        if [[ "$FOUND_SDK" -eq 0 && -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME:-}" ]]; then
          FOUND_SDK=1
        fi
        if [[ "$FOUND_SDK" -eq 1 ]]; then
          ok "Android SDK 安装成功，ANDROID_HOME=$ANDROID_HOME"
        else
          warn "SDK 安装脚本已运行，但未检测到 SDK 路径，请重新运行此脚本"
        fi
      } || warn "install_android_sdk_bywin.sh 执行失败"
    else
      fail "请运行 ./script/install_android_sdk_bywin.sh 安装 SDK，或手动设置 ANDROID_HOME 环境变量。"
    fi
  fi
fi

# ─── 4. Android SDK Tools ─────────────────────────────────────────────────────
echo -e "${CYAN}[4/8] Android SDK 工具（adb、sdkmanager）${RESET}"
# Windows 下可执行文件带 .exe 后缀
if [[ -f "${ANDROID_HOME}/platform-tools/adb.exe" ]]; then
  ok "adb 已找到：${ANDROID_HOME}/platform-tools/adb.exe"
else
  fail "未找到 adb.exe（路径：${ANDROID_HOME}/platform-tools/adb.exe）"
  SDKMANAGER="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager.bat"
  if [[ -f "$SDKMANAGER" ]]; then
    if confirm_install "通过 sdkmanager 安装 platform-tools"; then
      export MSYS_NO_PATHCONV=1
      SDKMANAGER_WIN="$(cygpath -w "$SDKMANAGER" 2>/dev/null || echo "$SDKMANAGER")"
      SDK_ROOT_WIN="$(cygpath -w "$ANDROID_HOME" 2>/dev/null || echo "$ANDROID_HOME")"
      yes | cmd.exe /c "$SDKMANAGER_WIN" --sdk_root="$SDK_ROOT_WIN" "platform-tools" && {
        ok "platform-tools 安装成功"
      } || warn "sdkmanager 安装 platform-tools 失败"
      unset MSYS_NO_PATHCONV
    fi
  else
    warn "sdkmanager 未找到，无法自动安装 platform-tools"
    warn "请在 Android Studio SDK Manager 中安装 platform-tools"
  fi
fi

SDKMANAGER="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager.bat"
if [[ -f "$SDKMANAGER" ]]; then
  ok "sdkmanager 已找到：${SDKMANAGER}"
else
  warn "sdkmanager 未找到：${SDKMANAGER}"
  # 检查是否有其他版本的 cmdline-tools
  ALT_SDKMANAGER=""
  if [[ -d "${ANDROID_HOME}/cmdline-tools" ]]; then
    for dir in "${ANDROID_HOME}/cmdline-tools"/*/bin; do
      if [[ -f "${dir}/sdkmanager.bat" ]]; then
        ALT_SDKMANAGER="${dir}/sdkmanager.bat"
        break
      fi
    done
  fi

  if [[ -n "$ALT_SDKMANAGER" ]]; then
    if confirm_install "通过 sdkmanager 安装 cmdline-tools;latest"; then
      export MSYS_NO_PATHCONV=1
      ALT_SDKMANAGER_WIN="$(cygpath -w "$ALT_SDKMANAGER" 2>/dev/null || echo "$ALT_SDKMANAGER")"
      SDK_ROOT_WIN="$(cygpath -w "$ANDROID_HOME" 2>/dev/null || echo "$ANDROID_HOME")"
      yes | cmd.exe /c "$ALT_SDKMANAGER_WIN" --sdk_root="$SDK_ROOT_WIN" "cmdline-tools;latest" && {
        ok "cmdline-tools;latest 安装成功"
        SDKMANAGER="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager.bat"
      } || warn "sdkmanager 安装 cmdline-tools;latest 失败"
      unset MSYS_NO_PATHCONV
    fi
  else
    warn "无可用 sdkmanager，无法自动安装 cmdline-tools"
    warn "请在 Android Studio SDK Manager > SDK Tools > Android SDK Command-line Tools 中安装"
    warn "或运行：./script/install_android_sdk_bywin.sh"
  fi
fi

# ─── 5. NDK ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}[5/8] Android NDK${RESET}"
# NDK 可能安装在两种目录结构中：
#   1. ndk/<version>/ — 新版 NDK（推荐，通过 sdkmanager 安装 ndk;27.x.x）
#   2. ndk-bundle/     — 旧版 NDK（已废弃，通过 ndk-bundle 包安装）
NDK_DIR="${ANDROID_HOME}/ndk"
NDK_BUNDLE_DIR="${ANDROID_HOME}/ndk-bundle"
NDK_PATH=""
NDK_VER=""

if [[ -d "$NDK_DIR" ]]; then
  NDK_VER=$(ls "$NDK_DIR" | sort -V | tail -1)
  if [[ -n "$NDK_VER" ]]; then
    NDK_PATH="${NDK_DIR}/${NDK_VER}"
  fi
fi

# 如果 ndk/ 目录不存在或为空，尝试 ndk-bundle/
if [[ -z "$NDK_PATH" && -d "$NDK_BUNDLE_DIR" ]]; then
  # 从 source.properties 读取版本号
  if [[ -f "${NDK_BUNDLE_DIR}/source.properties" ]]; then
    NDK_VER=$(grep 'Pkg.Revision' "${NDK_BUNDLE_DIR}/source.properties" 2>/dev/null | awk '{print $NF}' || echo "unknown")
  else
    NDK_VER="ndk-bundle"
  fi
  NDK_PATH="$NDK_BUNDLE_DIR"
  warn "检测到旧版 ndk-bundle（版本 $NDK_VER），建议安装新版 NDK："
  warn "  sdkmanager --install 'ndk;27.0.12077973'"
fi

if [[ -n "$NDK_PATH" ]]; then
  export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$NDK_PATH}"
  ok "NDK 版本：$NDK_VER → $NDK_PATH"
else
  fail "未找到 NDK（路径：$NDK_DIR 和 $NDK_BUNDLE_DIR 均不存在）"
  SDKMANAGER="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager.bat"
  if [[ -f "$SDKMANAGER" ]]; then
    if confirm_install "通过 sdkmanager 安装 NDK 27.0.12077973"; then
      export MSYS_NO_PATHCONV=1
      SDKMANAGER_WIN="$(cygpath -w "$SDKMANAGER" 2>/dev/null || echo "$SDKMANAGER")"
      SDK_ROOT_WIN="$(cygpath -w "$ANDROID_HOME" 2>/dev/null || echo "$ANDROID_HOME")"
      yes | cmd.exe /c "$SDKMANAGER_WIN" --sdk_root="$SDK_ROOT_WIN" "ndk;27.0.12077973" && {
        ok "NDK 安装成功"
        # 重新检测 NDK
        if [[ -d "$NDK_DIR" ]]; then
          NDK_VER=$(ls "$NDK_DIR" | sort -V | tail -1)
          if [[ -n "$NDK_VER" ]]; then
            NDK_PATH="${NDK_DIR}/${NDK_VER}"
            export ANDROID_NDK_HOME="$NDK_PATH"
            ok "NDK 版本：$NDK_VER → $NDK_PATH"
          fi
        fi
      } || warn "sdkmanager 安装 NDK 失败"
      unset MSYS_NO_PATHCONV
    fi
  else
    fail "sdkmanager 未找到，无法自动安装 NDK"
    fail "请运行 ./script/install_android_sdk_bywin.sh"
    fail "或在 Android Studio SDK Manager → NDK (Side by side) 中安装。"
  fi
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
    if confirm_install "安装缺失的 Rust Android 编译目标（${#MISSING_TARGETS[@]} 个）"; then
      for t in "${MISSING_TARGETS[@]}"; do
        echo -e "${CYAN}  rustup target add $t${RESET}"
        rustup target add "$t" && ok "  $t 安装成功" || warn "  $t 安装失败，请手动运行：rustup target add $t"
      done
    else
      warn "请手动运行以下命令安装缺失的编译目标："
      for t in "${MISSING_TARGETS[@]}"; do
        echo "    rustup target add $t"
      done
    fi
  fi
fi

# ─── 7. pnpm ──────────────────────────────────────────────────────────────────
echo -e "${CYAN}[7/8] pnpm${RESET}"
if command -v pnpm &>/dev/null; then
  ok "pnpm $(pnpm --version) 已安装"
else
  fail "未找到 pnpm"
  if confirm_install "通过 npm 全局安装 pnpm"; then
    npm install -g pnpm && {
      ok "pnpm $(pnpm --version) 安装成功"
    } || warn "npm install -g pnpm 失败"
  else
    fail "请手动安装：npm install -g pnpm"
  fi
fi

# ─── 8. keystore.properties ───────────────────────────────────────────────────
echo -e "${CYAN}[8/8] keystore.properties${RESET}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYSTORE_PROPS="${SCRIPT_DIR}/../backend/src-tauri/gen/android/keystore.properties"
if [[ -f "$KEYSTORE_PROPS" ]]; then
  ok "keystore.properties 已找到：$KEYSTORE_PROPS"
else
  fail "keystore.properties 未找到：$KEYSTORE_PROPS"
  if confirm_install "创建默认 keystore.properties 文件"; then
    # 确保目录存在
    mkdir -p "$(dirname "$KEYSTORE_PROPS")" 2>/dev/null || true
    cat > "$KEYSTORE_PROPS" <<'KEYSTORE_EOF'
keyAlias=tauri2demo_key
password=abc009988
storeFile="C:\\SyncData\\release.keystore"
KEYSTORE_EOF
    ok "keystore.properties 已创建：$KEYSTORE_PROPS"
  else
    warn "请手动创建该文件，内容如下："
    echo "    storeFile=C:/path/to/release.keystore"
    echo "    storePassword=your_store_password"
    echo "    keyAlias=your_key_alias"
    echo "    keyPassword=your_key_password"
    warn "生成 keystore："
    echo "    keytool -genkeypair -v -keystore release.keystore -alias tauri2demo-key -keyalg RSA -keysize 2048 -validity 10000"
  fi
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

# ─── Build Preparation ────────────────────────────────────────────────────────
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  构建准备                                  ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEN_ANDROID_DIR="${PROJECT_ROOT}/backend/src-tauri/gen/android"

# ─── Prep 1: pnpm install ────────────────────────────────────────────────────
echo -e "${CYAN}[准备 1/4] npm 依赖${RESET}"
if [[ -d "${PROJECT_ROOT}/node_modules" ]]; then
  ok "node_modules 已存在"
else
  warn "node_modules 不存在，正在运行 pnpm install ..."
  (cd "$PROJECT_ROOT" && pnpm install)
  ok "pnpm install 完成"
fi

# ─── Prep 2: Tauri Android init ──────────────────────────────────────────────
echo -e "${CYAN}[准备 2/4] Tauri Android 项目${RESET}"
ANDROID_INIT_NEEDED=0

# 检查 gen/android 关键文件是否存在
if [[ ! -f "${GEN_ANDROID_DIR}/settings.gradle.kts" ]]; then
  warn "settings.gradle.kts 缺失"
  ANDROID_INIT_NEEDED=1
fi
if [[ ! -f "${GEN_ANDROID_DIR}/gradlew" ]]; then
  warn "gradlew 缺失"
  ANDROID_INIT_NEEDED=1
fi
if [[ ! -d "${GEN_ANDROID_DIR}/app/src/main/java" ]]; then
  warn "app/src/main/java/ 缺失"
  ANDROID_INIT_NEEDED=1
fi

if [[ "$ANDROID_INIT_NEEDED" -eq 1 ]]; then
  # tauri android init 要求 gen/android 不存在或为空目录，否则会报错
  # 因此需要先备份 keystore.properties，删除不完整的 gen/android，再重新 init
  KEYSTORE_PROPS="${GEN_ANDROID_DIR}/keystore.properties"
  KEYSTORE_BACKUP=""
  if [[ -f "$KEYSTORE_PROPS" ]]; then
    KEYSTORE_BACKUP="$(mktemp /tmp/keystore_properties_XXXXXX)"
    cp "$KEYSTORE_PROPS" "$KEYSTORE_BACKUP"
    warn "已备份 keystore.properties"
  fi

  warn "正在删除不完整的 gen/android 目录 ..."
  rm -rf "${GEN_ANDROID_DIR}"

  warn "正在运行 pnpm tauri android init ..."
  (cd "$PROJECT_ROOT" && pnpm tauri android init)

  # 恢复 keystore.properties（init 会生成默认的，需要用我们的覆盖）
  if [[ -n "$KEYSTORE_BACKUP" && -f "$KEYSTORE_BACKUP" ]]; then
    cp "$KEYSTORE_BACKUP" "${GEN_ANDROID_DIR}/keystore.properties"
    rm -f "$KEYSTORE_BACKUP"
    ok "keystore.properties 已恢复"
  else
    # 没有备份（原来就不存在），写入默认配置
    if [[ ! -f "${GEN_ANDROID_DIR}/keystore.properties" ]]; then
      warn "正在写入 keystore.properties ..."
      cat > "${GEN_ANDROID_DIR}/keystore.properties" <<'KEYSTORE_EOF'
keyAlias=tauri2demo_key
password=abc009988
storeFile="C:\\SyncData\\release.keystore"
KEYSTORE_EOF
      ok "keystore.properties 已写入"
    fi
  fi

  # 替换 Android 签名和权限文件（init 生成的默认文件不含签名配置和录音权限）
  GEN_ANDROID_APP="${GEN_ANDROID_DIR}/app"
  echo -e "${CYAN}  替换 Android 签名和权限文件${RESET}"
  if [[ -f "${SCRIPT_DIR}/android-permission-sign/build.gradle.kts" ]]; then
    cp "${SCRIPT_DIR}/android-permission-sign/build.gradle.kts" "${GEN_ANDROID_APP}/build.gradle.kts"
    ok "build.gradle.kts 已替换"
  else
    warn "android-permission-sign/build.gradle.kts 不存在，跳过替换"
  fi
  if [[ -f "${SCRIPT_DIR}/android-permission-sign/AndroidManifest.xml" ]]; then
    cp "${SCRIPT_DIR}/android-permission-sign/AndroidManifest.xml" "${GEN_ANDROID_APP}/src/main/AndroidManifest.xml"
    ok "AndroidManifest.xml 已替换"
  else
    warn "android-permission-sign/AndroidManifest.xml 不存在，跳过替换"
  fi

  ok "pnpm tauri android init 完成"
else
  ok "gen/android 项目完整"
fi

# ─── Prep 3: Frontend build ──────────────────────────────────────────────────
echo -e "${CYAN}[准备 3/4] 前端构建${RESET}"
if [[ -d "${PROJECT_ROOT}/frontend/dist" ]]; then
  ok "frontend/dist 已存在"
else
  warn "frontend/dist 不存在，正在运行前端构建 ..."
  (cd "$PROJECT_ROOT" && pnpm build)
  ok "前端构建完成"
fi

# ─── Prep 4: Keystore file ───────────────────────────────────────────────────
echo -e "${CYAN}[准备 4/4] Keystore 签名文件${RESET}"
KEYSTORE_PROPS="${GEN_ANDROID_DIR}/keystore.properties"
if [[ -f "$KEYSTORE_PROPS" ]]; then
  # 读取 storeFile 路径（去除引号）
  STORE_FILE_RAW=$(grep '^storeFile=' "$KEYSTORE_PROPS" | sed 's/^storeFile=//' | tr -d '"' | tr -d "'")
  # 将 Windows 路径转换为 Unix 路径
  STORE_FILE_UNIX=""
  if [[ -n "$STORE_FILE_RAW" ]]; then
    STORE_FILE_UNIX="$(cygpath -u "$STORE_FILE_RAW" 2>/dev/null || echo "$STORE_FILE_RAW")"
  fi

  if [[ -n "$STORE_FILE_UNIX" && -f "$STORE_FILE_UNIX" ]]; then
    ok "Keystore 文件已存在：$STORE_FILE_RAW"
  else
    warn "Keystore 文件不存在：$STORE_FILE_RAW"
    warn "正在自动生成 keystore ..."

    # 读取 keyAlias 和 password
    KEY_ALIAS=$(grep '^keyAlias=' "$KEYSTORE_PROPS" | sed 's/^keyAlias=//' | tr -d '"' | tr -d "'")
    KEY_PASSWORD=$(grep '^password=' "$KEYSTORE_PROPS" | sed 's/^password=//' | tr -d '"' | tr -d "'")

    # 确保 keystore 所在目录存在
    STORE_DIR="$(dirname "$STORE_FILE_UNIX")"
    mkdir -p "$STORE_DIR" 2>/dev/null || true

    # 使用 keytool 生成 keystore
    if command -v keytool &>/dev/null; then
      keytool -genkeypair -v \
        -keystore "$STORE_FILE_UNIX" \
        -alias "${KEY_ALIAS:-tauri2demo_key}" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass "${KEY_PASSWORD:-changeit}" \
        -keypass "${KEY_PASSWORD:-changeit}" \
        -dname "CN=Tauri2Demo, OU=Dev, O=Dev, L=Unknown, ST=Unknown, C=CN"
      ok "Keystore 已生成：$STORE_FILE_RAW"
    else
      fail "keytool 未找到，无法自动生成 keystore"
      fail "请手动运行："
      fail "  keytool -genkeypair -v -keystore \"$STORE_FILE_RAW\" -alias ${KEY_ALIAS:-tauri2demo_key} -keyalg RSA -keysize 2048 -validity 10000"
    fi
  fi
else
  warn "keystore.properties 不存在，跳过 keystore 文件检查"
fi

echo ""
echo -e "${GREEN}  构建准备完成！${RESET}"
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

# Rust GNU 工具链的 dlltool — 交叉编译 Android 时 cc crate 需要调用 dlltool
# 该工具位于 rustlib/x86_64-pc-windows-gnu/bin/self-contained/ 下，默认不在 PATH 中
if command -v rustup &>/dev/null; then
  RUSTC_UNIX="$(cygpath -u "$(rustup which rustc)" 2>/dev/null)"
  if [[ -n "$RUSTC_UNIX" ]]; then
    RUST_SELF_CONTAINED="$(dirname "$(dirname "$RUSTC_UNIX")")/lib/rustlib/x86_64-pc-windows-gnu/bin/self-contained"
    if [[ -d "$RUST_SELF_CONTAINED" && -f "${RUST_SELF_CONTAINED}/dlltool.exe" ]]; then
      export PATH="${RUST_SELF_CONTAINED}:${PATH}"
      ok "Rust dlltool 已加入 PATH：${RUST_SELF_CONTAINED}"
    else
      warn "Rust GNU 工具链 self-contained 目录未找到：$RUST_SELF_CONTAINED"
      warn "交叉编译 Android 时可能因找不到 dlltool 而失败"
    fi
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
