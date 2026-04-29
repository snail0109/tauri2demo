param(
  [Alias('y')]
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

# ─── Rust 卸载函数 ────────────────────────────────────────────────────────────

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
  Invoke-NativeStream -Block { & rustup toolchain uninstall $toolchain }
  if ($LASTEXITCODE -eq 0) { Write-Ok "已卸载 $toolchain" } else { Write-Fail "rustup toolchain uninstall $toolchain 失败" }
}

function Remove-AllRustToolchain {
  if (-not (Get-ExePath 'rustup.exe')) { return }
  $toolchains = Get-RustupToolchain
  if ($toolchains.Count -eq 0) { return }
  if (-not (Confirm-Remove "卸载所有 Rust 工具链（共 $($toolchains.Count) 个）")) { return }
  foreach ($tc in $toolchains) {
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
  Write-Warn "请确保已关闭其他可能使用 Rust 的终端窗口"
  Invoke-NativeStream -Block { & rustup self uninstall -y }
  if (Get-ExePath 'rustup.exe') {
    Write-Fail "rustup self uninstall 未能完全清理（可能被进程占用）"
    Write-Fail "请关闭所有终端后手动删除："
    Write-Fail "  Remove-Item -Recurse -Force ~\.cargo"
    Write-Fail "  Remove-Item -Recurse -Force ~\.rustup"
  }
  else { Write-Ok "rustup 已卸载" }
}

# ─── 主流程 ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Banner -Title 'Rust 工具链卸载（Windows）           ' -Color Red
Write-Host ""
Write-Warn "本脚本会卸载 Rust 开发工具，可能影响其它 Rust 项目。请确认你了解每一步。"
Write-Host ""

$selected = Select-MenuOption -Prompt '请选择要卸载的内容：' -Options @(
  '卸载 stable-x86_64-pc-windows-gnu 工具链',
  '卸载 stable-x86_64-pc-windows-msvc 工具链',
  '卸载所有 Rust 工具链',
  '完全卸载 rustup（移除所有工具链 + ~\.cargo + ~\.rustup）'
)

switch ($selected) {
  1 {
    Enable-AutoConfirm
    Remove-RustToolchainAbi -Abi 'gnu'
  }
  2 {
    Enable-AutoConfirm
    Remove-RustToolchainAbi -Abi 'msvc'
  }
  3 {
    Enable-AutoConfirm
    Remove-AllRustToolchain
  }
  4 {
    Write-Warn "即将卸载：所有 Rust 工具链 → rustup"
    if (-not (Confirm-Remove "确认执行完全卸载（请慎重）")) {
      Exit-NoOp "已退出，未卸载任何内容。"
    }
    Enable-AutoConfirm
    Remove-AllRustToolchain
    Remove-Rustup
  }
  0 {
    Exit-NoOp "已退出，未卸载任何内容。"
  }
}

Write-Host ""
Write-Banner -Title '卸载结束摘要                            ' -Color Cyan

$hasRustup = $null -ne (Get-ExePath 'rustup.exe')
Add-CargoBinPath
$hasRustc = $null -ne (Get-ExePath 'rustc.exe')
$toolchains = Get-RustupToolchain

Write-RemovedStatus -Label 'rustup    ' -NotPresent (-not $hasRustup)
Write-RemovedStatus -Label 'rustc     ' -NotPresent (-not $hasRustc)
if ($hasRustup -and $toolchains.Count -gt 0) {
  Write-Host "  残留工具链：$($toolchains -join ', ')" -ForegroundColor Yellow
} else {
  Write-RemovedStatus -Label 'toolchains' -NotPresent ($toolchains.Count -eq 0)
}

Write-Host ""
if (-not $Failed) { Write-Host "  卸载完成！" -ForegroundColor Green }
else { Write-Host "  卸载流程已结束，但部分步骤失败或未完成，请查看上方日志手动处理。" -ForegroundColor Yellow }
