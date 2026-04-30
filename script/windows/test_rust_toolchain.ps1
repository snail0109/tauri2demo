# 测试 Test-RustToolchain 函数
$ErrorActionPreference = 'Continue'

# 1. 加载依赖
. (Join-Path $PSScriptRoot '_common.ps1')

# 2. 定义 Test-RustToolchain（从 install_c_compile_bywin.ps1 复制，但独立运行）
<#
.SYNOPSIS
  自测 rustc 工具链是否可用（用于调试 PATH / rustup 安装问题）。
.OUTPUTS
  [bool] 工具链可用返回 $true，否则返回 $false。
.NOTES
  会写入 $script:RustcVersion / $script:RustcHost 供下方打印。
#>
function Test-RustToolchain {
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
    Write-Warn "rustc 已找到但输出异常（toolchain 可能不完整）：$script:RustcVersion"
    $script:RustcVersion = $null
    $script:RustcHost = $null
    return $false
  }
  $hostLine = Invoke-NativeText -FilePath 'rustc' -Arguments @('-vV') |
    Where-Object { $_ -match '^host:\s*' } |
    Select-Object -First 1
  if ($hostLine) { $script:RustcHost = ($hostLine -replace '^host:\s*', '').Trim() }
  Write-Ok "Rust 工具链已安装"
  if (-not [string]::IsNullOrWhiteSpace($script:RustcHost)) { Write-Host "    host：$($script:RustcHost)" }
  if (-not [string]::IsNullOrWhiteSpace($script:RustcVersion)) { Write-Host "    版本：$($script:RustcVersion)" }
  return $true
}

# 3. 诊断：查找 rustc.exe 位置
Write-Host "──── 诊断信息 ────" -ForegroundColor DarkGray
Write-Host "  `$env:USERPROFILE = $env:USERPROFILE"
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
Write-Host "  .cargo\bin 路径: $cargoBin"
Write-Host "  .cargo\bin 存在: $(Test-Path -LiteralPath $cargoBin)"
$rustcFromPath = Get-ExePath 'rustc.exe'
Write-Host "  Get-ExePath rustc.exe: $rustcFromPath"
Write-Host ""

# 4. 执行测试
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Test-RustToolchain 函数测试" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$result = Test-RustToolchain

Write-Host ""
Write-Host "──────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  测试结果：" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────────" -ForegroundColor Cyan

if ($result) {
  Write-Host "  ✓ 函数返回：`$true" -ForegroundColor Green
  Write-Host "  ✓ `$script:RustcVersion = $script:RustcVersion"
  Write-Host "  ✓ `$script:RustcHost    = $script:RustcHost"
} else {
  Write-Host "  ✗ 函数返回：`$false（toolchain 不可用）" -ForegroundColor Red
  if ($script:RustcVersion) { Write-Host "  异常输出：$script:RustcVersion" -ForegroundColor Red }
}
