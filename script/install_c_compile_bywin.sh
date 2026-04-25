#!/usr/bin/env bash
# install_c_compile_bywin.sh — Windows (Git Bash / MSYS2) C/C++ 编译工具安装脚本
# 功能：
#   1. 检查是否已安装 C/C++ 编译器（MSVC / GNU gcc）
#   2. 如果已安装，显示环境信息后退出
#   3. 如果未安装，让用户选择安装 MSVC 或 GNU 工具链

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

ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*"; FAILED=1; }

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
  echo -e "  ${CYAN}0)${RESET} 退出（不安装）"
  echo ""
  echo -ne "${YELLOW}  请选择 [0-$((i-1))]：${RESET}"
  read -r choice

  if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] 2>/dev/null; then
    SELECTED_OPTION="$choice"
  else
    SELECTED_OPTION=0
  fi
}

# ─── 检查 MSVC ───────────────────────────────────────────────────────────────
check_msvc() {
  if command -v cl.exe &>/dev/null; then
    MSVC_PATH="$(which cl.exe)"
    # 尝试获取 MSVC 版本信息
    CL_INFO=$(cl.exe 2>&1 | head -2 | tr '\r' ' ' | tr '\n' ' ')
    echo -e "${GREEN}  ✓${RESET} MSVC cl.exe 已安装"
    echo -e "    路径：${MSVC_PATH}"
    echo -e "    版本：${CL_INFO}"
    return 0
  fi
  return 1
}

# ─── 检查 GNU gcc ────────────────────────────────────────────────────────────
check_gnu() {
  FOUND=0
  if command -v gcc &>/dev/null && gcc --version &>/dev/null; then
    GCC_PATH="$(which gcc)"
    GCC_INFO=$(gcc --version 2>&1 | head -1)
    echo -e "${GREEN}  ✓${RESET} GNU gcc 已安装"
    echo -e "    路径：${GCC_PATH}"
    echo -e "    版本：${GCC_INFO}"
    FOUND=1

    if command -v g++ &>/dev/null && g++ --version &>/dev/null; then
      GPP_INFO=$(g++ --version 2>&1 | head -1)
      echo -e "    g++ ：$(which g++) — ${GPP_INFO}"
    else
      warn "gcc 已找到但 g++ 未找到，部分 C++ 依赖可能编译失败"
    fi
  fi

  if [[ "$FOUND" -eq 0 ]] && command -v cc &>/dev/null && cc --version &>/dev/null; then
    CC_INFO=$(cc --version 2>&1 | head -1)
    echo -e "${GREEN}  ✓${RESET} C 编译器已安装"
    echo -e "    路径：$(which cc)"
    echo -e "    版本：${CC_INFO}"
    FOUND=1
  fi

  if [[ "$FOUND" -eq 1 ]]; then
    return 0
  fi
  return 1
}

# ─── 检查 Rust GNU 工具链（间接验证 gcc 可用） ──────────────────────────────
check_rust_gnu() {
  if ! command -v rustc &>/dev/null; then
    return 1
  fi

  RUSTC_INFO=$(rustc --version --verbose 2>&1 | head -2 | tr '\n' ' ')
  TEST_SRC=$(mktemp /tmp/test_rust_XXXXXX.rs)
  TEST_BIN=$(mktemp /tmp/test_rust_XXXXXX.exe)
  echo 'fn main() {}' > "$TEST_SRC"
  if rustc "$TEST_SRC" -o "$TEST_BIN" 2>/dev/null; then
    rm -f "$TEST_SRC" "$TEST_BIN"
    echo -e "${GREEN}  ✓${RESET} Rust GNU 工具链可用（gcc 由 Rust 自带）"
    echo -e "    版本：${RUSTC_INFO}"
    return 0
  else
    rm -f "$TEST_SRC" "$TEST_BIN"
    return 1
  fi
}

