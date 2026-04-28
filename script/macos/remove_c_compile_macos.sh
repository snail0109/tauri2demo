#!/usr/bin/env bash
# remove_c_compile_macos.sh — install_c_compile_macos.sh 的反向操作
# 功能：
#   按用户选择卸载以下任一组合：
#     1) Rust 工具链（保留 rustup）
#     2) rustup + 全部 Rust 工具链
#     3) 全部卸载（Rust + rustup）
#
# 注意：Xcode CLI Tools 不会被卸载（系统级工具，影响范围太大）
#
# 用法：
#   ./remove_c_compile_macos.sh              # 交互式
#   ./remove_c_compile_macos.sh -y           # 静默模式（自动确认）

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

# ─── 卸载所有 Rust 工具链（保留 rustup）─────────────────────────────────────

remove_all_rust_toolchains() {
  if ! command -v rustup &>/dev/null; then
    ensure_cargo_bin
    if ! command -v rustup &>/dev/null; then
      warn "未检测到 rustup，跳过"
      return 0
    fi
  fi

  local toolchains
  toolchains=$(rustup toolchain list 2>/dev/null | awk '{print $1}')
  if [[ -z "$toolchains" ]]; then
    warn "未检测到 Rust 工具链，跳过"
    return 0
  fi

  local count
  count=$(echo "$toolchains" | wc -l | tr -d ' ')

  if confirm_remove "卸载所有 Rust 工具链（共 $count 个）"; then
    while IFS= read -r tc; do
      [[ -z "$tc" ]] && continue
      if rustup toolchain uninstall "$tc" 2>&1; then
        ok "已卸载 $tc"
      else
        fail "卸载 $tc 失败"
      fi
    done <<< "$toolchains"
  else
    warn "已跳过"
  fi
}

# ─── 卸载指定 host-target 的 Rust 工具链 ─────────────────────────────────────

remove_host_rust_toolchain() {
  ensure_cargo_bin

  if ! command -v rustc &>/dev/null; then
    warn "未检测到 rustc，跳过"
    return 0
  fi

  local host_target
  host_target=$(rustc -vV 2>/dev/null | awk -F': ' '/^host:/{print $2}' | tr -d '\r ')
  if [[ -z "$host_target" ]]; then
    warn "无法检测 Rust host target，跳过"
    return 0
  fi

  local toolchain="stable-${host_target}"

  if ! rustup toolchain list 2>/dev/null | grep -q "^${toolchain}"; then
    warn "Rust 工具链 ${toolchain} 未安装，跳过"
    return 0
  fi

  if confirm_remove "卸载 Rust 工具链 ${toolchain}"; then
    if rustup toolchain uninstall "${toolchain}" 2>&1; then
      ok "已卸载 ${toolchain}"
    else
      fail "rustup toolchain uninstall ${toolchain} 失败"
    fi
  fi
}

# ─── 卸载 rustup ──────────────────────────────────────────────────────────────

remove_rustup() {
  ensure_cargo_bin

  if ! command -v rustup &>/dev/null; then
    warn "未检测到 rustup"
    return 0
  fi

  if confirm_remove "完全卸载 rustup（移除所有工具链、~/.cargo、~/.rustup）"; then
    rustup self uninstall -y 2>&1 || true
    if command -v rustup &>/dev/null; then
      fail "rustup self uninstall 后仍能找到 rustup，可能需要重启 shell"
    else
      ok "rustup 已卸载"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

ensure_cargo_bin

echo ""
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo -e "${RED}  C/C++ 编译工具卸载（macOS）            ${RESET}"
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo ""
warn "本脚本会卸载 Rust 工具链，不影响 Xcode CLI Tools（系统级工具）。"
echo ""

select_menu_option "请选择要卸载的内容：" \
  "Rust 工具链（保留 rustup）" \
  "rustup + 全部 Rust 工具链" \
  "全部卸载（Rust 工具链 + rustup + ~/.cargo + ~/.rustup）"

case "$SELECTED_OPTION" in
  1) remove_host_rust_toolchain ;;
  2)
    remove_all_rust_toolchains
    remove_rustup
    ;;
  3)
    warn "即将依次卸载：所有 Rust 工具链 → rustup → ~/.cargo → ~/.rustup"
    if ! confirm_remove "确认执行全部卸载（请慎重）"; then
      echo ""
      echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
      exit 0
    fi
    remove_all_rust_toolchains
    remove_rustup
    ;;
  0)
    echo ""
    echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
    exit 0
    ;;
esac

echo ""
banner "卸载结束摘要"

echo -e "  clang     ：$(command -v clang >/dev/null 2>&1 && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"
echo -e "  rustup    ：$(command -v rustup >/dev/null 2>&1 && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"
echo -e "  rustc     ：$(command -v rustc >/dev/null 2>&1 && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"
echo -e "  ~/.cargo  ：$([[ -d "$HOME/.cargo" ]] && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  卸载完成！${RESET}"
else
  echo -e "${YELLOW}  卸载流程已结束，但部分步骤失败，请查看上方日志。${RESET}"
fi

exit "$FAILED"
