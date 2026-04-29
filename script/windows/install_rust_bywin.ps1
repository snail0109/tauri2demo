param(
  [Alias('y')]
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

# ─── Rust 检测与安装函数 ─────────────────────────────────────────────────────

function Set-RustupChinaMirror {
  # 设置 Rust 国内镜像源环境变量（阿里云），加速 rustup 工具链下载和 self update。
  # 参考：https://developer.aliyun.com/mirror/rustup
  $env:RUSTUP_DIST_SERVER = 'https://mirrors.aliyun.com/rustup'
  $env:RUSTUP_UPDATE_ROOT = 'https://mirrors.aliyun.com/rustup/rustup'
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

function Test-RustToolchain {
  param([switch]$Quiet)
  $rustc = Get-ExePath 'rustc.exe'
  if (-not $rustc) {
    Add-CargoBinPath
    $rustc = Get-ExePath 'rustc.exe'
  }


  if (-not $rustc) { return $false }
  $versionOutput = Invoke-NativeText -FilePath 'rustc' -Arguments @('--version')
  $script:RustcVersion = ($versionOutput | Select-Object -First 1)
  # 校验输出版本号格式（如 "rustc 1.85.0 (...)"），排除 error/warning 等异常输出
  if ([string]::IsNullOrWhiteSpace($script:RustcVersion) -or $script:RustcVersion -notmatch '^rustc \d+\.\d+\.\d+') {
    if (-not $Quiet) { Write-Warn "rustc 已找到但输出异常（toolchain 可能不完整）：$script:RustcVersion" }
    $script:RustcVersion = $null
    $script:RustcHost = $null
    return $false
  }
  $hostLine = Invoke-NativeText -FilePath 'rustc' -Arguments @('-vV') |
  Where-Object { $_ -match '^host:\s*' } |
  Select-Object -First 1
  if ($hostLine) { $script:RustcHost = ($hostLine -replace '^host:\s*', '').Trim() }
  if (-not $Quiet) {
    Write-Ok "Rust 工具链已安装"
    if (-not [string]::IsNullOrWhiteSpace($script:RustcHost)) { Write-Host "    host：$($script:RustcHost)" }
    if (-not [string]::IsNullOrWhiteSpace($script:RustcVersion)) { Write-Host "    版本：$($script:RustcVersion)" }
  }
  return $true
}

function Install-Rustup {
  if (Get-ExePath 'rustup.exe') { return $true }
  Write-Host ""
  Write-Host "═══ 安装 rustup ═══" -ForegroundColor Cyan
  if (-not (Confirm-Install "安装 rustup（Rust 工具链管理器）")) {
    Write-Warn "已跳过 rustup 安装"
    return $false
  }

  # 设置国内镜像环境变量，供后续 rustup 命令和 toolchain 安装使用
  Set-RustupChinaMirror

  $verifyInstalled = {
    Add-CargoBinPath
    if (-not (Get-ExePath 'rustup.exe')) { return $false }
    $v = (Invoke-NativeText -FilePath 'rustup' -Arguments @('--version') | Select-Object -First 1)
    Write-Ok "rustup 安装成功：$v"
    return $true
  }

  $installer = Join-Path $env:TEMP 'rustup-init.exe'
  # 优先从国内镜像下载 rustup-init.exe，失败再回退到官方地址
  $downloadUrls = @(
    'https://mirrors.aliyun.com/rustup/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe',
    'https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe',
    'https://mirrors.ustc.edu.cn/rust-static/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
  )
  $downloaded = $false
  foreach ($url in $downloadUrls) {
    if (Save-WebFile -Urls @($url) -OutFile $installer) {
      $downloaded = $true
      break
    }
    Write-Warn "下载失败，尝试下一个源..."
  }
  if (-not $downloaded) {
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    Write-Fail "下载 rustup-init.exe 失败（已尝试国内镜像和官方地址）"
    Write-Fail "请手动访问 https://rustup.rs 安装"
    return $false
  }
  Write-Ok "启动 rustup-init（使用国内镜像，默认 toolchain=none，由本脚本后续配置）..."
  try {
    Start-Process -FilePath $installer -ArgumentList @('-y', '--default-toolchain', 'none', '--no-modify-path') -Wait -NoNewWindow | Out-Null
  }
  catch {}
  Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue

  if (& $verifyInstalled) { return $true }

  Write-Fail "rustup 自动安装失败，请手动访问 https://rustup.rs 安装"
  return $false
}

function Install-RustToolchainAbi {
  param([ValidateSet('msvc', 'gnu')] [string]$Abi)

  $target = "x86_64-pc-windows-$Abi"
  $toolchain = "stable-$target"

  if (-not (Get-ExePath 'rustup.exe')) {
    if (-not (Install-Rustup)) { return $false }
  }

  $list = Get-RustupToolchain
  $needInstall = ($list -notcontains $toolchain)
  if (-not $needInstall) {
    # 列表中有该 toolchain，但校验是否真的可用（可能残留损坏记录），静默检查避免重复日志
    $needInstall = -not (Test-RustToolchain -Quiet)
  }
  if ($needInstall) {
    if (-not (Confirm-Install "通过 rustup 安装 $toolchain 工具链")) {
      Write-Warn "已跳过 Rust $toolchain 工具链安装"
      return $false
    }
    Set-RustupChinaMirror
    Invoke-NativeStream -Block { & rustup toolchain install $toolchain }
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "rustup toolchain install $toolchain 失败"
      return $false
    }
    Write-Ok "Rust 工具链 $toolchain 安装成功"
  }

  $defaultLine = Invoke-NativeText -FilePath 'rustup' -Arguments @('default') | Select-Object -First 1
  $currentDefault = if ($defaultLine) { ($defaultLine -split '\s+')[0] } else { '' }
  if ($currentDefault -ne $toolchain) {
    $currentLabel = if ([string]::IsNullOrWhiteSpace($currentDefault)) { '未设置' } else { $currentDefault }
    if (Confirm-Install "将 $toolchain 设为默认 Rust 工具链（当前：$currentLabel）") {
      Invoke-NativeStream -Block { & rustup default $toolchain }
      if ($LASTEXITCODE -ne 0) { Write-Warn "设置默认工具链失败" }
    }
  }

  Test-RustToolchain -Quiet | Out-Null
  Write-Host ""
  Write-Banner -Title 'Rust 工具链已就绪' -Color Green
  return $true
}

# ─── 环境摘要 ─────────────────────────────────────────────────────────────────

function Write-EnvSummary {
  param([bool]$HasMsvc, [bool]$HasGnu)
  Write-StatusLine -Label 'MSVC      ' -Ok:$HasMsvc
  Write-StatusLine -Label 'GNU GCC   ' -Ok:$HasGnu
  Write-StatusLine -Label 'Rust      ' -Ok:(-not [string]::IsNullOrWhiteSpace($script:RustcHost))
}

# ─── 主流程 ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Banner -Title 'Rust 工具链检测与安装（Windows）    ' -Color Cyan
Write-Host ""

# [1/2] 检测 C/C++ 编译环境，判定 Rust ABI
Write-Host "[1/2] 检测 C/C++ 编译环境" -ForegroundColor Cyan

function Find-MsvcCl {
  $cl = Get-ExePath 'cl.exe'
  if ($cl) { return $cl }
  # cl.exe 不在 PATH 中时，用 vswhere 定位 VS 安装
  $vswhere = Get-ExePath 'vswhere.exe'
  if (-not $vswhere) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
      $vswhere = Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
      if (-not (Test-Path -LiteralPath $vswhere)) { $vswhere = $null }
    }
  }
  if ($vswhere) {
    $installPath = (Invoke-NativeText -FilePath $vswhere -Arguments @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath') | Select-Object -First 1)
    if ($installPath) {
      $msvcDir = Join-Path $installPath 'VC\Tools\MSVC'
      if (Test-Path -LiteralPath $msvcDir) {
        $cl = Get-ChildItem -LiteralPath $msvcDir -Recurse -Filter 'cl.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'x64' } |
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
  if ($Yes) {
    Write-Warn "-y 模式下默认选择 GNU ABI（x86_64-pc-windows-gnu）"
    $selectedAbi = 'gnu'
  }
  else {
    Write-Host ""
    $abiOptions = @('GNU (x86_64-pc-windows-gnu)', 'MSVC (x86_64-pc-windows-msvc)')
    $abiChoice = Select-MenuOption -Prompt '仍要继续？请选择 Rust 工具链 ABI：' -Options $abiOptions
    if ($abiChoice -eq 0) {
      Exit-NoOp "已退出，未安装 Rust 工具链。" -Code 0
    }
    $selectedAbi = if ($abiChoice -eq 1) { 'gnu' } else { 'msvc' }
  }
}
else {
  if ($hasGnu) { $selectedAbi = 'gnu' }
  else { $selectedAbi = 'msvc' }
}
Write-Host "  → 选择 Rust ABI：$selectedAbi (stable-x86_64-pc-windows-$selectedAbi)" -ForegroundColor DarkGray

# [2/2] 检测并安装 Rust 工具链
Write-Host ""
Write-Host "[2/2] 检查 Rust 工具链" -ForegroundColor Cyan
Add-CargoBinPath
$rustupExisted = (Get-ExePath 'rustup.exe') -ne $null
if (-not (Test-RustToolchain)) {
  if ($rustupExisted) {
    Write-Warn "rustup 已安装但 Rust 工具链不可用，将重新安装"
    Enable-AutoConfirm
  }
  else {
    Write-Warn "未检测到 rustup"
    Enable-AutoConfirm
    Install-Rustup | Out-Null
  }
}

if (Get-ExePath 'rustup.exe') {
  Install-RustToolchainAbi -Abi $selectedAbi | Out-Null
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
