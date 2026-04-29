$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

function Remove-Msys2 {
  $msysRoot = 'C:\msys64'
  if (-not (Test-Path -LiteralPath $msysRoot)) {
    Write-Warn "未检测到 MSYS2 安装目录 C:\msys64"
    return
  }
  Write-Warn "卸载 MSYS2 将删除整个 C:\msys64 目录及所有已装包（含其他工具）"

  if (Get-ExePath 'winget.exe') {
    Invoke-NativeStream -Block { & winget uninstall MSYS2.MSYS2 --silent }
  }
  Start-Sleep -Seconds 2
  if (Test-Path -LiteralPath $msysRoot) {
    # winget 未匹配或卸载失败，尝试直接删除
    Write-Host "  尝试直接删除 $msysRoot ..." -ForegroundColor Cyan
    try {
      Remove-Item -Recurse -Force -LiteralPath $msysRoot -ErrorAction Stop
    } catch {
      Write-Warn "自动删除失败：$($_.Exception.Message)"
    }
  }
  if (Test-Path -LiteralPath $msysRoot) {
    Write-Warn "无法自动删除 C:\msys64（可能被其他进程占用）"
    Write-Warn "请关闭所有 MSYS2 / Git Bash 终端后手动执行："
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

  if (-not (Get-ExePath 'winget.exe')) {
    Write-Warn "winget 不可用，请手动通过「Visual Studio Installer」卸载"
    return
  }

  $removed = $false
  foreach ($id in @('Microsoft.VisualStudio.2022.BuildTools', 'Microsoft.VisualStudio.2019.BuildTools')) {
    Write-Host "  卸载 $id ..." -ForegroundColor Cyan
    Invoke-NativeStream -Block { & winget uninstall $id --silent }
    if ($LASTEXITCODE -eq 0) { Write-Ok "已请求卸载 $id"; $removed = $true }
  }
  if (-not $removed) {
    Write-Warn "winget 未匹配到已安装的 Visual Studio Build Tools"
    Write-Warn "请通过「Visual Studio Installer」GUI 手动卸载"
  }
}

Write-Host ""
Write-Banner -Title 'C/C++ 编译工具卸载（Windows）          ' -Color Red
Write-Host ""
Write-Warn "本脚本会卸载系统级开发工具，可能影响其它项目。请确认你了解每一步。"
Write-Host ""

$selected = Select-MenuOption -Prompt '请选择要卸载的内容：' -Options @(
  '卸载 MSYS2 + MinGW gcc',
  '卸载 Visual Studio Build Tools (MSVC)',
  '全部卸载（MSYS2 + MSVC）'
)

switch ($selected) {
  1 {
    Remove-Msys2
  }
  2 {
    Remove-Msvc
  }
  3 {
    Write-Warn "即将依次卸载：MSYS2 → MSVC"

    Remove-Msys2
    Remove-Msvc
  }
  0 {
    Exit-NoOp "已退出，未卸载任何内容。"
  }
}

Write-Host ""
Write-Banner -Title '卸载结束摘要                            ' -Color Cyan

$hasMsvc = $null -ne (Get-ExePath 'cl.exe')
$hasGcc = $null -ne (Get-ExePath 'gcc.exe')
$hasMsys2 = Test-Path -LiteralPath 'C:\msys64'

Write-RemovedStatus -Label 'MSVC      ' -NotPresent (-not $hasMsvc)
Write-RemovedStatus -Label 'GNU GCC   ' -NotPresent (-not $hasGcc)
Write-RemovedStatus -Label 'MSYS2     ' -NotPresent (-not $hasMsys2)

Write-Host ""
if (-not $Failed) { Write-Host "  卸载完成！" -ForegroundColor Green }
else { Write-Host "  卸载流程已结束，但部分步骤失败或未完成，请查看上方日志手动处理。" -ForegroundColor Yellow }
