$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

# ─── Rust 卸载函数 ────────────────────────────────────────────────────────────

function Remove-AllRustToolchain {
  if (-not (Get-ExePath 'rustup.exe')) { return }
  $toolchains = Get-RustupToolchain
  if ($toolchains.Count -eq 0) { return }
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
Write-Warn "即将完全卸载 Rust：所有工具链 + rustup + ~\.cargo + ~\.rustup"

Enable-AutoConfirm
Remove-AllRustToolchain
Remove-Rustup

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
