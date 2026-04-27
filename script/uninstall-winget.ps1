#Requires -RunAsAdministrator
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  winget 禁用工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 查找所有 winget.exe
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetCmd) {
    Write-Host "未找到 winget 命令，可能已被禁用或卸载。" -ForegroundColor Yellow
    exit 0
}

Write-Host "找到 winget: $($wingetCmd.Source)" -ForegroundColor Green
Write-Host ""

# 查找 WindowsApps 下所有 winget.exe
$targets = @()
$appDirs = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*" -Directory -ErrorAction SilentlyContinue
foreach ($dir in $appDirs) {
    $exe = Join-Path $dir.FullName "winget.exe"
    if (Test-Path $exe) {
        $targets += $exe
    }
}

# 也加上 Get-Command 找到的路径
if ($wingetCmd.Source -and ($targets -notcontains $wingetCmd.Source)) {
    $targets += $wingetCmd.Source
}

if ($targets.Count -eq 0) {
    Write-Host "未找到 winget.exe 文件。" -ForegroundColor Yellow
    exit 0
}

Write-Host "找到以下 winget.exe 文件:" -ForegroundColor Cyan
foreach ($t in $targets) {
    Write-Host "  $t"
}
Write-Host ""
Write-Host "将通过重命名为 .bak 来禁用 winget 命令。" -ForegroundColor White
Write-Host "(恢复方法: 将 .bak 后缀去掉即可)" -ForegroundColor DarkGray
Write-Host ""

$confirm = Read-Host "是否继续? (y/N)"
if ($confirm -notmatch '^[yY]') {
    Write-Host "已取消。" -ForegroundColor Yellow
    exit 0
}

Write-Host ""

foreach ($exe in $targets) {
    Write-Host "处理: $exe" -ForegroundColor Cyan

    # 第1步: 获取父目录所有权 (WindowsApps 子目录受 TrustedInstaller 保护)
    $dir = Split-Path $exe
    Write-Host "  获取目录所有权..." -NoNewline
    $null = & takeown /f $dir /r /d Y 2>&1
    Write-Host " 完成" -ForegroundColor Green

    # 第2步: 授予管理员完全控制权限
    Write-Host "  设置权限..." -NoNewline
    $null = & icacls $dir /grant "Administrators:(OI)(CI)F" /t /c 2>&1
    Write-Host " 完成" -ForegroundColor Green

    # 第3步: 重命名
    Write-Host "  重命名 winget.exe -> winget.exe.bak ..." -NoNewline
    try {
        Rename-Item -Path $exe -NewName "winget.exe.bak" -Force -ErrorAction Stop
        Write-Host " 完成" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Warning "  重命名失败: $($_.Exception.Message)"
        Write-Host "  尝试替代方案: 用空文件覆盖..." -NoNewline
        try {
            [System.IO.File]::WriteAllBytes($exe, @())
            Write-Host " 完成" -ForegroundColor Green
        } catch {
            Write-Warning "  替代方案也失败: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "验证中..." -ForegroundColor Cyan
$check = Get-Command winget -ErrorAction SilentlyContinue
if (-not $check) {
    Write-Host "winget 已成功禁用!" -ForegroundColor Green
} else {
    Write-Host "winget 仍然可用: $($check.Source)" -ForegroundColor Yellow
    Write-Host "可能需要重启后生效，或存在其他副本。" -ForegroundColor Yellow
}
