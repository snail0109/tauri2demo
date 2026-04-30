# script/_test_ps.ps1
# 临时自测脚本：语法解析 + helper 单元测试 + DryRun 端到端
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\script\_test_ps.ps1
# 退出码：0=全部通过，1=任一失败

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Failures = New-Object System.Collections.Generic.List[string]

<#
.SYNOPSIS
  定义一个简单的测试用例包装器：执行脚本块并打印 PASS/FAIL。
.PARAMETER Name
  用例名称（用于输出与失败汇总）。
.PARAMETER Body
  测试逻辑脚本块；抛异常即视为失败。
.NOTES
  失败用例会记录到 $script:Failures，最终以退出码 1 返回。
#>
function Test-Case {
  param([string]$Name, [scriptblock]$Body)
  Write-Host "  [TEST] $Name ... " -NoNewline
  try {
    & $Body
    Write-Host "PASS" -ForegroundColor Green
  } catch {
    Write-Host "FAIL" -ForegroundColor Red
    Write-Host "         $($_.Exception.Message)" -ForegroundColor Red
    $script:Failures.Add($Name) | Out-Null
  }
}

Write-Host "──── 1. 语法解析 ────" -ForegroundColor Cyan
$targets = @(
  '_common.ps1',
  'install_android_sdk_bywin.ps1',
  'install_c_compile_bywin.ps1',
  'remove_android_sdk_bywin.ps1',
  'remove_c_compile_bywin.ps1',
  'build_bywin.ps1'
)
foreach ($t in $targets) {
  $p = Join-Path $ScriptDir $t
  Test-Case -Name "parse $t" -Body {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) { throw ("解析错误 {0} 个：{1}" -f $errors.Count, ($errors[0].Message)) }
  }
}

Write-Host ""
Write-Host "──── 2. _common.ps1 helper 单元测试 ────" -ForegroundColor Cyan
. (Join-Path $ScriptDir '_common.ps1')

Test-Case -Name 'Get-ExePath: 已存在命令' -Body {
  $p = Get-ExePath 'powershell.exe'
  if (-not $p) { throw "powershell.exe 必须能找到" }
}
Test-Case -Name 'Get-ExePath: 不存在命令返回 $null' -Body {
  $p = Get-ExePath 'definitely_not_a_real_command_xyz.exe'
  if ($null -ne $p) { throw "应返回 null，实际：$p" }
}
Test-Case -Name 'Invoke-NativeText: stdout 行' -Body {
  $lines = Invoke-NativeText -FilePath 'cmd.exe' -Arguments @('/c', 'echo hello')
  if (-not ($lines -contains 'hello')) { throw "未捕获到 echo 输出" }
}
Test-Case -Name 'Invoke-NativeText: 不抛 NativeCommandError' -Body {
  $prev = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Stop'
    $null = Invoke-NativeText -FilePath 'cmd.exe' -Arguments @('/c', '1>&2 echo err & exit /b 0')
  } finally { $ErrorActionPreference = $prev }
}
Test-Case -Name 'Invoke-NativeStream: 不抛 NativeCommandError（即便外层 EAP=Stop）' -Body {
  # 对照：在 EAP=Stop 下，直接执行带 stderr 的 native 命令会抛终止异常；
  # Invoke-NativeStream 必须吸收掉，使调用方在 EAP=Stop 也能继续。
  $prev = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Stop'
    Invoke-NativeStream -Block { & cmd.exe /c '1>&2 echo info: hello & exit /b 0' } | Out-Null
  } finally { $ErrorActionPreference = $prev }
}
Test-Case -Name 'Resolve-AndroidHome: 显式路径优先' -Body {
  $tmp = Join-Path $env:TEMP ("ah_test_{0}" -f ([guid]::NewGuid().ToString('N')))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $r = Resolve-AndroidHome -PreferredRoot $tmp
    if ($r -ne (Resolve-Path -LiteralPath $tmp).Path) { throw "应解析为 $tmp，实际：$r" }
  } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Test-Case -Name 'Get-RustupInstalledTarget: 返回数组、无空元素' -Body {
  $r = Get-RustupInstalledTarget
  if ($null -eq $r) { throw '应返回数组而非 $null' }
  $arr = @($r)
  foreach ($t in $arr) {
    if ([string]::IsNullOrWhiteSpace($t)) { throw '不应包含空元素' }
  }
  if (Get-ExePath 'rustup.exe') {
    if ($arr.Count -lt 1) { throw 'rustup 已装且至少应有 host target' }
  }
}
Test-Case -Name 'Get-RustupToolchain: 返回数组、首段为名称' -Body {
  $r = Get-RustupToolchain
  if ($null -eq $r) { throw '应返回数组而非 $null' }
  $arr = @($r)
  foreach ($t in $arr) {
    if ([string]::IsNullOrWhiteSpace($t)) { throw '不应包含空元素' }
    if ($t -match '\s') { throw "工具链名 ‘$t’ 不应包含空白" }
  }
}
Test-Case -Name 'Get-PropValue: 解析 key=value' -Body {
  $lines = @('foo=bar', 'baz="quoted"', "x='single'")
  if ((Get-PropValue -Lines $lines -Key 'foo') -ne 'bar') { throw "foo" }
  if ((Get-PropValue -Lines $lines -Key 'baz') -ne 'quoted') { throw "baz 应去引号" }
  if ((Get-PropValue -Lines $lines -Key 'x') -ne 'single') { throw "x 应去单引号" }
  if ((Get-PropValue -Lines $lines -Key 'missing') -ne '') { throw "missing 应为空" }
}
Test-Case -Name 'Confirm-Step: Enable-AutoConfirm 后透过 wrapper 自动通过' -Body {
  Disable-AutoConfirm
  Enable-AutoConfirm
  try {
    if (-not (Confirm-Remove "auto-confirm test" 6>$null)) { throw 'Enable-AutoConfirm 后 Confirm-Remove 应自动 true' }
    if (-not (Confirm-Install "auto-confirm test" 6>$null)) { throw 'Enable-AutoConfirm 后 Confirm-Install 应自动 true' }
    if (-not (Confirm-Continue "auto-confirm test" 6>$null)) { throw 'Enable-AutoConfirm 后 Confirm-Continue 应自动 true' }
  } finally { Disable-AutoConfirm }
}
Test-Case -Name 'Confirm-Step: 未启用 AutoConfirm 时遇到 "n" 输入应返回 false（Default=No）' -Body {
  Disable-AutoConfirm
  $script = Join-Path $env:TEMP ("confirm_no_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
  @"
. '$ScriptDir\_common.ps1'
if (Confirm-Remove 'should be denied') { exit 2 } else { exit 0 }
"@ | Set-Content -LiteralPath $script -Encoding UTF8
  try {
    $null = 'n' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Confirm-Remove 在 'n' 输入下应返回 false（exit 0），实际 exit $LASTEXITCODE" }
  } finally {
    Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
  }
}

Write-Host ""
Write-Host "──── 3. build_bywin.ps1 不带参数 → 用法提示 ────" -ForegroundColor Cyan
Test-Case -Name 'build_bywin.ps1（无参数）' -Body {
  $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'build_bywin.ps1') 2>&1
  if ($LASTEXITCODE -ne 1) { throw "应 exit 1，实际 $LASTEXITCODE" }
  if (-not ($out -match '用法')) { throw "应显示用法提示" }
}

