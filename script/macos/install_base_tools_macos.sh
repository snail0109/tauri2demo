#!/usr/bin/env bash
# install_base_tools_macos.sh — macOS 基础开发工具安装脚本
# 安装 Xcode CLI Tools、Homebrew、pnpm、Rust（rustup）
#
# 用法：
#   ./install_base_tools_macos.sh              # 交互式安装
#   ./install_base_tools_macos.sh -y           # 静默安装
#   ./install_base_tools_macos.sh --add-tools rust,pnpm   # 安装指定工具
#   ./install_base_tools_macos.sh --add-tools all          # 安装所有工具

set -euo pipefail

source "$(dirname "$0")/_common.sh"

# ─── Parse args ───────────────────────────────────────────────────────────────
ADD_TOOLS=()
REMOVE_TOOLS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      shift
      ;;
    --add-tools)
      IFS=',' read -ra ADD_TOOLS <<< "${2:-}"
      shift 2
      ;;
    --add-tools=*)
      IFS=',' read -ra ADD_TOOLS <<< "${1#--add-tools=}"
      shift
      ;;
    --remove-tools)
      IFS=',' read -ra REMOVE_TOOLS <<< "${2:-}"
      shift 2
      ;;
    --remove-tools=*)
      IFS=',' read -ra REMOVE_TOOLS <<< "${1#--remove-tools=}"
      shift
      ;;
    -h|--help)
      echo "用法：$0 [--add-tools <tools>] [--remove-tools <tools>] [-y]"
      echo ""
      echo "  --add-tools <t1,t2,...>  安装指定工具（xcode, brew, pnpm, rust, all）"
      echo "  --remove-tools <t1,t2,...>  卸载指定工具"
      echo "  -y / --yes               静默模式"
      exit 0
      ;;
    *)
      echo "错误：未知参数 $1" >&2
      exit 1
      ;;
  esac
done

# ─── Tool definitions ─────────────────────────────────────────────────────────
declare -A TOOL_NAMES=(
  [xcode]="Xcode Command Line Tools"
  [brew]="Homebrew"
  [pnpm]="pnpm"
  [rust]="Rust (rustup)"
)

VALID_IDS="xcode brew pnpm rust"

# ─── Xcode CLI Tools ──────────────────────────────────────────────────────────

test_xcode() {
  if xcode-select -p &>/dev/null && clang --version &>/dev/null; then
    ok "Xcode Command Line Tools 已安装：$(clang --version 2>&1 | head -1)"
    return 0
  fi
  return 1
}

install_xcode() {
  echo ""
  echo -e "${CYAN}═══ 安装 Xcode Command Line Tools ═══${RESET}"
  echo ""

  if test_xcode; then
    echo -e "${GREEN}  Xcode Command Line Tools 已就绪${RESET}"
    return 0
  fi

  if ! confirm_install "安装 Xcode Command Line Tools（可能需约 5-15 分钟）"; then
    warn "已跳过 Xcode CLI Tools 安装"
    return 1
  fi

  echo -e "${CYAN}  正在触发 Xcode CLI Tools 安装 ...${RESET}"
  echo -e "${YELLOW}  系统将弹出安装对话框，请点击「安装」并等待完成。${RESET}"
  xcode-select --install 2>&1 || true

  echo ""
  echo -e "${YELLOW}  安装完成后按 Enter 继续验证 ...${RESET}"
  if [[ "$AUTO_YES" -eq 0 ]]; then
    read -r
  fi

  if test_xcode; then
    ok "Xcode Command Line Tools 安装成功"
    return 0
  fi

  warn "Xcode CLI Tools 安装可能未完成"
  warn "请确认安装对话框已完成，或手动运行：xcode-select --install"
  return 1
}

uninstall_xcode() {
  echo ""
  echo -e "${CYAN}═══ 卸载 Xcode Command Line Tools ═══${RESET}"
  echo ""
  warn "卸载 Xcode CLI Tools 会影响所有依赖命令行的开发工具"
  if ! confirm_remove "继续卸载 Xcode Command Line Tools"; then
    warn "已跳过"
    return 0
  fi

  local xcode_dir
  xcode_dir=$(xcode-select -p 2>/dev/null || echo "")
  if [[ -n "$xcode_dir" && -d "$xcode_dir" ]]; then
    sudo rm -rf "$xcode_dir" 2>/dev/null && ok "已删除 $xcode_dir" || fail "删除 $xcode_dir 失败"
  fi
  ok "Xcode CLI Tools 卸载完成"
}

