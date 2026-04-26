# script/_common.ps1
# 5 个 .ps1 脚本共享的辅助函数与状态变量。
# 通过 dot-sourcing 引入：. (Join-Path $PSScriptRoot '_common.ps1')
#
# 调用脚本约定：
#   - -y 静默模式：调用脚本声明 [switch]$Yes 并在 dot-source 后执行
#       if ($Yes) { Enable-AutoConfirm }
#   - 如需追踪整体失败状态，调用脚本应在顶部声明 $Failed = $false

# ─── Logging ─────────────────────────────────────────────────────────────────
function Write-Ok([string]$Message) {
  Write-Host "  ✓  $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
  Write-Host "  ⚠  $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
  Write-Host "  ✗  $Message" -ForegroundColor Red
  $script:Failed = $true
}

function Write-StatusLine {
  param(
    [string]$Label,
    [bool]$Ok,
    [string]$OkText = '已安装',
    [string]$NotOkText = '未安装',
    [string]$Detail = ''
  )
  $value = if ($Ok) { $OkText } else { $NotOkText }
  $color = if ($Ok) { 'Green' } else { 'Yellow' }
  $line = "  $Label：$value"
  if ($Detail) { $line += " ($Detail)" }
  Write-Host $line -ForegroundColor $color
}

function Write-RemovedStatus {
  # remove_*.ps1 卸载摘要专用包装：固定 OkText='已移除' / NotOkText 默认 '仍存在'。
  param([string]$Label, [bool]$NotPresent, [string]$Detail = '', [string]$NotOkText = '仍存在')
  Write-StatusLine -Label $Label -Ok:$NotPresent -OkText '已移除' -NotOkText $NotOkText -Detail $Detail
}

# ─── Confirmations ───────────────────────────────────────────────────────────
# 全局自动确认开关：一旦置位，本脚本进程内所有 Confirm-* 都直接返回 true。
# 用于 -y 静默模式，以及"主菜单选择后子操作不再重复确认"场景。
$script:__AutoConfirm = $false

function Enable-AutoConfirm { $script:__AutoConfirm = $true }
function Disable-AutoConfirm { $script:__AutoConfirm = $false }

function Confirm-Step {
  param(
    [string]$Desc,
    [ValidateSet('Yes', 'No')] [string]$Default = 'Yes',
    [string]$AutoLabel = '自动确认'
  )
  if ($script:__AutoConfirm) {
    Write-Host "  ${AutoLabel}：$Desc" -ForegroundColor Yellow
    return $true
  }
  $hint = if ($Default -eq 'Yes') { '[Y/n]' } else { '[y/N]' }
  $ans = Read-Host "  ? $Desc $hint"
  if ($Default -eq 'Yes') {
    return -not ($ans -match '^(n|no)$')
  } else {
    return ($ans -match '^(y|yes)$')
  }
}

function Confirm-Install([string]$Desc) { Confirm-Step -Desc "$Desc 是否自动安装？" -Default 'Yes' }
function Confirm-Continue([string]$Desc) { Confirm-Step -Desc "$Desc 是否继续？" -Default 'Yes' }
function Confirm-Remove([string]$Desc) { Confirm-Step -Desc "$Desc —— 是否卸载？" -Default 'No' -AutoLabel '自动确认卸载' }

function Select-MenuOption {
  param(
    [string]$Prompt,
    [string[]]$Options
  )
  Write-Host $Prompt -ForegroundColor Cyan
  for ($i = 0; $i -lt $Options.Count; $i++) {
    Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i]) -ForegroundColor Cyan
  }
  Write-Host "  0) 退出（不操作）" -ForegroundColor Cyan
  Write-Host ""
  $choice = Read-Host ("  请选择 [0-{0}]" -f $Options.Count)
  $n = 0
  if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n }
  return 0
}

# ─── Native command helpers ──────────────────────────────────────────────────
# 在 Windows PowerShell 5.1 下，native 命令通过 2>&1 把 stderr 合并到成功流时，
# 每行 stderr 会被包装成 NativeCommandError；当 $ErrorActionPreference='Stop'
# 时会被当作终止异常抛出（如 java/cl/gcc 把版本写到 stderr 就会炸）。
# 下面两个助手在调用期间局部把 EAP 降到 Continue，避免误抛。

function Invoke-NativeText {
  # 捕获 native 命令的 stdout+stderr 为字符串数组（每行一项）。
  param([string]$FilePath, [string[]]$Arguments = @())
  $prev = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
  } finally {
    $ErrorActionPreference = $prev
  }
}

