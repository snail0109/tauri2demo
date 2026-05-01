<#
.SYNOPSIS
  在 Windows 上检测并安装 Rust 工具链（rustup + stable toolchain），并根据 C/C++ 环境选择 GNU/MSVC ABI。
.DESCRIPTION
  - 先探测系统可用的 C/C++ 编译器（MSVC cl 或 GNU gcc），用于选择 Rust toolchain ABI
  - 若 rustup/toolchain 不可用，会尝试自动安装 rustup 并安装 stable-x86_64-pc-windows-(gnu|msvc)
  - 会写入 Rust 国内镜像（阿里云）以加速下载，并可配置 cargo crates.io 国内源
#>
$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

# ─── Rust 检测与安装函数 ─────────────────────────────────────────────────────

function Set-RustupChinaMirror {
  # 设置 Rust 国内镜像源环境变量（阿里云），加速 rustup 工具链下载和 self update。
  # 参考：https://developer.aliyun.com/mirror/rustup
  # 同时写入当前会话和用户级环境变量，确保新终端也生效。
  $env:RUSTUP_DIST_SERVER = 'https://mirrors.aliyun.com/rustup'
  $env:RUSTUP_UPDATE_ROOT = 'https://mirrors.aliyun.com/rustup/rustup'
  Set-UserEnvIfChanged -Name 'RUSTUP_DIST_SERVER' -Value $env:RUSTUP_DIST_SERVER
  Set-UserEnvIfChanged -Name 'RUSTUP_UPDATE_ROOT' -Value $env:RUSTUP_UPDATE_ROOT
  Write-Ok "已配置 Rust 国内镜像源（阿里云）"

  # 同时配置 cargo crates.io 国内源
  $cargoConfigDir = Join-Path $HOME '.cargo'
  $cargoConfigFile = Join-Path $cargoConfigDir 'config.toml'
  if (-not (Test-Path -LiteralPath $cargoConfigDir)) {
    New-Item -ItemType Directory -Force -Path $cargoConfigDir | Out-Null
  }
  if (-not (Test-Path -LiteralPath $cargoConfigFile)) {
    @'
[source.crates-io]
replace-with = 'aliyun'

[source.aliyun]
registry = "sparse+https://mirrors.aliyun.com/crates.io-index/"
'@ | Set-Content -LiteralPath $cargoConfigFile -Encoding UTF8
    Write-Ok "已配置 cargo crates.io 国内源（阿里云）"
  }
}

<#
.SYNOPSIS
  安装 rustup（Rust 工具链管理器）。
.OUTPUTS
  [bool]
.NOTES
  通过下载 rustup-init.exe 进行静默安装（默认 toolchain=none，后续步骤再安装具体 toolchain）。