# ─── Homebrew ─────────────────────────────────────────────────────────────────

test_brew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew 已安装：$(brew --version 2>&1 | head -1)"
    return 0
  fi
  return 1
}

install_brew() {
  echo ""
  echo -e "${CYAN}═══ 安装 Homebrew ═══${RESET}"
  echo ""

  if test_brew; then
    echo -e "${GREEN}  Homebrew 已就绪${RESET}"
    return 0
  fi

  if ! confirm_install "安装 Homebrew（macOS 包管理器）"; then
    warn "已跳过 Homebrew 安装"
    return 1
  fi

  echo -e "${CYAN}  正在安装 Homebrew ...${RESET}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 || true

  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if test_brew; then
    ok "Homebrew 安装成功"
    return 0
  fi

  fail "Homebrew 自动安装失败"
  fail "请手动访问 https://brew.sh 安装"
  return 1
}

uninstall_brew() {
  echo ""
  echo -e "${CYAN}═══ 卸载 Homebrew ═══${RESET}"
  echo ""
  warn "卸载 Homebrew 将删除所有通过 brew 安装的包"
  if ! confirm_remove "继续卸载 Homebrew"; then
    warn "已跳过"
    return 0
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" 2>&1 || true
  ok "Homebrew 卸载完成"
}

# ─── pnpm ─────────────────────────────────────────────────────────────────────

test_pnpm() {
  if command -v pnpm &>/dev/null; then
    ok "pnpm $(pnpm --version) 已安装"
    return 0
  fi
  return 1
}

install_pnpm() {
  echo ""
  echo -e "${CYAN}═══ 安装 pnpm ═══${RESET}"
  echo ""

  if test_pnpm; then
    echo -e "${GREEN}  pnpm 已就绪${RESET}"
    return 0
  fi

  if ! confirm_install "安装 pnpm（通过 npm install -g pnpm）"; then
    warn "已跳过 pnpm 安装"
    return 1
  fi

  if ! command -v npm &>/dev/null; then
    fail "未找到 npm，请先安装 Xcode Command Line Tools"
    return 1
  fi

  npm install -g pnpm 2>&1 && {
    ok "pnpm 安装成功"
    return 0
  } || {
    fail "pnpm 安装失败"
    return 1
  }
}

uninstall_pnpm() {
  echo ""
  echo -e "${CYAN}═══ 卸载 pnpm ═══${RESET}"
  echo ""

  if ! command -v pnpm &>/dev/null; then
    warn "pnpm 未安装，跳过"
    return 0
  fi

  if ! confirm_remove "卸载 pnpm"; then
    warn "已跳过"
    return 0
  fi

  npm uninstall -g pnpm 2>&1 && ok "pnpm 已卸载" || fail "pnpm 卸载失败"
}

# ─── Rust (rustup) ────────────────────────────────────────────────────────────

test_rust() {
  if command -v rustc &>/dev/null; then
    ok "Rust 已安装：$(rustc --version 2>&1 | head -1)"
    return 0
  fi
  if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "Rust 已安装：$(rustc --version 2>&1 | head -1)"
    return 0
  fi
  return 1
}

install_rust() {
  echo ""
  echo -e "${CYAN}═══ 安装 Rust（rustup）═══${RESET}"
  echo ""

  if test_rust; then
    echo -e "${GREEN}  Rust 已就绪${RESET}"
    return 0
  fi

  if ! confirm_install "安装 Rust 工具链（通过 rustup）"; then
    warn "已跳过 Rust 安装"
    return 1
  fi

  echo -e "${CYAN}  正在下载 rustup-init ...${RESET}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 || true

  if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "Rust 安装成功：$(rustc --version 2>&1 | head -1)"
    return 0
  fi

  fail "Rust 自动安装失败"
  fail "请手动访问 https://rustup.rs 安装"
  return 1
}

uninstall_rust() {
  echo ""
  echo -e "${CYAN}═══ 卸载 Rust ═══${RESET}"
  echo ""

  if ! command -v rustup &>/dev/null; then
    warn "未检测到 rustup，跳过"
    return 0
  fi

  if ! confirm_remove "完全卸载 Rust（移除所有工具链、~/.cargo、~/.rustup）"; then
    warn "已跳过"
    return 0
  fi

  rustup self uninstall -y 2>&1 || true
  ok "Rust 已卸载"
}

