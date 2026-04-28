#!/usr/bin/env bash
# install_c_compile_macos.sh — macOS C/C++ 编译工具链检查与安装
# macOS 上 C/C++ 编译器由 Xcode Command Line Tools 提供（clang/clang++），
# 本脚本确保 Xcode CLI Tools 和 Rust 工具链匹配主机架构。
#
# 用法：
#   ./install_c_compile_macos.sh              # 交互式
#   ./install_c_compile_macos.sh -y           # 静默模式

set -euo pipefail

source "$(dirname "$0")/_common.sh"

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

# ─── Xcode CLI Tools（提供 clang/clang++） ────────────────────────────────────

test_clang() {
  if xcode-select -p &>/dev/null && clang --version &>/dev/null; then
    local clang_ver
    clang_ver=$(clang --version 2>&1 | head -1)
    ok "clang 已安装：${clang_ver}"
    return 0
  fi
  return 1
}

install_xcode_clt() {
  if test_clang; then
    return 0
  fi

  if ! confirm_install "安装 Xcode Command Line Tools（提供 clang 编译器）"; then
    warn "已跳过 Xcode CLI Tools 安装"
    return 1
  fi

  echo -e "${CYAN}  正在触发安装 Xcode CLI Tools ...${RESET}"
  echo -e "${YELLOW}  系统将弹出安装对话框，请点击「安装」。${RESET}"
  xcode-select --install 2>&1 || true

  echo -e "${YELLOW}  安装完成后按 Enter 继续 ...${RESET}"
  if [[ "$AUTO_YES" -eq 0 ]]; then
    read -r
  fi

  if test_clang; then
    ok "Xcode Command Line Tools 安装成功"
    return 0
  fi

  fail "Xcode CLI Tools 安装未完成"
  fail "请手动运行：xcode-select --install"
  return 1
}

# ─── Rust 工具链 ──────────────────────────────────────────────────────────────

RUSTC_VERSION=""
RUSTC_HOST=""

test_rust() {
  ensure_cargo_bin

  if ! command -v rustc &>/dev/null; then
    return 1
  fi

  RUSTC_VERSION=$(rustc --version 2>&1 | head -1)
  RUSTC_HOST=$(rustc -vV 2>/dev/null | awk -F': ' '/^host:/{print $2}' | tr -d '\r ')
  ok "Rust 工具链已安装"
  echo -e "    host：${RUSTC_HOST}"
  echo -e "    版本：${RUSTC_VERSION}"
  return 0
}

install_rustup() {
  if command -v rustup &>/dev/null; then
    return 0
  fi
  if [[ -f "$HOME/.cargo/bin/rustup" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    return 0
  fi

  echo ""
  echo -e "${CYAN}═══ 安装 rustup ═══${RESET}"

  if ! confirm_install "安装 rustup（Rust 工具链管理器）"; then
    warn "已跳过 rustup 安装"
    return 1
  fi

  echo -e "${CYAN}  正在下载 rustup-init ...${RESET}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 || true

  if [[ -f "$HOME/.cargo/bin/rustup" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "rustup 安装成功"
    return 0
  fi

  fail "rustup 自动安装失败"
  fail "请手动访问 https://rustup.rs 安装"
  return 1
}

ensure_rust_toolchain() {
  local host_target="${RUSTC_HOST:-}"
  if [[ -z "$host_target" ]]; then
    host_target=$(rustc -vV 2>/dev/null | awk -F': ' '/^host:/{print $2}' | tr -d '\r ' || echo "")
  fi

  if [[ -z "$host_target" ]]; then
    fail "无法检测 Rust host target"
    return 1
  fi

  local toolchain="stable-${host_target}"

  if ! rustup toolchain list 2>/dev/null | grep -q "^${toolchain}"; then
    if confirm_install "通过 rustup 安装 ${toolchain} 工具链"; then
      rustup toolchain install "${toolchain}" 2>&1 && {
        ok "Rust 工具链 ${toolchain} 安装成功"
      } || {
        fail "rustup toolchain install ${toolchain} 失败"
        return 1
      }
    fi
  fi

  local current_default
  current_default=$(rustup default 2>/dev/null | awk '{print $1}')
  if [[ "$current_default" != "${toolchain}" ]]; then
    if confirm_install "将 ${toolchain} 设为默认 Rust 工具链（当前：${current_default:-未设置}）"; then
      rustup default "${toolchain}" 2>&1 || warn "设置默认工具链失败"
    fi
  fi

  test_rust >/dev/null 2>&1 || true
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  C/C++ 编译工具检查与安装（macOS）       ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

# ─── 步骤 1：检查 C/C++ 编译器 ───────────────────────────────────────────────
echo -e "${CYAN}[1/3] 检查 C/C++ 编译器（clang）${RESET}"

HAS_CLANG=0
if test_clang; then
  HAS_CLANG=1
fi

if [[ "$HAS_CLANG" -eq 1 ]]; then
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"
  echo -e "${GREEN}  C/C++ 编译工具已就绪${RESET}"
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"

  echo ""
  echo -e "${CYAN}[2/3] 检查 Rust 工具链${RESET}"
  if ! test_rust; then
    warn "未检测到 rustc/rustup"
    if install_rustup; then
      test_rust >/dev/null 2>&1 || true
    fi
  fi

  if command -v rustup &>/dev/null; then
    ensure_rust_toolchain || true
  fi

  echo ""
  echo -e "${CYAN}[3/3] 环境摘要${RESET}"
  echo -e "  clang     ：${GREEN}已安装${RESET}"
  if [[ -n "$RUSTC_HOST" ]]; then
    echo -e "  Rust      ：${GREEN}已安装 —— ${RUSTC_HOST}${RESET}"
  else
    echo -e "  Rust      ：${YELLOW}未安装${RESET}"
  fi
  echo ""
  echo -e "${GREEN}  检查完成，C/C++ 编译工具可用。${RESET}"
  exit 0
fi

# ─── 未安装：自动安装 Xcode CLI Tools ────────────────────────────────────────
echo ""
echo -e "${RED}  ✗ 未检测到 C/C++ 编译器（clang）${RESET}"
echo ""
echo -e "${CYAN}[2/3] 安装 Xcode Command Line Tools${RESET}"

if install_xcode_clt; then
  HAS_CLANG=1
else
  fail "C/C++ 编译器安装失败"
  fail "请手动安装 Xcode Command Line Tools：xcode-select --install"
  exit 1
fi

echo ""
echo -e "${CYAN}[3/3] 安装 Rust 工具链${RESET}"

if ! test_rust; then
  if install_rustup; then
    test_rust >/dev/null 2>&1 || true
  fi
fi

if command -v rustup &>/dev/null; then
  ensure_rust_toolchain || true
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "  clang     ：$(test_clang >/dev/null 2>&1 && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
if [[ -n "$RUSTC_HOST" ]]; then
  echo -e "  Rust      ：${GREEN}已安装 —— ${RUSTC_HOST}${RESET}"
else
  echo -e "  Rust      ：${YELLOW}未安装${RESET}"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  工具链安装完成！${RESET}"
else
  echo -e "${YELLOW}  工具链安装已完成，但部分步骤可能需要手动处理。${RESET}"
fi
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

exit "$FAILED"