# ─── 检查 GNU 汇编器 as.exe ─────────────────────────────────────────────────
check_as() {
  MSYS2_MINGW_BIN="/c/msys64/mingw64/bin"
  if command -v as &>/dev/null; then
    ok "GNU 汇编器 as 已在 PATH 中"
    return 0
  elif [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
    export PATH="${MSYS2_MINGW_BIN}:${PATH}"
    ok "GNU 汇编器 as 已找到：${MSYS2_MINGW_BIN}/as.exe（已添加到 PATH）"
    return 0
  fi
  return 1
}

# ─── 安装 MSVC ───────────────────────────────────────────────────────────────
install_msvc() {
  echo ""
  echo -e "${CYAN}═══ 安装 MSVC (Visual Studio Build Tools) ═══${RESET}"
  echo ""
  echo -e "  MSVC 需要通过 Visual Studio Installer 安装，步骤如下："
  echo ""
  echo -e "  ${YELLOW}方式一：自动下载安装器${RESET}"
  echo -e "    脚本将下载 vs_BuildTools.exe 并启动安装"
  echo ""
  echo -e "  ${YELLOW}方式二：手动安装${RESET}"
  echo -e "    1. 访问 https://visualstudio.microsoft.com/visual-cpp-build-tools/"
  echo -e "    2. 下载 Build Tools for Visual Studio"
  echo -e "    3. 安装时勾选「使用 C++ 的桌面开发」工作负载"
  echo ""

  if confirm_install "自动下载并启动 MSVC Build Tools 安装器"; then
    local installer_path
    installer_path="$(mktemp /tmp/vs_buildtools_XXXXXX.exe)"
    echo -e "${CYAN}  正在下载 Visual Studio Build Tools 安装器 ...${RESET}"
    if curl -fSL -o "$installer_path" "https://aka.ms/vs/17/release/vs_BuildTools.exe" 2>/dev/null; then
      ok "下载完成，正在启动安装器 ..."
      echo -e "${YELLOW}  请在安装器中勾选「使用 C++ 的桌面开发」工作负载${RESET}"
      # --wait 让安装器阻塞直到安装完成
      cmd.exe /c "$installer_path" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait 2>&1 || true
      rm -f "$installer_path"

      # 安装完成后刷新 PATH 并重新检查
      refresh_path
      echo ""
      echo -e "${CYAN}  重新检查 MSVC ...${RESET}"
      if check_msvc; then
        ok "MSVC 安装成功！"
        return 0
      else
        warn "MSVC 安装器已运行，但当前 shell 未检测到 cl.exe"
        warn "请重新打开终端后再次运行此脚本验证"
        return 0
      fi
    else
      rm -f "$installer_path"
      fail "下载 Visual Studio Build Tools 安装器失败"
      fail "请手动访问 https://visualstudio.microsoft.com/visual-cpp-build-tools/ 下载安装"
      return 1
    fi
  else
    warn "已跳过 MSVC 自动安装，请手动安装后重新运行此脚本"
    return 1
  fi
}

# ─── 安装 GNU gcc ────────────────────────────────────────────────────────────
install_gnu() {
  echo ""
  echo -e "${CYAN}═══ 安装 GNU gcc (MinGW-w64) ═══${RESET}"
  echo ""

  # 优先尝试 pacman（MSYS2 环境）
  if command -v pacman &>/dev/null; then
    if confirm_install "通过 pacman 安装 mingw-w64-x86_64-gcc"; then
      pacman -S --noconfirm mingw-w64-x86_64-gcc && {
        ok "mingw-w64-x86_64-gcc 安装成功"
        refresh_path
        if check_gnu; then
          ok "GNU gcc 安装验证通过！"
        fi
        return 0
      } || warn "pacman 安装失败"
    fi
  fi

  # 尝试通过 rustup 安装 GNU 工具链
  if command -v rustup &>/dev/null; then
    if confirm_install "通过 rustup 安装 stable-x86_64-pc-windows-gnu 工具链"; then
      rustup toolchain install stable-x86_64-pc-windows-gnu && {
        ok "Rust GNU 工具链安装成功"
        # 验证编译
        TEST_SRC=$(mktemp /tmp/test_rust_XXXXXX.rs)
        TEST_BIN=$(mktemp /tmp/test_rust_XXXXXX.exe)
        echo 'fn main() {}' > "$TEST_SRC"
        if rustc "$TEST_SRC" -o "$TEST_BIN" 2>/dev/null; then
          ok "Rust GNU 工具链编译链接验证通过"
          rm -f "$TEST_SRC" "$TEST_BIN"
          return 0
        else
          warn "Rust GNU 工具链安装后编译链接仍失败"
          rm -f "$TEST_SRC" "$TEST_BIN"
        fi
      } || warn "rustup 工具链安装失败"
    fi
  fi

  # 尝试通过 winget 安装 MSYS2（包含 gcc）
  if command -v winget &>/dev/null; then
    if confirm_install "通过 winget 安装 MSYS2（包含 mingw-w64-gcc）"; then
      winget install MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements 2>&1
      if [[ -d "/c/msys64" ]]; then
        /c/msys64/usr/bin/bash.exe -lc "pacman-key --init && pacman-key --populate msys2 && pacman -Sy --noconfirm archlinux-msys2-keyring && pacman -Su --noconfirm && pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils" 2>&1
        MSYS2_MINGW_BIN="/c/msys64/mingw64/bin"
        if [[ -f "${MSYS2_MINGW_BIN}/gcc.exe" ]]; then
          export PATH="${MSYS2_MINGW_BIN}:${PATH}"
          ok "MSYS2 + mingw-w64-gcc 安装成功"
          if check_gnu; then
            ok "GNU gcc 安装验证通过！"
          fi
          return 0
        else
          warn "MSYS2 已安装但 gcc 未找到，请手动执行："
          warn "  /c/msys64/usr/bin/bash.exe -lc 'pacman -S --noconfirm mingw-w64-x86_64-gcc'"
        fi
      else
        warn "winget 安装 MSYS2 后未在 C:\\msys64 找到安装目录"
      fi
    fi
  fi

  # 所有自动安装方式都失败
  fail "GNU gcc 自动安装失败或被跳过"
  fail "请手动安装以下任一工具链："
  fail "  • MSYS2: https://www.msys2.org/ 安装后运行 pacman -S mingw-w64-x86_64-gcc"
  fail "  • MinGW-w64: https://www.mingw-w64.org/"
  fail "  • Rust + GNU: https://rustup.rs 安装时选择 x86_64-pc-windows-gnu"
  return 1
}

# ─── 安装 GNU 汇编器 as.exe ─────────────────────────────────────────────────
install_as() {
  MSYS2_MINGW_BIN="/c/msys64/mingw64/bin"

  if check_as; then
    return 0
  fi

  warn "未找到 GNU 汇编器 as.exe，Rust dlltool 将无法创建导入库（编译会报 CreateProcess 错误）"

  if [[ -d "/c/msys64" ]]; then
    if confirm_install "通过 MSYS2 pacman 安装 mingw-w64-x86_64-binutils"; then
      /c/msys64/usr/bin/bash.exe -lc "pacman -S --noconfirm --needed mingw-w64-x86_64-binutils" 2>&1
      if [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
        export PATH="${MSYS2_MINGW_BIN}:${PATH}"
        ok "mingw-w64-x86_64-binutils 安装成功，as.exe 已添加到 PATH"
        return 0
      else
        warn "pacman 安装完成但未找到 as.exe，可能需要更新 MSYS2："
        warn "  /c/msys64/usr/bin/bash.exe -lc 'pacman -Syu --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-binutils'"
      fi
    fi
  else
    if confirm_install "通过 winget 安装 MSYS2，然后安装 mingw-w64-x86_64-binutils"; then
      winget install MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements 2>&1
      if [[ -d "/c/msys64" ]]; then
        /c/msys64/usr/bin/bash.exe -lc "pacman-key --init && pacman-key --populate msys2 && pacman -Sy --noconfirm archlinux-msys2-keyring && pacman -Su --noconfirm && pacman -S --noconfirm --needed mingw-w64-x86_64-binutils" 2>&1
        if [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
          export PATH="${MSYS2_MINGW_BIN}:${PATH}"
          ok "MSYS2 + binutils 安装成功，as.exe 已添加到 PATH"
          return 0
        else
          warn "MSYS2 已安装但 binutils 安装可能不完整，请手动执行："
          warn "  /c/msys64/usr/bin/bash.exe -lc 'pacman -S --noconfirm mingw-w64-x86_64-binutils'"
        fi
      else
        warn "winget 安装 MSYS2 后未在 C:\\msys64 找到安装目录"
      fi
    fi
  fi

  fail "缺少 GNU 汇编器 as.exe，Android 交叉编译将失败。"
  fail "请安装 MSYS2（https://www.msys2.org/）并运行："
  fail "  pacman -S mingw-w64-x86_64-binutils"
  fail "然后将 C:\\msys64\\mingw64\\bin 添加到 PATH"
  return 1
}

refresh_path() {
  local win_path
  win_path="$(powershell -Command "[Environment]::GetEnvironmentVariable('PATH','User')" 2>/dev/null | tr -d '\r')"
  if [[ -n "$win_path" ]]; then
    local unix_path
    unix_path="$(cygpath -u "$win_path" 2>/dev/null || echo "$win_path")"
    export PATH="${PATH}:${unix_path}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  C/C++ 编译工具检查与安装（Windows）    ${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo ""

FAILED=0
FOUND_CC=0

# ─── 步骤 1：检查是否已安装 C/C++ 编译器 ─────────────────────────────────────
echo -e "${CYAN}[1/3] 检查 C/C++ 编译器${RESET}"

HAS_MSVC=0
HAS_GNU=0
HAS_RUST_GNU=0

if check_msvc; then
  HAS_MSVC=1
  FOUND_CC=1
fi

if check_gnu; then
  HAS_GNU=1
  FOUND_CC=1
fi

if [[ "$FOUND_CC" -eq 0 ]] && check_rust_gnu; then
  HAS_RUST_GNU=1
  FOUND_CC=1
fi

# ─── 已安装：显示环境信息后退出 ──────────────────────────────────────────────
if [[ "$FOUND_CC" -eq 1 ]]; then
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"
  echo -e "${GREEN}  C/C++ 编译工具已就绪${RESET}"
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"

  # ─── 步骤 2（已安装分支）：检查 as.exe ────────────────────────────────────
  echo ""
  echo -e "${CYAN}[2/3] 检查 GNU 汇编器 as.exe${RESET}"
  if ! check_as; then
    # as.exe 缺失，尝试安装
    install_as
  fi

  # ─── 步骤 3：显示环境摘要 ──────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}[3/3] 环境摘要${RESET}"
  echo -e "  MSVC      ：$([ "$HAS_MSVC" -eq 1 ] && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
  echo -e "  GNU gcc   ：$([ "$HAS_GNU" -eq 1 ] && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
  echo -e "  Rust GNU  ：$([ "$HAS_RUST_GNU" -eq 1 ] && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"

  echo ""
  echo -e "${GREEN}  检查完成，C/C++ 编译工具可用。${RESET}"
  exit 0
fi

# ─── 未安装：让用户选择安装方式 ──────────────────────────────────────────────
echo ""
echo -e "${RED}  ✗ 未检测到 C/C++ 编译器${RESET}"
echo ""
echo -e "${CYAN}[2/3] 选择安装方式${RESET}"

select_option "请选择要安装的 C/C++ 编译工具链：" "MSVC (Visual Studio Build Tools)" "GNU gcc (MinGW-w64 / MSYS2)"

case "$SELECTED_OPTION" in
  1)
    install_msvc
    ;;
  2)
    install_gnu
    ;;
  0)
    echo ""
    echo -e "${YELLOW}  已退出，未安装任何 C/C++ 编译工具。${RESET}"
    exit 1
    ;;
esac

# ─── 步骤 3：安装后检查 as.exe ───────────────────────────────────────────────
echo ""
echo -e "${CYAN}[3/3] 检查 GNU 汇编器 as.exe${RESET}"
if ! check_as; then
  install_as
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  C/C++ 编译工具安装完成！${RESET}"
else
  echo -e "${YELLOW}  C/C++ 编译工具安装已完成，但部分步骤可能需要手动处理。${RESET}"
fi
