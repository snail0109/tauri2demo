#!/usr/bin/env bash
# install_c_compile_bywin.sh — Windows (MSYS2) Rust 编译依赖工具链安装脚本
# 功能：
#   1. 检查是否已安装 C/C++ 编译器（MSVC / GNU gcc）及 Rust 工具链
#   2. 如果已安装，验证 Rust 工具链与 C 编译器 ABI 匹配后显示摘要退出
#   3. 如果未安装，让用户在以下两套组合中选择：
#        • MSVC + Rust (stable-x86_64-pc-windows-msvc)
#        • GNU gcc + Rust (stable-x86_64-pc-windows-gnu)
#
# 运行环境假设：MSYS2 mingw64 shell（pacman、bash 均在 PATH 中）。
# 不再针对 Git Bash 做兼容；如需在 Git Bash 下使用，请改用 MSYS2。

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
    ok "MSVC cl.exe 已安装"
    echo -e "    路径：${MSVC_PATH}"
    echo -e "    版本：${CL_INFO}"
    return 0
  fi
  return 1
}

# ─── 检查 GNU gcc ────────────────────────────────────────────────────────────
check_gnu() {
  FOUND=0

  # 若 gcc 不在 PATH 中，先尝试探测 MSYS2 标准安装路径并将其加入 PATH，
  # 避免出现「PATH 中没有 gcc → 报未安装 → 进入安装流程后又发现已安装」的冲突。
  echo "    检测 MSYS2 安装路径： /c/msys64"
  MSYS2_MINGW_BIN="/c/msys64/mingw64/bin"
  if ! command -v gcc &>/dev/null && [[ -f "${MSYS2_MINGW_BIN}/gcc.exe" ]]; then
    export PATH="${MSYS2_MINGW_BIN}:${PATH}"
  fi

  if command -v gcc &>/dev/null && gcc --version &>/dev/null; then
    GCC_INFO=$(gcc --version 2>&1 | head -1)
    ok "GNU GCC 编译器已安装"
    echo -e "    路径：$(which gcc)"
    echo -e "    版本：${GCC_INFO}"
    FOUND=1

    if ! command -v g++ &>/dev/null || ! g++ --version &>/dev/null; then
      warn "GCC 已找到但 G++ 未找到，部分 C++ 依赖可能编译失败"
    fi
  fi

  if [[ "$FOUND" -eq 1 ]]; then
    return 0
  fi
  return 1
}