function Invoke-NativeStream {
  # 透传 native 命令的输出到 Host：把 stderr 合并进 stdout，并把 ErrorRecord
  # 强制转为字符串，避免 PowerShell 5.1 用错误格式化器显示
  # （如 rustup 把 "info: ..." 写到 stderr 时会被显示成大红块）。
  # 调用方不要在块里再写 `2>&1 | Out-Host`，本函数已统一处理。
  param([scriptblock]$Block)
  $prev = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Block 2>&1 | ForEach-Object { Write-Host "$_" }
  } finally {
    $ErrorActionPreference = $prev
  }
}

# ─── Rustup helpers ──────────────────────────────────────────────────────────
function Get-RustupInstalledTarget {
  # 已安装的 Rust 编译目标列表（string[]）。rustup 不存在时返回空数组。
  if (-not (Get-ExePath 'rustup.exe')) { return @() }
  return @(Invoke-NativeText -FilePath 'rustup' -Arguments @('target', 'list', '--installed') |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-RustupToolchain {
  # 已安装的 Rust 工具链名称列表（string[]，每行第一段，去掉 "(default)" 等后缀）。
  if (-not (Get-ExePath 'rustup.exe')) { return @() }
  return @(Invoke-NativeText -FilePath 'rustup' -Arguments @('toolchain', 'list') |
    ForEach-Object { ($_ -split '\s+')[0] } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

# ─── Path / process discovery ────────────────────────────────────────────────
function Get-ExePath([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $cmd) { return $null }
  return $cmd.Source
}

function New-DirectoryIfMissing([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Add-PathPrefix([string]$Prefix) {
  if ([string]::IsNullOrWhiteSpace($Prefix)) { return }
  $parts = $env:Path -split ';'
  if ($parts -contains $Prefix) { return }
  $env:Path = "$Prefix;$env:Path"
}

function Add-CargoBinPath {
  # 若 ~/.cargo/bin 存在则前置到当前 shell PATH，便于随后 Get-ExePath 命中 rustup/rustc。
  $p = Join-Path $HOME '.cargo\bin'
  if (Test-Path -LiteralPath $p) { Add-PathPrefix $p }
}

function Get-PnpmExe {
  # Windows 上 pnpm 同时存在 pnpm.cmd（npm 全局装）与 pnpm.exe（独立安装器），优先 .cmd。
  return (Get-ExePath 'pnpm.cmd'), (Get-ExePath 'pnpm.exe') | Where-Object { $_ } | Select-Object -First 1
}

# ─── User environment writers ────────────────────────────────────────────────
function Set-UserEnv([string]$Name, [string]$ValueOrNull) {
  try {
    [Environment]::SetEnvironmentVariable($Name, $ValueOrNull, 'User')
    return $true
  } catch {
    return $false
  }
}

function Add-UserPathSegment([string]$Segment) {
  $seg = $Segment.Trim()
  if ([string]::IsNullOrWhiteSpace($seg)) { return $true }
  $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
  $parts = if ([string]::IsNullOrWhiteSpace($userPath)) { @() } else { $userPath -split ';' }
  foreach ($p in $parts) {
    if ($p.Trim().ToLowerInvariant() -eq $seg.ToLowerInvariant()) { return $true }
  }
  $new = if ([string]::IsNullOrWhiteSpace($userPath)) { $seg } else { "$userPath;$seg" }
  return (Set-UserEnv -Name 'PATH' -ValueOrNull $new)
}

function Set-UserEnvIfChanged {
  # 写入用户环境变量；若与现值相同则只打印"已正确设置"日志。
  # 替代 install_android_sdk 中重复的 ANDROID_HOME / ANDROID_NDK_HOME 设置块。
  param([string]$Name, [string]$Value)
  $current = [Environment]::GetEnvironmentVariable($Name, 'User')
  if ($current -eq $Value) {
    Write-Ok "$Name 环境变量已正确设置：$Value"
    return
  }
  if (Set-UserEnv -Name $Name -ValueOrNull $Value) {
    Write-Ok "$Name 已写入用户环境变量：$Value"
    Write-Ok "（新开终端窗口后生效）"
  } else {
    Write-Warn "写入 $Name 失败，请手动设置"
    Write-Warn "  系统设置 → 环境变量 → 用户变量 → 新建 $Name = $Value"
  }
}

# ─── Web download ────────────────────────────────────────────────────────────
function Save-WebFile {
  # 依次尝试 $Urls 直到下载成功；下载失败时返回 $false，不抛异常。
  param([string[]]$Urls, [string]$OutFile, [int]$TimeoutSec = 30)
  foreach ($u in $Urls) {
    Write-Host "  尝试下载：$u" -ForegroundColor Cyan
    try {
      Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec | Out-Null
      Write-Ok "下载完成（来源：$u）"
      return $true
    } catch {
      Write-Warn "下载失败，尝试下一个镜像 ..."
    }
  }
  return $false
}

# ─── Android SDK / NDK discovery ─────────────────────────────────────────────
function Get-AndroidSdkRootCandidate {
  # 候选 SDK 根（按探测优先级返回 string[]）：显式 -PreferredRoot → ANDROID_HOME →
  # ANDROID_SDK_ROOT → 项目约定 C:\DevDisk\DevTools\AndroidSDK → Android Studio 默认。
  param([string]$PreferredRoot)

  $roots = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($PreferredRoot)) {
    $roots.Add($PreferredRoot.Trim('"')) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) { $roots.Add($env:ANDROID_HOME.Trim('"')) | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) { $roots.Add($env:ANDROID_SDK_ROOT.Trim('"')) | Out-Null }
  $roots.Add('C:\DevDisk\DevTools\AndroidSDK') | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $roots.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Out-Null
  }
  $roots.Add((Join-Path $HOME 'AppData\Local\Android\Sdk')) | Out-Null
  return $roots
}

function Resolve-AndroidHome {
  param([string]$PreferredRoot)
  foreach ($p in (Get-AndroidSdkRootCandidate -PreferredRoot $PreferredRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) {
      return (Resolve-Path -LiteralPath $p).Path
    }
  }
  return $null
}

function Find-SdkManager {
  param([string]$PreferredRoot)
  foreach ($r in (Get-AndroidSdkRootCandidate -PreferredRoot $PreferredRoot)) {
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    $p = Join-Path $r 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
  }
  return $null
}

function Get-AndroidHomeFromSdkManager([string]$SdkManagerPath) {
  $binDir = Split-Path -Parent $SdkManagerPath
  $latestDir = Split-Path -Parent $binDir
  $cmdlineDir = Split-Path -Parent $latestDir
  $sdkRoot = Split-Path -Parent $cmdlineDir
  return (Resolve-Path -LiteralPath $sdkRoot).Path
}

function Resolve-AndroidNdk([string]$AndroidHome) {
  $ndkDir = Join-Path $AndroidHome 'ndk'
  if (Test-Path -LiteralPath $ndkDir) {
    $versions = Get-ChildItem -LiteralPath $ndkDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($versions) {
      $best = $versions | Sort-Object {
        try { [version]($_ -replace '[^0-9\.]', '') } catch { [version]'0.0' }
      } | Select-Object -Last 1
      if ($best) { return @{ Path = (Join-Path $ndkDir $best); Version = $best; Kind = 'ndk' } }
    }
  }
  $bundle = Join-Path $AndroidHome 'ndk-bundle'
  if (Test-Path -LiteralPath $bundle) {
    $ver = 'ndk-bundle'
    $prop = Join-Path $bundle 'source.properties'
    if (Test-Path -LiteralPath $prop) {
      $line = (Get-Content -LiteralPath $prop -ErrorAction SilentlyContinue | Where-Object { $_ -match '^Pkg\.Revision\s*=' } | Select-Object -First 1)
      if ($line) { $ver = ($line -split '=' | Select-Object -Last 1).Trim() }
    }
    return @{ Path = $bundle; Version = $ver; Kind = 'ndk-bundle' }
  }
  return $null
}

function Get-JavaMajorVersion {
  if ($null -eq (Get-ExePath 'java.exe')) { return $null }
  $line = (Invoke-NativeText -FilePath 'java' -Arguments @('-version') | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($line)) { return $null }
  $m = [regex]::Match($line, '([0-9]+)')
  if (-not $m.Success) { return $null }
  return [int]$m.Groups[1].Value
}

# ─── Misc helpers ────────────────────────────────────────────────────────────
function Get-PropValue {
  param([string[]]$Lines, [string]$Key)
  $line = $Lines | Where-Object { $_ -match ('^' + [regex]::Escape($Key) + '=') } | Select-Object -First 1
  if (-not $line) { return '' }
  return ($line -replace ('^' + [regex]::Escape($Key) + '='), '').Trim().Trim('"').Trim("'")
}
