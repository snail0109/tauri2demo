#!/usr/bin/env bash
# build_macos.sh — macOS 多平台 dev/build 助手（Tauri 2）
# 用法：
#   ./build_macos.sh dev              # 启动 Android 开发模式（默认）
#   ./build_macos.sh dev macos        # 启动桌面端开发模式
#   ./build_macos.sh build android    # 构建 Android APK/AAB
#   ./build_macos.sh build ios        # 构建 iOS IPA
#   ./build_macos.sh build macos      # 构建 macOS dmg
#   ./build_macos.sh check android    # 仅检查环境，不构建
#
# 环境安装请使用：
#   ./script/macos/install_base_tools_macos.sh --add-tools all -y
#   ./script/macos/install_c_compile_macos.sh -y
#   ./script/macos/install_android_sdk_macos.sh -y

set -euo pipefail

COMMAND="${1:-}"
PLATFORM="${2:-android}"   # dev / check 默认 android；build 须显式指定平台

source "$(dirname "$0")/_common.sh"

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${CYAN}用法：${RESET} $0 <dev|build|check> [android|ios|macos]"
  echo ""
  echo "  dev                启动 Android 开发模式（热重载，默认平台）"
  echo "  dev macos          启动桌面端开发模式（热重载）"
  echo "  build android      构建 Android APK/AAB 发布包"
  echo "  build ios          构建 iOS IPA 发布包"
  echo "  build macos        构建 macOS dmg 发布包"
  echo "  check android      仅检查环境，不构建"
  echo ""
  echo "  环境安装脚本："
  echo "    ./script/macos/install_base_tools_macos.sh --add-tools all -y"
  echo "    ./script/macos/install_c_compile_macos.sh -y"
  echo "    ./script/macos/install_android_sdk_macos.sh -y"
  exit 1
}

# ─── Argument validation ──────────────────────────────────────────────────────
if [[ "$COMMAND" != "dev" && "$COMMAND" != "build" && "$COMMAND" != "check" ]]; then
  usage
fi
if [[ "$COMMAND" != "dev" && "$PLATFORM" != "android" && "$PLATFORM" != "ios" && "$PLATFORM" != "macos" ]]; then
  echo -e "${RED}  ✗${RESET} $COMMAND 命令需指定平台：android | ios | macos"
  usage
fi
if [[ "$COMMAND" == "dev" && "$PLATFORM" != "android" && "$PLATFORM" != "macos" ]]; then
  echo -e "${RED}  ✗${RESET} dev 命令支持的平台：android（默认）| macos"
  usage
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  环境检查（目标平台：${PLATFORM}）         ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 公共：Xcode Command Line Tools ──────────────────────────────────────────
echo -e "${CYAN}[*] Xcode Command Line Tools${RESET}"
if xcode-select -p &>/dev/null && clang --version &>/dev/null; then
  ok "clang 已安装：$(clang --version 2>&1 | head -1)"
else
  fail "未安装 Xcode Command Line Tools"
  fail "请运行：./script/macos/install_c_compile_macos.sh -y"
fi

# ─── 公共：pnpm ───────────────────────────────────────────────────────────────
echo -e "${CYAN}[*] pnpm${RESET}"
if command -v pnpm &>/dev/null; then
  ok "pnpm $(pnpm --version) 已安装"
else
  fail "未找到 pnpm"
  fail "请运行：./script/macos/install_base_tools_macos.sh --add-tools pnpm -y"
fi