# ─── Tool dispatch ────────────────────────────────────────────────────────────

declare -A INSTALL_FUNCS=(
  [xcode]=install_xcode
  [brew]=install_brew
  [pnpm]=install_pnpm
  [rust]=install_rust
)

declare -A UNINSTALL_FUNCS=(
  [xcode]=uninstall_xcode
  [brew]=uninstall_brew
  [pnpm]=uninstall_pnpm
  [rust]=uninstall_rust
)

declare -A TEST_FUNCS=(
  [xcode]=test_xcode
  [brew]=test_brew
  [pnpm]=test_pnpm
  [rust]=test_rust
)

usage() {
  echo ""
  echo -e "${CYAN}═══ 基础工具管理（macOS）═══${RESET}"
  echo ""
  echo "用法：$0 --add-tools <工具1,工具2,...>   安装指定工具"
  echo "      $0 --add-tools all                  安装所有工具"
  echo "      $0 --remove-tools <工具1,工具2,...>  卸载指定工具"
  echo "      $0 --remove-tools all               卸载所有工具"
  echo "      $0 -y --add-tools all               静默安装所有工具"
  echo ""
  echo "可用工具："
  echo "  xcode  Xcode Command Line Tools"
  echo "  brew   Homebrew"
  echo "  pnpm   pnpm"
  echo "  rust   Rust (rustup)"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ ${#ADD_TOOLS[@]} -eq 0 && ${#REMOVE_TOOLS[@]} -eq 0 ]]; then
  usage
  exit 0
fi

# 展开别名
if [[ "${ADD_TOOLS[*]}" == "all" ]]; then
  ADD_TOOLS=(xcode brew pnpm rust)
fi
if [[ "${REMOVE_TOOLS[*]}" == "all" ]]; then
  REMOVE_TOOLS=(xcode brew pnpm rust)
fi

# 校验
for t in "${ADD_TOOLS[@]}"; do
  if [[ ! "$VALID_IDS" =~ $t ]]; then
    echo -e "${RED}  未知工具（--add-tools）：$t${RESET}"
    echo "  可用：xcode, brew, pnpm, rust, all"
    exit 1
  fi
done
for t in "${REMOVE_TOOLS[@]}"; do
  if [[ ! "$VALID_IDS" =~ $t ]]; then
    echo -e "${RED}  未知工具（--remove-tools）：$t${RESET}"
    echo "  可用：xcode, brew, pnpm, rust, all"
    exit 1
  fi
done

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  基础工具管理（macOS）                  ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

# ── 卸载流程 ──
if [[ ${#REMOVE_TOOLS[@]} -gt 0 ]]; then
  step=0 total=${#REMOVE_TOOLS[@]}
  for t in "${REMOVE_TOOLS[@]}"; do
    step=$((step + 1))
    echo -e "${CYAN}[$step/$total] 卸载 ${TOOL_NAMES[$t]}${RESET}"
    ${UNINSTALL_FUNCS[$t]}
    echo ""
  done
fi

# ── 安装流程 ──
if [[ ${#ADD_TOOLS[@]} -gt 0 ]]; then
  needs_brew=0
  for t in "${ADD_TOOLS[@]}"; do
    if [[ "$t" != "brew" && "$t" != "xcode" ]]; then
      needs_brew=1
    fi
  done
  if [[ "$needs_brew" -eq 1 ]] && ! command -v brew &>/dev/null && [[ ! " ${ADD_TOOLS[*]} " =~ " brew " ]]; then
    warn "检测到需要 Homebrew 但未选择安装，将自动前置安装"
    ADD_TOOLS=(brew "${ADD_TOOLS[@]}")
  fi

  step=0 total=${#ADD_TOOLS[@]}
  for t in "${ADD_TOOLS[@]}"; do
    step=$((step + 1))
    echo -e "${CYAN}[$step/$total] 安装 ${TOOL_NAMES[$t]}${RESET}"
    ${INSTALL_FUNCS[$t]}
    echo ""
  done
fi

# ── 摘要 ──
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
if [[ "$FAILED" -ne 0 ]]; then
  echo -e "${RED}  部分操作未完成，请查看上方日志${RESET}"
else
  echo -e "${GREEN}  操作完成！${RESET}"
fi
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

exit "$FAILED"
