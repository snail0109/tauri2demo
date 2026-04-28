#!/usr/bin/env bash
# _common.sh — macOS 脚本共享辅助函数与状态变量
# 通过 source 引入：source "$(dirname "$0")/_common.sh"
#
# 提供：颜色、日志（ok/warn/fail）、横幅、确认交互、菜单选择、
#       Rust 编译目标检查、Java 版本检查、常用路径辅助。

# ─── Colors ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# ─── Global state ─────────────────────────────────────────────────────────────
FAILED=0
AUTO_YES=0
SELECTED_OPTION=0
MISSING_TARGETS=()

# ─── Logging ──────────────────────────────────────────────────────────────────
ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*"; FAILED=1; }

# ─── Banner ───────────────────────────────────────────────────────────────────
# 用法: banner "标题" [颜色] [宽度]
banner() {
  local title="$1"
  local color="${2:-${CYAN}}"
  local width="${3:-42}"
  local bar
  bar=$(printf '%*s' "$width" '' | tr ' ' '═')
  echo -e "${color}${bar}${RESET}"
  echo -e "${color}  ${title}${RESET}"
  echo -e "${color}${bar}${RESET}"
}

# ─── Confirmations ────────────────────────────────────────────────────────────
confirm_install() {
  local desc="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
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

# ─── Menu ─────────────────────────────────────────────────────────────────────
# 用法: select_menu_option "提示文字" "选项1" "选项2" ...
# 用户选择存入 $SELECTED_OPTION（0=退出）
select_menu_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local count=${#options[@]}

  echo -e "${CYAN}${prompt}${RESET}"
  local i=1
  for opt in "${options[@]}"; do
    echo -e "  ${CYAN}${i})${RESET} ${opt}"
    ((i++))
  done
  echo -e "  ${CYAN}0)${RESET} 退出（不操作）"
  echo ""
  echo -ne "${YELLOW}  请选择 [0-${count}]：${RESET}"
  read -r choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "$count" ]]; then
    SELECTED_OPTION="$choice"
  else
    SELECTED_OPTION=0
  fi
}

# ─── Cargo / Rust ─────────────────────────────────────────────────────────────
ensure_cargo_bin() {
  if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
}

# Rust 编译目标常量（各脚本按需引用）
ANDROID_RUST_TARGETS=(
  "aarch64-linux-android"
  "armv7-linux-androideabi"
  "i686-linux-android"
  "x86_64-linux-android"
)

IOS_RUST_TARGETS=(
  "aarch64-apple-ios"
  "x86_64-apple-ios"
  "aarch64-apple-ios-sim"
)

MACOS_RUST_TARGETS=(
  "aarch64-apple-darwin"
  "x86_64-apple-darwin"
)

# 检查 Rust 编译目标，缺失的存入 $MISSING_TARGETS，返回值 0=全部已安装
# 用法: check_rust_targets "${ANDROID_RUST_TARGETS[@]}"
check_rust_targets() {
  local required=("$@")
  MISSING_TARGETS=()
  if ! command -v rustup &>/dev/null; then
    ensure_cargo_bin
    if ! command -v rustup &>/dev/null; then
      fail "未找到 rustup"
      MISSING_TARGETS=("${required[@]}")
      return 1
    fi
  fi
  local installed
  installed=$(rustup target list --installed 2>/dev/null)
  for t in "${required[@]}"; do
    if echo "$installed" | grep -q "$t"; then
      ok "  $t"
    else
      MISSING_TARGETS+=("$t")
      fail "  ${t}（未安装）"
    fi
  done
  [[ ${#MISSING_TARGETS[@]} -eq 0 ]]
}

# ─── Java ─────────────────────────────────────────────────────────────────────
get_java_major_version() {
  if ! command -v java &>/dev/null; then
    echo "0"
    return
  fi
  java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1
}

check_java17() {
  local ver
  ver=$(get_java_major_version)
  if [[ "$ver" -ge 17 ]]; then
    ok "Java $ver 已安装：$(which java)"
    return 0
  elif [[ "$ver" -gt 0 ]]; then
    fail "检测到 Java $ver，需要 JDK 17+"
    return 1
  else
    fail "未找到 Java，需要 JDK 17+"
    return 1
  fi
}