# ─── Android 专属检查 ─────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "android" ]]; then

  echo -e "${CYAN}[Android] Java JDK（17+）${RESET}"
  if ! check_java17; then
    fail "请运行：./script/macos/install_android_sdk_macos.sh -y"
  fi

  # ANDROID_HOME
  echo -e "${CYAN}[Android] ANDROID_HOME${RESET}"
  ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$ANDROID_HOME" && -d "$ANDROID_HOME" ]]; then
    ok "ANDROID_HOME=$ANDROID_HOME"
  else
    if [[ -d "$HOME/Library/Android/sdk" ]]; then
      export ANDROID_HOME="$HOME/Library/Android/sdk"
      warn "ANDROID_HOME 未设置，使用默认路径：$ANDROID_HOME"
      warn "建议运行 source ~/.zshrc 或手动设置环境变量"
    else
      fail "ANDROID_HOME 未设置且默认路径不存在"
      fail "请运行：./script/macos/install_android_sdk_macos.sh -y"
    fi
  fi

  # Android SDK Tools
  echo -e "${CYAN}[Android] SDK 工具（adb、sdkmanager）${RESET}"
  ADB="${ANDROID_HOME}/platform-tools/adb"
  SDKMANAGER="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
  if [[ -x "$ADB" ]]; then
    ok "adb 已找到：$ADB"
  else
    fail "未找到 adb（路径：$ADB）"
    fail "请运行：./script/macos/install_android_sdk_macos.sh -y"
  fi
  if [[ -x "${SDKMANAGER}" ]]; then
    ok "sdkmanager 已找到：${SDKMANAGER}"
  else
    warn "sdkmanager 未找到：${SDKMANAGER}"
    warn "请运行：./script/macos/install_android_sdk_macos.sh -y"
  fi

  # NDK
  echo -e "${CYAN}[Android] Android NDK${RESET}"
  NDK_DIR="${ANDROID_HOME}/ndk"
  if [[ -d "$NDK_DIR" ]]; then
    NDK_VER=$(ls "$NDK_DIR" | sort -V | tail -1)
    NDK_PATH="${NDK_DIR}/${NDK_VER}"
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$NDK_PATH}"
    if [[ -z "${NDK_VER}" ]]; then
      fail "NDK 目录存在但为空"
      fail "请运行：./script/macos/install_android_sdk_macos.sh -y"
    else
      ok "NDK 版本：$NDK_VER → $NDK_PATH"
    fi
  else
    fail "未找到 NDK（路径：$NDK_DIR）"
    fail "请运行：./script/macos/install_android_sdk_macos.sh -y"
  fi

  # Rust Android targets
  echo -e "${CYAN}[Android] Rust 编译目标${RESET}"
  if ! check_rust_targets "${ANDROID_RUST_TARGETS[@]}"; then
    echo ""
    warn "请运行安装脚本安装缺失的编译目标："
    echo "    ./script/macos/install_android_sdk_macos.sh -y"
  fi

  # keystore.properties（仅 build）
  if [[ "$COMMAND" == "build" ]]; then
    echo -e "${CYAN}[Android] keystore.properties${RESET}"
    KEYSTORE_PROPS="$(cd "$SCRIPT_DIR/../.." && pwd)/backend/src-tauri/gen/android/keystore.properties"
    if [[ -f "$KEYSTORE_PROPS" ]]; then
      ok "keystore.properties 已找到：$KEYSTORE_PROPS"
    else
      fail "keystore.properties 未找到：$KEYSTORE_PROPS"
      warn "请创建该文件，内容示例："
      echo "    storeFile=./config/release.keystore"
      echo "    password=your_password"
      echo "    keyAlias=your_key_alias"
      warn "生成 keystore："
      echo "    keytool -genkeypair -v -keystore release.keystore -alias my-key -keyalg RSA -keysize 2048 -validity 10000"
    fi
  fi

fi  # end android

# ─── iOS 专属检查 ──────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "ios" ]]; then

  echo -e "${CYAN}[iOS] Rust 编译目标${RESET}"
  if ! check_rust_targets "${IOS_RUST_TARGETS[@]}"; then
    echo ""
    warn "请运行以下命令安装缺失的编译目标："
    for t in "${MISSING_TARGETS[@]}"; do
      echo "    rustup target add $t"
    done
  fi

fi  # end ios

