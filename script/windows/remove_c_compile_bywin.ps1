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
  $hasWinget = Get-ExePath 'winget.exe'
  $hasCl = Get-ExePath 'cl.exe'

  if (-not $hasCl) {
    Write-Warn "未检测到 MSVC 编译器（cl.exe），跳过"
    return
  }

  # 通过 winget list 查找已安装的 BuildTools 包
  $installed = @()
  if ($hasWinget) {
    $allIds = @('Microsoft.VisualStudio.2022.BuildTools', 'Microsoft.VisualStudio.2019.BuildTools')
    foreach ($id in $allIds) {
      $result = Invoke-NativeText -FilePath 'winget' -Arguments @('list', '--id', $id, '--exact')
      if ($result -join '' -match $id) { $installed += $id }
    }
  }

  if ($installed.Count -gt 0) {
    Write-Ok "检测到已安装的 MSVC BuildTools：$($installed -join ', ')"
    foreach ($id in $installed) {
      Write-Host "  卸载 $id ..." -ForegroundColor Cyan
      Invoke-NativeStream -Block { & winget uninstall $id --silent }
      if ($LASTEXITCODE -eq 0) { Write-Ok "已请求卸载 $id" }
      else { Write-Warn "winget 卸载 $id 失败或未匹配" }
    }
  } else {
    Write-Warn "winget 未匹配到已安装的 BuildTools 包"
    if ($hasCl) {
      Write-Warn "cl.exe 存在但可能通过完整 Visual Studio 安装，请通过「Visual Studio Installer」GUI 手动卸载"
    }
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
    Enable-AutoConfirm
    Remove-Msys2
  }
  2 {
    Enable-AutoConfirm
    Remove-Msvc
  }
  3 {
    Enable-AutoConfirm
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
