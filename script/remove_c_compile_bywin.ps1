param(
  [Alias('y')]
  [switch]$Yes,

  [Alias('WhatIf')]
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

function Remove-RustToolchainAbi {
  param([ValidateSet('msvc', 'gnu')] [string]$Abi)

  $toolchain = "stable-x86_64-pc-windows-$Abi"
  if (-not (Get-ExePath 'rustup.exe')) {
    Write-Warn "未检测到 rustup，跳过 Rust 工具链卸载"
    return
  }
  $list = Get-RustupToolchain
  if ($list -notcontains $toolchain) {
    Write-Warn "Rust 工具链 $toolchain 未安装，跳过"
    return
  }
  if (-not (Confirm-Remove "卸载 Rust 工具链 $toolchain")) {
    Write-Warn "已跳过 $toolchain"
    return
  }
  if ($DryRun) { Write-Warn "DryRun: rustup toolchain uninstall $toolchain"; return }
  Invoke-NativeStream -Block { & rustup toolchain uninstall $toolchain }
  if ($LASTEXITCODE -eq 0) { Write-Ok "已卸载 $toolchain" } else { Write-Fail "rustup toolchain uninstall $toolchain 失败" }
}

function Remove-AllRustToolchain {
  if (-not (Get-ExePath 'rustup.exe')) { return }
  $toolchains = Get-RustupToolchain
  if ($toolchains.Count -eq 0) { return }
  if (-not (Confirm-Remove "卸载所有 Rust 工具链（共 $($toolchains.Count) 个）")) { return }
  foreach ($tc in $toolchains) {
    if ($DryRun) { Write-Warn "DryRun: rustup toolchain uninstall $tc"; continue }
    Invoke-NativeStream -Block { & rustup toolchain uninstall $tc }
    if ($LASTEXITCODE -eq 0) { Write-Ok "已卸载 $tc" } else { Write-Fail "卸载 $tc 失败" }
  }
}

function Remove-Rustup {
  if (-not (Get-ExePath 'rustup.exe')) {
    Write-Warn "未检测到 rustup"
    return
  }
  if (-not (Confirm-Remove "完全卸载 rustup（移除所有 Rust 工具链、~\.cargo、~\.rustup）")) { return }
  if ($DryRun) { Write-Warn "DryRun: rustup self uninstall -y"; return }
  Invoke-NativeStream -Block { & rustup self uninstall -y }
  if (Get-ExePath 'rustup.exe') { Write-Fail "rustup self uninstall 后仍能找到 rustup，可能需要重启 shell 或手动清理" }
  else { Write-Ok "rustup 已卸载" }
}

function Remove-Msys2 {
  $msysRoot = 'C:\msys64'
  if (-not (Test-Path -LiteralPath $msysRoot)) {
    Write-Warn "未检测到 MSYS2 安装目录 C:\msys64"
    return
  }
  Write-Warn "卸载 MSYS2 将删除整个 C:\msys64 目录及所有已装包（含其他工具）"
  if (-not (Confirm-Remove "继续卸载整个 MSYS2")) { return }

  if ($DryRun) { Write-Warn "DryRun: winget uninstall MSYS2.MSYS2"; return }
  if (Get-ExePath 'winget.exe') {
    Invoke-NativeStream -Block { & winget uninstall MSYS2.MSYS2 --silent }
  }
  Start-Sleep -Seconds 2
  if (Test-Path -LiteralPath $msysRoot) {
    Write-Warn "winget 卸载后 C:\msys64 仍存在。请关闭所有 MSYS2 / Git Bash 终端，"
    Write-Warn "然后在 PowerShell（管理员）中手动删除："
    Write-Warn "  Remove-Item -Recurse -Force C:\msys64"
    Write-Fail "MSYS2 未完全卸载（目录仍存在）"
  } else {
    Write-Ok "MSYS2 已完全卸载"
  }
}

function Remove-Msvc {
  if (-not (Get-ExePath 'winget.exe') -and -not (Get-ExePath 'cl.exe')) {
    Write-Warn "未检测到 MSVC 或 winget，跳过"
    return
  }
  Write-Warn "卸载 MSVC 将影响所有依赖 Visual Studio Build Tools 的项目"
  if (-not (Confirm-Remove "卸载 Visual Studio Build Tools (2022 / 2019)")) { return }

  if ($DryRun) { Write-Warn "DryRun: winget uninstall Microsoft.VisualStudio.2022.BuildTools / 2019.BuildTools"; return }

  if (-not (Get-ExePath 'winget.exe')) {
    Write-Warn "winget 不可用，请手动通过「Visual Studio Installer」卸载"
    return
  }

  $removed = $false
  foreach ($id in @('Microsoft.VisualStudio.2022.BuildTools', 'Microsoft.VisualStudio.2019.BuildTools')) {
    Invoke-NativeStream -Block { & winget uninstall $id --silent }
    if ($LASTEXITCODE -eq 0) { Write-Ok "已请求卸载 $id"; $removed = $true }
  }
  if (-not $removed) {
    Write-Warn "winget 未匹配到已安装的 Visual Studio Build Tools"
    Write-Warn "请通过「Visual Studio Installer」GUI 手动卸载"
  }
}

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Red
Write-Host "  C/C++ 编译工具卸载（Windows）          " -ForegroundColor Red
Write-Host "══════════════════════════════════════════" -ForegroundColor Red
Write-Host ""
Write-Warn "本脚本会卸载系统级开发工具，可能影响其它项目。请确认你了解每一步。"
Write-Host ""

$selected = Select-MenuOption -Prompt '请选择要卸载的内容：' -Options @(
  'Rust(gnu) + MinGW gcc + rustup + MSYS2',
  'Rust(msvc) + MSVC + rustup + MSYS2',
  '全部卸载（rustup + MSYS2 + MSVC）'
)

switch ($selected) {
  1 {
    Enable-AutoConfirm
    Remove-RustToolchainAbi -Abi 'gnu'
    Remove-Rustup
    Remove-Msys2
  }
  2 {
    Enable-AutoConfirm
    Remove-RustToolchainAbi -Abi 'msvc'
    Remove-Msvc
    Remove-Rustup
    Remove-Msys2
  }
  3 {
    Write-Warn "即将依次卸载：所有 Rust 工具链 → rustup → MSYS2 → MSVC"
    if (-not (Confirm-Remove "确认执行全部卸载（请慎重）")) {
      Write-Host ""
      Write-Host "  已退出，未卸载任何内容。" -ForegroundColor Yellow
      exit 0
    }
    Enable-AutoConfirm
    Remove-AllRustToolchain
    Remove-Rustup
    Remove-Msys2
    Remove-Msvc
  }
  0 {
    Write-Host ""
    Write-Host "  已退出，未卸载任何内容。" -ForegroundColor Yellow
    exit 0
  }
}

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  卸载结束摘要                            " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

$hasMsvc = $null -ne (Get-ExePath 'cl.exe')
$hasGcc = $null -ne (Get-ExePath 'gcc.exe')
$hasRustup = $null -ne (Get-ExePath 'rustup.exe')
$hasMsys2 = Test-Path -LiteralPath 'C:\msys64'

Write-StatusLine -Label 'MSVC      ' -Ok:(-not $hasMsvc) -OkText '已移除' -NotOkText '仍存在'
Write-StatusLine -Label 'GNU GCC   ' -Ok:(-not $hasGcc) -OkText '已移除' -NotOkText '仍存在'
Write-StatusLine -Label 'rustup    ' -Ok:(-not $hasRustup) -OkText '已移除' -NotOkText '仍存在'
Write-StatusLine -Label 'MSYS2     ' -Ok:(-not $hasMsys2) -OkText '已移除' -NotOkText '仍存在'

Write-Host ""
if (-not $Failed) { Write-Host "  卸载完成！" -ForegroundColor Green }
else { Write-Host "  卸载流程已结束，但部分步骤失败或未完成，请查看上方日志手动处理。" -ForegroundColor Yellow }