#>
function Install-Rustup {
  if (Get-ExePath 'rustup.exe') { return $true }
  Write-Host ""
  Write-Host "═══ 安装 rustup ═══" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "准备下载安装介质 rustup-init.exe"
  $installer = Join-Path $env:TEMP 'rustup-init.exe'
  if (-not (Save-WebFile -Urls @(
    'https://mirrors.aliyun.com/rustup/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe',
    'https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe',
    'https://mirrors.ustc.edu.cn/rust-static/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
  ) -OutFile $installer)) {
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    Write-Fail "下载 rustup-init.exe 失败（已尝试国内镜像和官方地址）"
    Write-Fail "请手动访问 https://rustup.rs 安装"
    return $false
  }
  Write-Host ""
  Write-Host "通过 rustup-init 安装 rustup + rustc"
  Write-Host "  运行命令：`"$installer`" -y --default-toolchain none --no-modify-path" -ForegroundColor Cyan
  Invoke-NativeStream -Block {& $installer -y --default-toolchain none --no-modify-path }
  # Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue

  Add-CargoBinPath

  if (Get-ExePath 'rustup.exe') {
    $v = (Invoke-NativeText -FilePath 'rustup' -Arguments @('--version') | Select-Object -First 1)
    Write-Ok "rustup 安装成功：$v"
    return $true
  }

  Write-Fail "rustup 自动安装失败，请手动访问 https://rustup.rs 安装"
  return $false
}

<#
.SYNOPSIS
  安装指定 ABI 的 stable Windows Rust toolchain，并可选择设为默认。
.PARAMETER Abi
  msvc 或 gnu。
.OUTPUTS
  [bool]
.NOTES
  - 会调用 rustup toolchain install stable-x86_64-pc-windows-<abi>
  - 会尝试设置为 rustup default（可确认）
#>
function Install-RustToolchainAbi {
  param([ValidateSet('msvc', 'gnu')] [string]$Abi)

  $target = "x86_64-pc-windows-$Abi"
  $toolchain = "stable-$target"

  Write-Host ""
  Write-Host "Rust 工具链 $toolchain 准备安装"

  $list = Get-RustupToolchain
  $needInstall = ($list -notcontains $toolchain)
  if (-not $needInstall) {
    # 列表中有该 toolchain，但校验是否真的可用（可能残留损坏记录），静默检查避免重复日志
    $needInstall = -not (Test-RustToolchain -Quiet)
  }

  if ($needInstall) {
    Set-RustupChinaMirror
    Write-Host "  运行命令：rustup toolchain install $toolchain" -ForegroundColor Cyan
    Invoke-NativeStream -Block {& rustup toolchain install $toolchain }
    Write-Ok "Rust 工具链 $toolchain 安装成功"
  }

  $defaultLine = Invoke-NativeText -FilePath 'rustup' -Arguments @('default') | Select-Object -First 1
  $currentDefault = if ($defaultLine) { ($defaultLine -split '\s+')[0] } else { '' }
  if ($currentDefault -ne $toolchain) {
    Write-Host "  运行命令：rustup default $toolchain" -ForegroundColor Cyan
    Invoke-NativeStream -Block {& rustup default $toolchain }
  }

  return $true
}

# ─── 环境摘要 ─────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
  输出当前环境摘要（MSVC/GNU/Rust toolchain）。
.PARAMETER HasMsvc
  是否检测到 MSVC。
.PARAMETER HasGnu
  是否检测到 GNU gcc。
#>
function Write-EnvSummary {
  param([bool]$HasMsvc, [bool]$HasGnu)
  Write-StatusLine -Label 'MSVC             ' -Ok:$HasMsvc
  Write-StatusLine -Label 'Gnu GCC          ' -Ok:$HasGnu
  Write-StatusLine -Label 'Rust + Toolchain ' -Ok:(-not [string]::IsNullOrWhiteSpace($script:RustcHost))
}

# ─── 主流程 ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Banner -Title 'Rust 工具链检测与安装（Windows）    ' -Color Cyan
Write-Host ""

# [1/2] 检测 C/C++ 编译环境，判定 Rust ABI
Write-Host "[1/2] 检测 C/C++ 编译环境" -ForegroundColor Cyan

<#
.SYNOPSIS
  尝试定位 MSVC cl.exe 的绝对路径（包含 vswhere 回退）。
.OUTPUTS
  [string] cl.exe 的路径；未找到返回 $null。
.NOTES
  cl.exe 可能不在 PATH（例如仅安装了 Build Tools），因此需要通过 vswhere 定位安装目录。
#>
function Find-MsvcCl {
  # 优先用 PATH 直接定位（最快；若用户已运行过 vcvars64.bat 或已把工具链加入 PATH，则可命中）
  $cl = Get-ExePath 'cl.exe'
  if ($cl) { return $cl }

  # cl.exe 不在 PATH 时：通过 vswhere 定位 Visual Studio / Build Tools 安装根目录
  # vswhere.exe 通常随 VS Installer 安装，可能位于 ProgramFiles(x86) 或 ProgramFiles
  $vswhere = Get-ExePath 'vswhere.exe'
  if (-not $vswhere) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { # -LiteralPath 不做通配符解释，把字符串当作真实路径原样处理。
      $vswhere = Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
      if (-not (Test-Path -LiteralPath $vswhere)) { $vswhere = $null }
    }
  }

  # 用 vswhere 找“最新的、包含 VC Tools 组件”的安装（避免匹配到只装了 IDE 但没装 C++ 工具链的 VS）
  if ($vswhere) {
    Write-Host "  运行命令：`"$vswhere`" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath" -ForegroundColor Cyan
    $installPath = (Invoke-NativeText -FilePath $vswhere -Arguments @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath') | Select-Object -First 1)
    if ($installPath) {
      # VC 工具链实际存放目录：<VS>\VC\Tools\MSVC\<version>\bin\Hostx64\x64\cl.exe
      $msvcDir = Join-Path $installPath 'VC\Tools\MSVC'
      if (Test-Path -LiteralPath $msvcDir) {
        $cl = Get-ChildItem -LiteralPath $msvcDir -Recurse -Filter 'cl.exe' -ErrorAction SilentlyContinue |
        # 仅保留 x64 编译器（Hostx64\x64）；避免命中 x86/arm64 目录下的 cl.exe
        Where-Object { $_.Directory.Name -eq 'x64' } |
        # 多版本并存时按路径倒序取最新版本（通常目录名包含版本号）
        Sort-Object FullName -Descending |
        Select-Object -First 1
        if ($cl) { return $cl.FullName }
      }
    }
  }
  return $null
}