# ─── 检查 Rust 工具链 ───────────────────────────────────────────────────────
RUSTC_VERSION=""
RUSTC_HOST=""
check_rust() {
  # 若 rustc 不在 PATH 中，探测 cargo 的标准安装位置（rustup 默认装到 ~/.cargo/bin）
  # 适配 Windows 用户 PATH 已更新但当前 shell 未刷新的场景。
  echo "    检测 Rust 安装路径： $HOME/.cargo/bin"
  if ! command -v rustc &>/dev/null && [[ -f "$HOME/.cargo/bin/rustc.exe" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi

  if ! command -v rustc &>/dev/null; then
    return 1
  fi
  RUSTC_VERSION=$(rustc --version 2>&1 | head -1)
  RUSTC_HOST=$(rustc -vV 2>/dev/null | awk -F': ' '/^host:/{print $2}' | tr -d '\r ')
  ok "Rust 工具链已安装"
  echo -e "    host：${RUSTC_HOST}"
  echo -e "    版本：${RUSTC_VERSION}}"
  return 0
}

# ─── 安装 rustup（Rust 工具链管理器） ───────────────────────────────────────
install_rustup() {
  if command -v rustup &>/dev/null; then
    return 0
  fi

  echo ""
  echo -e "${CYAN}═══ 安装 rustup ═══${RESET}"

  if ! confirm_install "安装 rustup（Rust 工具链管理器）"; then
    warn "已跳过 rustup 安装"
    return 1
  fi

  # ── 优先尝试 winget ──
  if command -v winget &>/dev/null; then
    echo -e "${CYAN}  尝试通过 winget 安装 Rustlang.Rustup ...${RESET}"
    winget install --id Rustlang.Rustup --accept-package-agreements --accept-source-agreements --silent 2>&1 || true
    # 把 cargo bin 加入 PATH
    if [[ -d "$HOME/.cargo/bin" ]]; then
      export PATH="$HOME/.cargo/bin:$PATH"
    fi
    if command -v rustup &>/dev/null; then
      ok "rustup 安装成功：$(rustup --version 2>&1 | head -1)"
      return 0
    fi
    warn "winget 未生效或未找到 rustup,改用 rustup-init.exe ..."
  fi

  # ── 回退：下载 rustup-init.exe 静默安装 ──
  local installer
  installer=$(mktemp /tmp/rustup_init_XXXXXX.exe)
  echo -e "${CYAN}  正在下载 rustup-init.exe ...${RESET}"
  if ! curl -fSL -o "$installer" "https://win.rustup.rs/x86_64" 2>/dev/null; then
    rm -f "$installer"
    fail "下载 rustup-init.exe 失败"
    fail "请手动访问 https://rustup.rs 安装"
    return 1
  fi
  ok "下载完成，启动 rustup-init（默认 toolchain=none，由本脚本后续配置）..."
  "$installer" -y --default-toolchain none --no-modify-path 2>&1 || true
  rm -f "$installer"

  if [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi

  if command -v rustup &>/dev/null; then
    ok "rustup 安装成功：$(rustup --version 2>&1 | head -1)"
    return 0
  fi

  fail "rustup 自动安装失败，请手动访问 https://rustup.rs 安装"
  return 1
}

# ─── 确保对应 ABI 的 Rust 工具链已安装并设为默认 ─────────────────────────────
# 参数：msvc | gnu
ensure_rust_toolchain() {
  local abi="$1"
  local target="x86_64-pc-windows-${abi}"
  local toolchain="stable-${target}"

  if ! command -v rustup &>/dev/null; then
    if ! install_rustup; then
      return 1
    fi
  fi

  if rustup toolchain list 2>/dev/null | grep -q "^${toolchain}"; then
  else
    if confirm_install "通过 rustup 安装 ${toolchain} 工具链"; then
      if rustup toolchain install "${toolchain}" 2>&1; then
        ok "Rust 工具链 ${toolchain} 安装成功"
      else
        fail "rustup toolchain install ${toolchain} 失败"
        return 1
      fi
    else
      warn "已跳过 Rust ${toolchain} 工具链安装"
      return 1
    fi
  fi

  local current_default
  current_default=$(rustup default 2>/dev/null | awk '{print $1}')
  if [[ "$current_default" != "${toolchain}" ]]; then
    if confirm_install "将 ${toolchain} 设为默认 Rust 工具链（当前：${current_default:-未设置}）"; then
      rustup default "${toolchain}" 2>&1 || warn "设置默认工具链失败"
    fi
  fi

  # 刷新缓存的 host 信息
  check_rust >/dev/null 2>&1 || true

  echo ""
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"
  echo -e "${GREEN}  Rust 工具链已就绪${RESET}"
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"
  return 0
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
      "$installer_path" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait 2>&1 || true
      rm -f "$installer_path"

      echo ""
      echo -e "${CYAN}  重新检查 MSVC ...${RESET}"
      if check_msvc; then
        ok "MSVC 安装成功！"
      else
        warn "MSVC 安装器已运行，但当前 shell 未检测到 cl.exe"
        warn "请重新打开终端后再次运行此脚本验证"
      fi
      ensure_rust_toolchain msvc || true
      return 0
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

  MSYS2_MINGW_BIN="/c/msys64/mingw64/bin"

  # ── 情况 1：MSYS2 已安装 → 直接用 pacman 安装 gcc ──
  if [[ -d "/c/msys64" ]]; then
    ok "检测到 MSYS2 已安装在 C:\\msys64"

    # 检查 gcc 是否已经存在于 MSYS2 目录中（只是不在 PATH 中）
    if [[ -f "${MSYS2_MINGW_BIN}/gcc.exe" ]]; then
      export PATH="${MSYS2_MINGW_BIN}:${PATH}"
      ok "gcc 已存在于 ${MSYS2_MINGW_BIN}，已添加到 PATH"
      if check_gnu; then
        ok "GNU gcc 安装验证通过！"
      fi
      ensure_rust_toolchain gnu || true
      return 0
    fi

    # gcc 不存在，通过 pacman 安装
    if confirm_install "通过 MSYS2 pacman 安装 mingw-w64-x86_64-gcc"; then
      pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils 2>&1
      if [[ -f "${MSYS2_MINGW_BIN}/gcc.exe" ]]; then
        export PATH="${MSYS2_MINGW_BIN}:${PATH}"
        ok "mingw-w64-x86_64-gcc 安装成功"
        if check_gnu; then
          ok "GNU gcc 安装验证通过！"
        fi
        ensure_rust_toolchain gnu || true
        return 0
      else
        warn "pacman 安装完成但未找到 gcc.exe，可能需要更新 MSYS2："
        warn "  pacman -Syu --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-gcc"
      fi
    fi

  # ── 情况 2：MSYS2 未安装 → 先安装 MSYS2 再装 gcc ──
  else
    if command -v winget &>/dev/null; then
      if confirm_install "通过 winget 安装 MSYS2，然后安装 mingw-w64-x86_64-gcc"; then
        winget install MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements 2>&1
        if [[ -d "/c/msys64" ]]; then
          # 初始化 MSYS2 并安装 gcc + binutils
          /c/msys64/usr/bin/bash.exe -lc "pacman-key --init && pacman-key --populate msys2 && pacman -Sy --noconfirm archlinux-msys2-keyring && pacman -Su --noconfirm && pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils" 2>&1
          if [[ -f "${MSYS2_MINGW_BIN}/gcc.exe" ]]; then
            export PATH="${MSYS2_MINGW_BIN}:${PATH}"
            ok "MSYS2 + mingw-w64-gcc 安装成功"
            if check_gnu; then
              ok "GNU gcc 安装验证通过！"
            fi
            ensure_rust_toolchain gnu || true
            return 0
          else
            warn "MSYS2 已安装但 gcc 安装可能不完整，请手动执行："
            warn "  /c/msys64/usr/bin/bash.exe -lc 'pacman -S --noconfirm mingw-w64-x86_64-gcc'"
          fi
        else
          warn "winget 安装 MSYS2 后未在 C:\\msys64 找到安装目录"
        fi
      fi
    else
      warn "winget 未找到，无法自动安装 MSYS2"
    fi
  fi

  # 所有自动安装方式都失败
  fail "GNU gcc 自动安装失败或被跳过"
  fail "请手动安装以下工具链："
  fail "  • MSYS2: https://www.msys2.org/ 安装后运行 pacman -S mingw-w64-x86_64-gcc"
  fail "  • MinGW-w64: https://www.mingw-w64.org/"
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
      pacman -S --noconfirm --needed mingw-w64-x86_64-binutils 2>&1
      if [[ -f "${MSYS2_MINGW_BIN}/as.exe" ]]; then
        export PATH="${MSYS2_MINGW_BIN}:${PATH}"
        ok "mingw-w64-x86_64-binutils 安装成功，as.exe 已添加到 PATH"
        return 0
      else
        warn "pacman 安装完成但未找到 as.exe，可能需要更新 MSYS2："
        warn "  pacman -Syu --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-binutils"
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
echo -e "${CYAN}[1/4] 检查 C/C++ 编译器${RESET}"

HAS_MSVC=0
HAS_GNU=0

if check_msvc; then
  HAS_MSVC=1
  FOUND_CC=1
fi

if check_gnu; then
  HAS_GNU=1
  FOUND_CC=1
fi

# ─── 已安装：检查 Rust 工具链匹配并显示摘要 ──────────────────────────────────
if [[ "$FOUND_CC" -eq 1 ]]; then
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"
  echo -e "${GREEN}  C/C++ 编译工具已就绪${RESET}"
  echo -e "${GREEN}══════════════════════════════════════════${RESET}"

  # ─── 步骤 2：检查 Rust 工具链（与已检测到的 C 编译器配套） ────────────────
  echo ""
  echo -e "${CYAN}[2/4] 检查 Rust 工具链${RESET}"
  if ! check_rust; then
    warn "未检测到 rustc/rustup"
    if install_rustup; then
      check_rust >/dev/null 2>&1 || true
    fi
  fi
  # 当只有一种 C 编译器时，确保对应 ABI 的 Rust 工具链可用
  if command -v rustup &>/dev/null; then
    if [[ "$HAS_MSVC" -eq 1 && "$HAS_GNU" -eq 0 ]]; then
      ensure_rust_toolchain msvc || true
    elif [[ "$HAS_GNU" -eq 1 && "$HAS_MSVC" -eq 0 ]]; then
      ensure_rust_toolchain gnu || true
    fi
  fi

  # ─── 步骤 3：检查 as.exe ──────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}[3/4] 检查 GNU 汇编器 as.exe${RESET}"
  if ! check_as; then
    install_as
  fi

  # ─── 步骤 4：显示环境摘要 ──────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}[4/4] 环境摘要${RESET}"
  echo -e "  MSVC      ：$([ "$HAS_MSVC" -eq 1 ] && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
  echo -e "  GNU GCC   ：$([ "$HAS_GNU" -eq 1 ] && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
  if [[ -n "$RUSTC_HOST" ]]; then
    echo -e "  Rust      ：${GREEN}已安装${RESET}"
  else
    echo -e "  Rust      ：${YELLOW}未安装${RESET}"
  fi

  echo ""
  echo -e "${GREEN}  检查完成，C/C++ 编译工具可用。${RESET}"
  exit 0
fi

# ─── 未安装：让用户选择安装方式 ──────────────────────────────────────────────
echo ""
echo -e "${RED}  ✗ 未检测到 C/C++ 编译器${RESET}"
echo ""
echo -e "${CYAN}[2/4] 选择安装方式${RESET}"

select_option "请选择要安装的工具链组合：" \
  "MSVC + Rust 工具链 (Visual Studio Build Tools + stable-x86_64-pc-windows-msvc)" \
  "GNU  + Rust 工具链 (MinGW-w64 / MSYS2 + stable-x86_64-pc-windows-gnu)"

case "$SELECTED_OPTION" in
  1)
    install_msvc
    ;;
  2)
    install_gnu
    ;;
  0)
    echo ""
    echo -e "${YELLOW}  已退出，未安装任何工具链。${RESET}"
    exit 1
    ;;
esac

# ─── 步骤 3：安装后检查 as.exe ───────────────────────────────────────────────
echo ""
echo -e "${CYAN}[3/4] 检查 GNU 汇编器 as.exe${RESET}"
if ! check_as; then
  install_as
fi

# ─── 步骤 4：安装后摘要 ──────────────────────────────────────────────────────
check_rust >/dev/null 2>&1 || true
echo ""
echo -e "${CYAN}[4/4] 环境摘要${RESET}"
echo -e "  MSVC      ：$(check_msvc >/dev/null 2>&1 && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
echo -e "  GNU GCC   ：$(command -v gcc >/dev/null 2>&1 && echo -e "${GREEN}已安装${RESET}" || echo -e "${YELLOW}未安装${RESET}")"
if [[ -n "$RUSTC_HOST" ]]; then
  echo -e "  Rust      ：${GREEN}已安装${RESET}"
else
  echo -e "  Rust      ：${YELLOW}未安装${RESET}"
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}  工具链安装完成！${RESET}"
else
  echo -e "${YELLOW}  工具链安装已完成，但部分步骤可能需要手动处理。${RESET}"
fi
