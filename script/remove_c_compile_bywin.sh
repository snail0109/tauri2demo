#!/usr/bin/env bash
# remove_c_compile_bywin.sh — install_c_compile_bywin.sh 的反向操作
# 功能：
#   按用户选择卸载以下任一组合：
#     1) MSVC + Rust(msvc) 工具链
#     2) GNU (MinGW-w64) + Rust(gnu) 工具链
#     3) 仅卸载 rustup（连带所有 Rust 工具链）
#     4) 卸载整个 MSYS2 发行版（含所有 mingw-w64 包）
#     5) 全部卸载（最危险，需多次确认）
#
# 运行环境假设：MSYS2 mingw64 shell（pacman、winget、rustup 均在 PATH 中）。
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

# ─── 卸载特定 ABI 的 Rust 工具链 ────────────────────────────────────────────
# 参数：msvc | gnu
remove_rust_toolchain() {
  local abi="$1"
  local toolchain="stable-x86_64-pc-windows-${abi}"

  if ! command -v rustup &>/dev/null; then
    warn "未检测到 rustup，跳过 Rust 工具链卸载"
    return 0
  fi

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
  else
    warn "已跳过 ${toolchain}"
  fi
}

# ─── 卸载所有 Rust 工具链 ────────────────────────────────────────────────────
remove_all_rust_toolchains() {
  if ! command -v rustup &>/dev/null; then
    return 0
  fi
  local toolchains
  toolchains=$(rustup toolchain list 2>/dev/null | awk '{print $1}')
  [[ -z "$toolchains" ]] && return 0

  if confirm_remove "卸载所有 Rust 工具链（共 $(echo "$toolchains" | wc -l) 个）"; then
    while read -r tc; do
      [[ -z "$tc" ]] && continue
      rustup toolchain uninstall "$tc" 2>&1 && ok "已卸载 $tc" || fail "卸载 $tc 失败"
    done <<< "$toolchains"
  fi
}

# ─── 卸载 rustup（包含 ~/.cargo 和 ~/.rustup） ──────────────────────────────
remove_rustup() {
  if ! command -v rustup &>/dev/null; then
    warn "未检测到 rustup"
    return 0
  fi

  if confirm_remove "完全卸载 rustup（移除所有 Rust 工具链、~/.cargo、~/.rustup）"; then
    rustup self uninstall -y 2>&1 || true
    if command -v rustup &>/dev/null; then
      fail "rustup self uninstall 后仍能找到 rustup，可能需要重启 shell 或手动清理"
    else
      ok "rustup 已卸载"
    fi
  fi
}

# ─── 卸载 mingw-w64 GCC / binutils（仅卸载包，保留 MSYS2） ──────────────────
remove_mingw_packages() {
  if [[ ! -d "/c/msys64" ]]; then
    warn "未检测到 MSYS2，跳过 mingw-w64 包卸载"
    return 0
  fi
  if ! command -v pacman &>/dev/null; then
    warn "当前 shell 中无 pacman，请在 MSYS2 mingw64 shell 中执行此脚本"
    return 1
  fi

  local pkgs="mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils"
  if confirm_remove "卸载 ${pkgs}"; then
    if pacman -R --noconfirm $pkgs 2>&1; then
      ok "已卸载 ${pkgs}"
    else
      fail "pacman -R 卸载失败（可能依赖被其他包引用）"
    fi
  fi
}

# ─── 完全卸载 MSYS2 ──────────────────────────────────────────────────────────
remove_msys2() {
  if [[ ! -d "/c/msys64" ]]; then
    warn "未检测到 MSYS2 安装目录 C:\\msys64"
    return 0
  fi

  warn "卸载 MSYS2 将删除整个 C:\\msys64 目录及所有已装包（含其他工具）"
  if ! confirm_remove "继续卸载整个 MSYS2"; then
    return 0
  fi

  # 优先尝试 winget
  if command -v winget &>/dev/null; then
    winget uninstall MSYS2.MSYS2 --silent 2>&1 || true
  fi

  if [[ -d "/c/msys64" ]]; then
    warn "winget 卸载后 C:\\msys64 仍存在。请关闭所有 MSYS2 / Git Bash 终端，"
    warn "然后在 PowerShell（管理员）中手动删除："
    warn "  Remove-Item -Recurse -Force C:\\msys64"
    fail "MSYS2 未完全卸载（目录仍存在）"
  else
    ok "MSYS2 已完全卸载"
  fi
}