$msvcClPath = Find-MsvcCl
$hasMsvc = ($msvcClPath -ne $null)
$hasGnu = (Get-ExePath 'gcc.exe') -ne $null

if ($hasMsvc) { Write-Ok "检测到 MSVC（$msvcClPath）" }
if ($hasGnu) { Write-Ok "检测到 GNU GCC（gcc.exe）" }

if (-not $hasMsvc -and -not $hasGnu) {
  Write-Warn "未检测到 C/C++ 编译器，Rust 编译需要至少一种 C 链接器"
  Write-Warn "请先运行 install_c_compile_bywin.ps1 安装 C/C++ 编译工具，或手动安装后重试"
  Write-Host ""
  $abiOptions = @('GNU (x86_64-pc-windows-gnu)', 'MSVC (x86_64-pc-windows-msvc)')
  $abiChoice = Select-MenuOption -Prompt '仍要继续？请选择 Rust 工具链 ABI：' -Options $abiOptions
  if ($abiChoice -eq 0) {
    Exit-NoOp "已退出，未安装 Rust 工具链。" -Code 0
  }
  $selectedAbi = if ($abiChoice -eq 1) { 'gnu' } else { 'msvc' }
}
else {
  if ($hasGnu) { $selectedAbi = 'gnu' }
  else { $selectedAbi = 'msvc' }
}
Write-Host "  匹配Rust的工具链为 $selectedAbi (stable-x86_64-pc-windows-$selectedAbi)" -ForegroundColor DarkGray

# [2/2] 检测并安装 Rust 工具链
Write-Host ""
Write-Host "[2/2] 检查 Rust 工具链" -ForegroundColor Cyan
Add-CargoBinPath

# 一次性确保 rustup 可用，后续不再检测
if (-not (Get-ExePath 'rustup.exe')) {
  Write-Warn "未检测到 rustup，准备安装..."
  if (-not (Install-Rustup)) {
    Write-Fail "rustup 安装失败，请手动访问 https://rustup.rs 安装"
    exit 1
  }
}

Install-RustToolchainAbi -Abi $selectedAbi | Out-Null
Test-RustToolchain | Out-Null

# 将 ~\.cargo\bin 写入用户 PATH，使新终端也能直接使用 rustup、rustc、cargo
$cargoBin = Join-Path $HOME '.cargo\bin'
if (Test-Path -LiteralPath $cargoBin) {
  Add-UserPathSegment $cargoBin | Out-Null
  Write-Ok "已将 ~\.cargo\bin 加入用户 PATH（新终端窗口生效）"
}

# 环境摘要
Write-Host ""
Write-Host "环境摘要" -ForegroundColor Cyan
Write-EnvSummary -HasMsvc $hasMsvc -HasGnu $hasGnu
Write-Host ""
if (-not $Failed) {
  Write-Host "  Rust 工具链安装完成！" -ForegroundColor Green
}
else {
  Write-Host "  安装已完成，但部分步骤可能需要手动处理。" -ForegroundColor Yellow
}