Write-Host ""
Write-Host "──── 4. remove_*.ps1 -DryRun（端到端，但不实际改系统） ────" -ForegroundColor Cyan
# DryRun 模式下脚本不应实际执行卸载操作；用 -y 自动确认，0 选项自动退出
# 注意：交互菜单仍会读 stdin，需注入 0 跳过
Test-Case -Name 'remove_android_sdk_bywin.ps1 -DryRun（菜单选 0 退出）' -Body {
  $out = '0' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'remove_android_sdk_bywin.ps1') -DryRun 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { throw "应 exit 0，实际 $rc；输出：$($out -join "`n")" }
}
Test-Case -Name 'remove_android_sdk_bywin.ps1 -DryRun（菜单选 1，子操作不再问）' -Body {
  # 只注入 "1"，不再注入任何 y/n。Enable-AutoConfirm 生效则全程不挂。
  $out = '1' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'remove_android_sdk_bywin.ps1') -DryRun 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { throw "应 exit 0，实际 $rc；输出：$($out -join "`n")" }
}
Test-Case -Name 'remove_android_sdk_bywin.ps1 -DryRun（菜单选 3 + 顶层 y，子操作不再问）' -Body {
  # 选 3 需要先在顶层确认；之后 Enable-AutoConfirm 接管所有子 Confirm-Remove。
  $out = "3`ny" | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'remove_android_sdk_bywin.ps1') -DryRun 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { throw "应 exit 0，实际 $rc；输出：$($out -join "`n")" }
}
Test-Case -Name 'remove_c_compile_bywin.ps1 -DryRun（菜单选 0 退出）' -Body {
  $out = '0' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'remove_c_compile_bywin.ps1') -DryRun 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { throw "应 exit 0，实际 $rc；输出：$($out -join "`n")" }
}
Test-Case -Name 'remove_c_compile_bywin.ps1 -DryRun（菜单选 1，子操作不再问）' -Body {
  $out = '1' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'remove_c_compile_bywin.ps1') -DryRun 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { throw "应 exit 0，实际 $rc；输出：$($out -join "`n")" }
}
Test-Case -Name 'remove_c_compile_bywin.ps1 -DryRun（菜单选 3 + 顶层 y，子操作不再问）' -Body {
  $out = "3`ny" | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'remove_c_compile_bywin.ps1') -DryRun 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { throw "应 exit 0，实际 $rc；输出：$($out -join "`n")" }
}

Write-Host ""
if ($Failures.Count -eq 0) {
  Write-Host "✓ 全部测试通过" -ForegroundColor Green
  exit 0
} else {
  Write-Host ("✗ {0} 个测试失败：" -f $Failures.Count) -ForegroundColor Red
  $Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}