# ─── 卸载 MSVC Build Tools ───────────────────────────────────────────────────
remove_msvc() {
  if ! command -v cl.exe &>/dev/null && ! command -v winget &>/dev/null; then
    warn "未检测到 MSVC 或 winget，跳过"
    return 0
  fi

  warn "卸载 MSVC 将影响所有依赖 Visual Studio Build Tools 的项目"
  if ! confirm_remove "卸载 Visual Studio Build Tools (2022 / 2019)"; then
    return 0
  fi

  if command -v winget &>/dev/null; then
    # 先试 2022，再试 2019；至少一个成功即可
    local removed=0
    if winget uninstall Microsoft.VisualStudio.2022.BuildTools --silent 2>&1; then
      ok "已请求卸载 Microsoft.VisualStudio.2022.BuildTools"
      removed=1
    fi
    if winget uninstall Microsoft.VisualStudio.2019.BuildTools --silent 2>&1; then
      ok "已请求卸载 Microsoft.VisualStudio.2019.BuildTools"
      removed=1
    fi
    if [[ "$removed" -eq 0 ]]; then
      warn "winget 未匹配到已安装的 Visual Studio Build Tools"
      warn "请通过「Visual Studio Installer」GUI 手动卸载"
    fi
  else
    warn "winget 不可用，请手动通过「Visual Studio Installer」卸载"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo -e "${RED}  C/C++ 编译工具卸载（Windows）          ${RESET}"
echo -e "${RED}══════════════════════════════════════════${RESET}"
echo ""
warn "本脚本会卸载系统级开发工具，可能影响其它项目。请确认你了解每一步。"
echo ""

select_option "请选择要卸载的内容：" \
  "MSVC + Rust(msvc) 工具链" \
  "GNU (MinGW-w64) + Rust(gnu) 工具链" \
  "仅卸载 rustup（连带所有 Rust 工具链）" \
  "卸载整个 MSYS2 发行版" \
  "全部卸载（rustup + MSYS2 + MSVC）"

case "$SELECTED_OPTION" in
  1)
    remove_rust_toolchain msvc
    remove_msvc
    ;;
  2)
    remove_rust_toolchain gnu
    remove_mingw_packages
    ;;
  3)
    remove_rustup
    ;;
  4)
    remove_msys2
    ;;
  5)
    warn "即将依次卸载：所有 Rust 工具链 → rustup → MSYS2 → MSVC"
    if ! confirm_remove "确认执行全部卸载（请慎重）"; then
      echo ""
      echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
      exit 0
    fi
    remove_all_rust_toolchains
    remove_rustup
    remove_msys2
    remove_msvc
    ;;
  0)
    echo ""
    echo -e "${YELLOW}  已退出，未卸载任何内容。${RESET}"
    exit 0
    ;;
esac

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  卸载结束摘要                            ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "  MSVC      ：$(command -v cl.exe >/dev/null 2>&1 && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"
echo -e "  GNU GCC   ：$(command -v gcc    >/dev/null 2>&1 && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"
echo -e "  rustup    ：$(command -v rustup >/dev/null 2>&1 && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"
echo -e "  MSYS2     ：$([[ -d /c/msys64 ]]              && echo -e "${YELLOW}仍存在${RESET}" || echo -e "${GREEN}已移除${RESET}")"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  卸载完成！${RESET}"
else
  echo -e "${YELLOW}  卸载流程已结束，但部分步骤失败或未完成，请查看上方日志手动处理。${RESET}"
fi