# ─── macOS 专属检查 ────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "macos" ]]; then

  echo -e "${CYAN}[macOS] Rust 编译目标${RESET}"
  if ! command -v rustup &>/dev/null; then
    fail "未找到 rustup"
    fail "请运行：./script/macos/install_base_tools_macos.sh --add-tools rust -y"
  else
    INSTALLED_TARGETS=$(rustup target list --installed 2>/dev/null)
    MISSING_TARGETS=()
    for t in "${MACOS_RUST_TARGETS[@]}"; do
      if echo "$INSTALLED_TARGETS" | grep -q "$t"; then
        ok "  $t"
      else
        MISSING_TARGETS+=("$t")
        warn "  ${t}（未安装，构建当前架构时不影响，通用包需安装）"
      fi
    done
    if [[ ${#MISSING_TARGETS[@]} -gt 0 ]]; then
      echo ""
      warn "如需构建通用包（universal），请安装缺失目标："
      for t in "${MISSING_TARGETS[@]}"; do
        echo "    rustup target add $t"
      done
    fi
  fi

fi  # end macos

# ─── 汇总结果 ─────────────────────────────────────────────────────────────────
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

# check 模式到此结束
if [[ "$COMMAND" == "check" ]]; then
  exit 0
fi

# ─── 构建准备（Android）──────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "android" ]]; then

  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  GEN_ANDROID_DIR="${PROJECT_ROOT}/backend/src-tauri/gen/android"

  echo ""
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  echo -e "${CYAN}  构建准备                                  ${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  echo ""

  # ─── Prep 1: pnpm install ──────────────────────────────────────────────────
  echo -e "${CYAN}[准备 1/3] npm 依赖${RESET}"
  if [[ -d "${PROJECT_ROOT}/node_modules" ]]; then
    ok "node_modules 已存在"
  else
    warn "node_modules 不存在，正在运行 pnpm install ..."
    (cd "$PROJECT_ROOT" && pnpm install)
    ok "pnpm install 完成"
  fi

  # ─── Prep 2: Tauri Android init ────────────────────────────────────────────
  echo -e "${CYAN}[准备 2/3] Tauri Android 项目${RESET}"
  ANDROID_INIT_NEEDED=0

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

    # 恢复 keystore.properties
    if [[ -n "$KEYSTORE_BACKUP" && -f "$KEYSTORE_BACKUP" ]]; then
      cp "$KEYSTORE_BACKUP" "${GEN_ANDROID_DIR}/keystore.properties"
      rm -f "$KEYSTORE_BACKUP"
      ok "keystore.properties 已恢复"
    fi

    # 替换签名和权限文件
    GEN_ANDROID_APP="${GEN_ANDROID_DIR}/app"
    echo -e "${CYAN}  替换 Android 签名和权限文件${RESET}"
    cp "${SCRIPT_DIR}/../android-permission-sign/build.gradle.kts" "${GEN_ANDROID_APP}/build.gradle.kts"
    ok "build.gradle.kts 已替换"
    cp "${SCRIPT_DIR}/../android-permission-sign/AndroidManifest.xml" "${GEN_ANDROID_APP}/src/main/AndroidManifest.xml"
    ok "AndroidManifest.xml 已替换"

    ok "pnpm tauri android init 完成"
  else
    ok "gen/android 项目完整"

    # 即使不需要 init，build 时也替换签名和权限文件
    if [[ "$COMMAND" == "build" ]]; then
      GEN_ANDROID_APP="${GEN_ANDROID_DIR}/app"
      echo -e "${CYAN}  替换 Android 签名和权限文件${RESET}"
      cp "${SCRIPT_DIR}/../android-permission-sign/build.gradle.kts" "${GEN_ANDROID_APP}/build.gradle.kts"
      ok "build.gradle.kts 已替换"
      cp "${SCRIPT_DIR}/../android-permission-sign/AndroidManifest.xml" "${GEN_ANDROID_APP}/src/main/AndroidManifest.xml"
      ok "AndroidManifest.xml 已替换"
    fi
  fi

  # ─── Prep 3: 前端构建 ──────────────────────────────────────────────────────
  echo -e "${CYAN}[准备 3/3] 前端构建${RESET}"
  if [[ -d "${PROJECT_ROOT}/frontend/dist" ]]; then
    ok "frontend/dist 已存在"
  else
    warn "frontend/dist 不存在，正在运行前端构建 ..."
    (cd "$PROJECT_ROOT" && pnpm build)
    ok "前端构建完成"
  fi

  echo ""
  echo -e "${GREEN}  构建准备完成！${RESET}"
  echo ""

fi  # end android prep

# ─── 执行 Tauri 命令 ──────────────────────────────────────────────────────────
case "${COMMAND}/${PLATFORM}" in
  dev/android)
    echo -e "${CYAN}执行：pnpm tauri android dev${RESET}"
    echo ""
    exec pnpm tauri android dev
    ;;
  dev/macos)
    echo -e "${CYAN}执行：pnpm tauri dev${RESET}"
    echo ""
    exec pnpm tauri dev
    ;;
  build/android)
    echo -e "${CYAN}执行：pnpm tauri android build${RESET}"
    echo ""
    exec pnpm tauri android build
    ;;
  build/ios)
    echo -e "${CYAN}执行：pnpm tauri ios build${RESET}"
    echo ""
    exec pnpm tauri ios build
    ;;
  build/macos)
    echo -e "${CYAN}执行：pnpm tauri build${RESET}"
    echo ""
    exec pnpm tauri build
    ;;
esac
