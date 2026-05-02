# script/_common.ps1
# 5 个 .ps1 脚本共享的辅助函数与状态变量。
# 通过 dot-sourcing 引入：. (Join-Path $PSScriptRoot '_common.ps1')
#
# 调用脚本约定：
#   - -y 静默模式：调用脚本声明 [switch]$Yes 并在 dot-source 后执行
#       if ($Yes) { Enable-AutoConfirm }
#   - 如需追踪整体失败状态，调用脚本应在顶部声明 $Failed = $false

# ─── Logging ─────────────────────────────────────────────────────────────────
<#
.SYNOPSIS
  输出成功日志（绿色 ✓）。
.PARAMETER Message
  要输出的提示文本。
#>
function Write-Ok([string]$Message) {
  Write-Host "  ✓  $Message" -ForegroundColor Green
}

<#
.SYNOPSIS
  输出警告日志（黄色 ⚠）。
.PARAMETER Message
  要输出的提示文本。
#>
function Write-Warn([string]$Message) {
  Write-Host "  ⚠  $Message" -ForegroundColor Yellow
}

<#
.SYNOPSIS
  输出失败日志（红色 ✗），并把全局失败标记置为 $true。
.PARAMETER Message
  要输出的提示文本。
.NOTES
  会写入 $script:Failed = $true，便于调用脚本在结尾统一判断是否失败。
#>
function Write-Fail([string]$Message) {
  Write-Host "  ✗  $Message" -ForegroundColor Red
  $script:Failed = $true
}

<#
.SYNOPSIS
  输出“状态行”格式：Label：已安装/未安装（可自定义文本与附加说明）。
.PARAMETER Label
  左侧标签文本。
.PARAMETER Ok
  是否为“成功/已安装”状态。
.PARAMETER OkText
  Ok 为 $true 时显示的文本。
.PARAMETER NotOkText
  Ok 为 $false 时显示的文本。
.PARAMETER Detail
  额外说明（可为空）。
#>
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

<#
.SYNOPSIS
  remove_*.ps1 的卸载摘要专用状态行：固定 OkText='已移除'。
.PARAMETER Label
  左侧标签文本。
.PARAMETER NotPresent
  目标是否“不存在”（不存在即视为已移除）。
.PARAMETER Detail
  额外说明（可为空）。
.PARAMETER NotOkText
  NotPresent 为 $false 时显示文本，默认“仍存在”。
#>
function Write-RemovedStatus {
  # remove_*.ps1 卸载摘要专用包装：固定 OkText='已移除' / NotOkText 默认 '仍存在'。
  param([string]$Label, [bool]$NotPresent, [string]$Detail = '', [string]$NotOkText = '仍存在')
  Write-StatusLine -Label $Label -Ok:$NotPresent -OkText '已移除' -NotOkText $NotOkText -Detail $Detail
}

<#
.SYNOPSIS
  输出 3 行横幅：上分隔线 + 标题 + 下分隔线。
.PARAMETER Title
  标题文本。
.PARAMETER Color
  分隔线颜色。
.PARAMETER TitleColor
  标题颜色（默认与 Color 相同）。
.PARAMETER Width
  分隔线宽度（字符数）。
#>
function Write-Banner {
  # 输出 3 行横幅：上 ═ 条 + 标题 + 下 ═ 条。前后空行由调用方控制。
  # TitleColor 缺省与 Color 一致；少数场合（如安装完成提示）用 Green 标题 + Cyan 边。
  param(
    [string]$Title,
    [string]$Color = 'Cyan',
    [string]$TitleColor,
    [int]$Width = 42
  )
  if ([string]::IsNullOrWhiteSpace($TitleColor)) { $TitleColor = $Color }
  $bar = '═' * $Width
  Write-Host $bar -ForegroundColor $Color
  Write-Host "  $Title" -ForegroundColor $TitleColor
  Write-Host $bar -ForegroundColor $Color
}

# ─── Confirmations ───────────────────────────────────────────────────────────
# 全局自动确认开关：一旦置位，本脚本进程内所有 Confirm-* 都直接返回 true。
# 用于 -y 静默模式，以及"主菜单选择后子操作不再重复确认"场景。
$script:__AutoConfirm = $false

<#
.SYNOPSIS
  启用“自动确认”模式：所有 Confirm-* 直接返回 $true。
.NOTES
  常用于 -y 静默模式，或主菜单确认后子操作不再重复询问。
#>
function Enable-AutoConfirm { $script:__AutoConfirm = $true }

<#
.SYNOPSIS
  关闭“自动确认”模式：Confirm-* 恢复交互询问。
#>
function Disable-AutoConfirm { $script:__AutoConfirm = $false }

<#
.SYNOPSIS
  交互式确认步骤（支持默认值与自动确认）。
.PARAMETER Desc
  交互提示文本。
.PARAMETER Default
  默认选项（Yes/No）。
.PARAMETER AutoLabel
  自动确认场景下的说明标签（目前仅用于语义表达）。
.OUTPUTS
  [bool] 用户是否确认继续。
#>
function Confirm-Step {
  param(
    [string]$Desc,
    [ValidateSet('Yes', 'No')] [string]$Default = 'Yes',
    [string]$AutoLabel = '自动确认'
  )
  if ($script:__AutoConfirm) {
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

<#
.SYNOPSIS
  询问“是否安装/自动安装”。
.PARAMETER Desc
  描述文本。
.OUTPUTS
  [bool]
#>
function Confirm-Install([string]$Desc) { Confirm-Step -Desc "$Desc 是否自动安装？" -Default 'Yes' }

<#
.SYNOPSIS
  询问“是否继续”。
.PARAMETER Desc
  描述文本。
.OUTPUTS
  [bool]
#>
function Confirm-Continue([string]$Desc) { Confirm-Step -Desc "$Desc 是否继续？" -Default 'Yes' }

<#
.SYNOPSIS
  询问“是否卸载”（默认 No，更安全）。
.PARAMETER Desc
  描述文本。
.OUTPUTS
  [bool]
#>
function Confirm-Remove([string]$Desc) { Confirm-Step -Desc "$Desc —— 是否卸载？" -Default 'No' -AutoLabel '自动确认卸载' }

<#
.SYNOPSIS
  输出提示并退出脚本（用于“用户选择不操作”场景）。
.PARAMETER Message
  退出前输出的提示文本。
.PARAMETER Code
  退出码（默认 0）。
#>
function Exit-NoOp {
  # 用户在菜单或确认提示中选择放弃时的统一退出：黄字提示 + exit。
  # remove_*.ps1 的"菜单选 0 / Confirm-Remove 拒绝"以及 install_c_compile 的"菜单选 0"共用。
  param([string]$Message, [int]$Code = 0)
  Write-Host ""
  Write-Host "  $Message" -ForegroundColor Yellow
  exit $Code
}

<#
.SYNOPSIS
  输出简单编号菜单并读取用户选择。
.PARAMETER Prompt
  菜单提示标题。
.PARAMETER Options
  选项列表（从 1 开始编号，0 代表退出）。
.OUTPUTS
  [int] 选择的编号（0 表示退出/无效输入）。
#>
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

<#
.SYNOPSIS
  以“文本行数组”的方式执行 native 命令（合并 stdout+stderr），且避免 PowerShell 5.1 的 NativeCommandError 终止异常。
.PARAMETER FilePath
  可执行文件路径或命令名。
.PARAMETER Arguments
  参数数组。
.OUTPUTS
  [string[]] 每行一条文本。
.NOTES
  函数内部临时把 $ErrorActionPreference 设为 Continue，执行结束后恢复。
#>
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

<#
.SYNOPSIS
  执行 native 命令并把输出“流式”打印到 Host（处理 PowerShell 5.1 的 stderr/进度条兼容问题）。
.PARAMETER Block
  要执行的脚本块（内部应仅包含 native 命令调用）。
.NOTES
  - 会把 stderr 合并并强制转成字符串，避免红色 ErrorRecord 块污染日志。
  - 对常见进度条/旋转帧做单行覆盖，减少刷屏。
#>
function Invoke-NativeStream {
  # 透传 native 命令的输出到 Host：把 stderr 合并进 stdout，并把 ErrorRecord
  # 强制转为字符串，避免 PowerShell 5.1 用错误格式化器显示
  # （如 rustup 把 "info: ..." 写到 stderr 时会被显示成大红块）。
  # 调用方不要在块里再写 `2>&1 | Out-Host`，本函数已统一处理。
  # winget 等工具的进度条帧（如 "▉  3%" 或 "- \ | /" 旋转动画）每帧输出一行，
  # 用 [Console]::SetCursorPosition 覆盖同一行，避免刷屏。
  # 非进度条的正常文本始终正常输出。
  param([scriptblock]$Block)
  $prev = $ErrorActionPreference
  $isSpinnerLine = $false
  try {
    $ErrorActionPreference = 'Continue'
    & $Block 2>&1 | ForEach-Object {
      $text = "$_"
      $trimmed = $text.Trim()
      # 检测进度条帧：行内仅包含进度条字符（▉▓░█─━■□●○◆◇★☆spinner等）+ 空格 + 百分比
      # 不含字母/中文等正常文本内容的短行视为进度条帧
      $isSpinner = ($trimmed.Length -gt 0) -and ($trimmed.Length -le 40) -and
                   ($trimmed -notmatch '[a-zA-Z一-鿿]') -and
                   ($trimmed -match '[▉▓░█─━■□●○◆◇★☆\-\\/|%0-9]')
      if ($isSpinner) {
        if ($isSpinnerLine) {
          [Console]::SetCursorPosition(0, [Console]::CursorTop)
          # 用空格覆盖旧内容（新内容可能比旧内容短）
          [Console]::Write((' ' * [Math]::Max(0, [Console]::WindowWidth - 1)))
          [Console]::SetCursorPosition(0, [Console]::CursorTop)
        }
        [Console]::Write($text)
        $isSpinnerLine = $true
      } else {
        if ($isSpinnerLine) {
          [Console]::WriteLine()
          $isSpinnerLine = $false
        }
        Write-Host $text
      }
    }
    # 如果最后一行是进度条，补一个换行
    if ($isSpinnerLine) {
      [Console]::WriteLine()
    }
  } finally {
    $ErrorActionPreference = $prev
  }
}

<#
.SYNOPSIS
  切换到指定目录后执行 native 命令（执行完必定恢复当前目录）。
.PARAMETER Path
  工作目录。
.PARAMETER Block
  要执行的脚本块（内部应包含 native 命令调用）。
#>
function Invoke-NativeStreamIn {
  # 在 $Path 目录下运行 $Block；总是恢复 cwd，即便 native 命令出错也不残留。
  param([string]$Path, [scriptblock]$Block)
  Push-Location $Path
  try { Invoke-NativeStream -Block $Block } finally { Pop-Location }
}

# ─── Rustup helpers ──────────────────────────────────────────────────────────
<#
.SYNOPSIS
  获取当前 rustup 已安装的 target 列表。
.OUTPUTS
  [string[]] 已安装 target；rustup 不存在时返回空数组。
#>
function Get-RustupInstalledTarget {
  # 已安装的 Rust 编译目标列表（string[]）。rustup 不存在时返回空数组。
  # 注意：PowerShell 会枚举数组输出；若直接 return @()，调用方可能得到 $null。
  if (-not (Get-ExePath 'rustup.exe')) { return ,([string[]]@()) }
  return @(Invoke-NativeText -FilePath 'rustup' -Arguments @('target', 'list', '--installed') |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

<#
.SYNOPSIS
  获取 Tauri Android 构建所需的 Rust target 列表（固定 4 个）。
.OUTPUTS
  [string[]]
#>
function Get-AndroidRustTarget {
  # Tauri Android 构建所需的 4 个 Rust 编译目标。install / remove / build 共用。
  return @(
    'aarch64-linux-android',
    'armv7-linux-androideabi',
    'i686-linux-android',
    'x86_64-linux-android'
  )
}

<#
.SYNOPSIS
  获取当前 rustup 已安装的工具链名称列表。
.OUTPUTS
  [string[]] 工具链名称（去掉 "(default)" 等后缀）。
#>
function Get-RustupToolchain {
  # 已安装的 Rust 工具链名称列表（string[]，每行第一段，去掉 "(default)" 等后缀）。
  # 注意：PowerShell 会枚举数组输出；若直接 return @()，调用方可能得到 $null。
  if (-not (Get-ExePath 'rustup.exe')) { return ,([string[]]@()) }
  return @(Invoke-NativeText -FilePath 'rustup' -Arguments @('toolchain', 'list') |
    ForEach-Object { ($_ -split '\s+')[0] } |
    Where-Object { $_ -match '^\w+-\w+-\w+-\w+' })
}

# ─── Path / process discovery ────────────────────────────────────────────────
<#
.SYNOPSIS
  解析可执行文件路径（相当于 Windows 的 where/PowerShell 的 Get-Command Source）。
.PARAMETER Name
  命令名（如 rustc.exe）。
.OUTPUTS
  [string] 可执行文件路径；不存在返回 $null。
#>
function Get-ExePath([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $cmd) { return $null }
  return $cmd.Source
}

<#
.SYNOPSIS
  确保目录存在，不存在则创建。
.PARAMETER Path
  目录路径。
#>
function New-DirectoryIfMissing([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

<#
.SYNOPSIS
  把指定目录前置到当前进程 PATH（避免重复添加）。
.PARAMETER Prefix
  需要前置的目录路径。
#>
function Add-PathPrefix([string]$Prefix) {
  if ([string]::IsNullOrWhiteSpace($Prefix)) { return }
  $parts = $env:Path -split ';'
  if ($parts -contains $Prefix) { return }
  $env:Path = "$Prefix;$env:Path"
}

<#
.SYNOPSIS
  把 ~\.cargo\bin 前置到当前进程 PATH（如果该目录存在）。
.NOTES
  主要用于在当前 shell 里立刻找到 rustup/rustc/cargo。
#>
function Add-CargoBinPath {
  # 若 ~/.cargo/bin 存在则前置到当前 shell PATH，便于随后 Get-ExePath 命中 rustup/rustc。
  $p = Join-Path $HOME '.cargo\bin'
  if (Test-Path -LiteralPath $p) { Add-PathPrefix $p }
}

<#
.SYNOPSIS
  获取 pnpm 可执行文件路径（优先 pnpm.cmd）。
.OUTPUTS
  [string] pnpm 路径；未安装返回 $null。
#>
function Get-PnpmExe {
  # Windows 上 pnpm 同时存在 pnpm.cmd（npm 全局装）与 pnpm.exe（独立安装器），优先 .cmd。
  return (Get-ExePath 'pnpm.cmd'), (Get-ExePath 'pnpm.exe') | Where-Object { $_ } | Select-Object -First 1
}

# ─── User environment writers ────────────────────────────────────────────────
<#
.SYNOPSIS
  写入用户级环境变量（User scope）。
.PARAMETER Name
  变量名。
.PARAMETER ValueOrNull
  变量值；传 $null 表示删除该变量。
.OUTPUTS
  [bool] 是否写入成功。
#>
function Set-UserEnv([string]$Name, [string]$ValueOrNull) {
  try {
    [Environment]::SetEnvironmentVariable($Name, $ValueOrNull, 'User')
    return $true
  } catch {
    return $false
  }
}

<#
.SYNOPSIS
  把一个目录段追加到用户 PATH（User scope），避免重复添加。
.PARAMETER Segment
  要追加的目录路径。
.OUTPUTS
  [bool] 是否处理成功（含“已存在”场景）。
#>
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

<#
.SYNOPSIS
  仅在值变化时写入用户环境变量，并输出中文提示。
.PARAMETER Name
  变量名。
.PARAMETER Value
  要写入的新值。
.NOTES
  用于减少重复写入与重复日志。
#>
function Set-UserEnvIfChanged {
  # 写入用户环境变量；若与现值相同则只打印"已正确设置"日志。
  # 替代 install_android_sdk 中重复的 ANDROID_HOME / ANDROID_NDK_HOME 设置块。
  param([string]$Name, [string]$Value)
  $current = [Environment]::GetEnvironmentVariable($Name, 'User')
  if ($current -eq $Value) {
    return
  }
  if (Set-UserEnv -Name $Name -ValueOrNull $Value) {
    Write-Ok "set $Name = $Value"
  } else {
    Write-Warn "set $Name = $Value (失败)"
  }
}

# ─── Web download ────────────────────────────────────────────────────────────
<#
.SYNOPSIS
  从单个 URL 下载文件（带简单进度显示）。
.PARAMETER Url
  下载地址。
.PARAMETER OutFile
  输出文件路径。
.PARAMETER TimeoutSec
  超时秒数（连接与读写）。
.OUTPUTS
  [bool] 是否下载成功。
#>
function Save-WebFileSingle {
  # 单地址直接下载，带进度显示
  param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 30)

  Write-Host "  下载：$Url" -ForegroundColor Cyan
  $resp = $null; $stream = $null; $out = $null
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.UserAgent = 'PowerShell/Save-WebFile'
    $req.AllowAutoRedirect = $true
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $stream = $resp.GetResponseStream()
    $out = [System.IO.File]::Create($OutFile)

    $buf = New-Object byte[] 81920
    [long]$read = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastReport = 0L
    $lastLineLen = 0
    while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
      $out.Write($buf, 0, $n)
      $read += $n
      $now = $sw.ElapsedMilliseconds
      if ($now - $lastReport -lt 200) { continue }
      $lastReport = $now
      $sec = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
      $speedKB = ($read / $sec) / 1KB
      if ($total -gt 0) {
        $pct = [int](($read / $total) * 100)
        $etaSec = if ($speedKB -gt 0) { [int](($total - $read) / 1KB / $speedKB) } else { 0 }
        $status = '{0,3}%  {1,8:N0} / {2,8:N0} KB  {3,6:N0} KB/s  ETA {4}s' -f $pct, ($read/1KB), ($total/1KB), $speedKB, $etaSec
      } else {
        $status = '{0,8:N0} KB  {1,6:N0} KB/s' -f ($read/1KB), $speedKB
      }
      $line = "    $status"
      $pad = [Math]::Max(0, $lastLineLen - $line.Length)
      [Console]::Write("`r" + $line + (' ' * $pad))
      $lastLineLen = $line.Length
    }
    [Console]::Write("`r" + (' ' * $lastLineLen) + "`r")

    $sw.Stop()
    $sec = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
    $avgKB = ($read / $sec) / 1KB
    Write-Ok ("下载完成（{0:N0} KB，{1:N0} KB/s）" -f ($read/1KB), $avgKB)
    Write-Host "  下载完成：$OutFile" -ForegroundColor Cyan
    return $true
  } catch {
    Write-Warn "下载失败：$($_.Exception.Message)"
    Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
  } finally {
    if ($out) { $out.Close() }
    if ($stream) { $stream.Close() }
    if ($resp) { $resp.Close() }
  }
  return $false
}

<#
.SYNOPSIS
  多地址下载：先并行测速选择最快源，再用单线程稳定下载。
.PARAMETER Urls
  候选 URL 列表（会自动去空/去空白）。
.PARAMETER OutFile
  输出文件路径。
.PARAMETER TimeoutSec
  单次下载超时秒数。
.PARAMETER MinSizeKB
  下载完成后的最小文件大小校验（防止下载到错误页面）。
.PARAMETER RaceSec
  并行测速时间（秒）。
.OUTPUTS
  [bool] 是否下载成功。
#>
function Save-WebFile {
  # 并行竞速 + 单线程下载：先用 Start-Job 对所有 URL 并行采样测速，选出最快的源，
  # 再用 Save-WebFileSingle（同步 I/O）从该源完成完整下载。
  # MinSizeKB 参数：下载完成后校验文件大小，小于此值视为无效（如代理返回错误页面）。
  param([string[]]$Urls, [string]$OutFile, [int]$TimeoutSec = 30, [int]$MinSizeKB = 0, [int]$RaceSec = 10)

  $urlList = @(
    $Urls |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  if ($urlList.Count -le 0) {
    Write-Warn "未提供下载地址"
    return $false
  }

  # 单地址直接下载，无需竞速
  if ($urlList.Count -eq 1) {
    $result = Save-WebFileSingle -Url $urlList[0] -OutFile $OutFile -TimeoutSec $TimeoutSec
    if ($result -and $MinSizeKB -gt 0) {
      $info = Get-Item -LiteralPath $OutFile -ErrorAction SilentlyContinue
      if ($info -and ($info.Length / 1KB) -lt $MinSizeKB) {
        Write-Warn "下载文件过小（{0:N0} KB < {1:N0} KB），可能为错误页面" -f ($info.Length / 1KB), $MinSizeKB
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        return $false
      }
    }
    return $result
  }

  Write-Host "  可下载的地址库：" -ForegroundColor Cyan
  for ($i = 0; $i -lt $urlList.Count; $i++) {
    Write-Host ("    {0}) {1}" -f ($i + 1), $urlList[$i]) -ForegroundColor Cyan
  }

  # ── 阶段一：并行测速 ──
  # 用 Start-Job 对每个 URL 起独立进程，下载约 256KB 采样测速
  Write-Host "  并行测速 ${RaceSec}s，选择最快源 ..." -ForegroundColor Cyan

  $timeoutMs = [Math]::Max($TimeoutSec, $RaceSec + 10) * 1000
  $jobs = @()
  foreach ($u in $urlList) {
    $job = Start-Job -ArgumentList $u, $RaceSec, $timeoutMs -ScriptBlock {
      param($url, $raceSec, $timeoutMs)
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Timeout = $timeoutMs
        $req.ReadWriteTimeout = $timeoutMs
        $req.UserAgent = 'PowerShell/Save-WebFile'
        $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $buf = New-Object byte[] 8192
        $total = 0L
        $maxBytes = 256KB
        while ($total -lt $maxBytes -and $sw.Elapsed.TotalSeconds -lt $raceSec) {
          $n = $stream.Read($buf, 0, [Math]::Min($buf.Length, $maxBytes - $total))
          if ($n -le 0) { break }
          $total += $n
        }
        $stream.Close()
        $resp.Close()
        $sw.Stop()
        $elapsed = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        [PSCustomObject]@{ Url = $url; SpeedKBps = [int](($total / $elapsed) / 1KB); Error = '' }
      } catch {
        [PSCustomObject]@{ Url = $url; SpeedKBps = 0; Error = $_.Exception.Message }
      }
    }
    $jobs += $job
  }

  # 等待所有测速任务完成
  Wait-Job -Job $jobs -Timeout ($RaceSec + 15) | Out-Null

  # 显示测速结果
  Write-Host ""
  Write-Host "  测速结果：" -ForegroundColor Cyan
  $raceResults = @()
  foreach ($job in $jobs) {
    $result = Receive-Job -Job $job
    Remove-Job -Job $job -Force
    if (-not $result) { continue }
    try { $uri = [System.Uri]::new($result.Url); $shortName = $uri.Host } catch { $shortName = $result.Url }
    if ($result.Error) {
      Write-Host ("    {0} ✗" -f $shortName, $result.Error) -ForegroundColor Red
    } else {
      Write-Host ("    {0}  {1:N0} KB/s" -f $shortName, $result.SpeedKBps) -ForegroundColor Cyan
      $raceResults += $result
    }
  }

  if ($raceResults.Count -eq 0) {
    Write-Warn "所有下载源均失败"
    return $false
  }

  # 选出最快源
  $best = $raceResults | Sort-Object -Property SpeedKBps -Descending | Select-Object -First 1
  try { $uri = [System.Uri]::new($best.Url); $bestShortName = $uri.Host } catch { $bestShortName = $best.Url }
  Write-Host ""
  Write-Ok "选择最快源：$bestShortName（$($best.SpeedKBps) KB/s）"

  # ── 阶段二：用 Save-WebFileSingle 从最快源同步下载 ──
  $result = Save-WebFileSingle -Url $best.Url -OutFile $OutFile -TimeoutSec $TimeoutSec
  if (-not $result) { return $false }

  # 校验文件大小
  if ($MinSizeKB -gt 0) {
    $info = Get-Item -LiteralPath $OutFile -ErrorAction SilentlyContinue
    if (-not $info -or ($info.Length / 1KB) -lt $MinSizeKB) {
      $actualKB = if ($info) { [int]($info.Length / 1KB) } else { 0 }
      Write-Warn "下载文件过小（${actualKB} KB < ${MinSizeKB} KB），可能为错误页面"
      Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
      return $false
    }
  }

  return $true
}

# ─── C/C++ compiler detection ─────────────────────────────────────────────────
# MSYS2/MinGW 路径常量（Test-Gnu / Test-GnuAssembler 等共享使用）
$script:MsysRoot    = 'C:\msys64'
$script:MsysBash    = Join-Path $script:MsysRoot 'usr\bin\bash.exe'
$script:MingwBin     = Join-Path $script:MsysRoot 'mingw64\bin'
$script:MingwGccExe  = Join-Path $script:MingwBin 'gcc.exe'
$script:MingwAsExe   = Join-Path $script:MingwBin 'as.exe'

<#
.SYNOPSIS
  检测 MSVC cl.exe 是否可用（包含 vswhere 回退定位），找到后自动加入当前 PATH。
.OUTPUTS
  [bool]
.NOTES
  cl.exe 可能不在 PATH（例如仅装了 Build Tools），因此需要通过 vswhere 定位安装目录。
  检测到后会自动将所在目录加入当前进程 PATH，确保后续构建步骤可用。
#>
function Test-Msvc {
  $cl = Get-ExePath 'cl.exe'
  if (-not $cl) {
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
          $clItem = Get-ChildItem -LiteralPath $msvcDir -Recurse -Filter 'cl.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -eq 'x64' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
          if ($clItem) {
            $cl = $clItem.FullName
            Add-PathPrefix $clItem.Directory.FullName
          }
        }
      }
    }
  }
  if (-not $cl) { return $false }
  $info = (Invoke-NativeText -FilePath $cl | Select-Object -First 1)
  Write-Ok "MSVC cl.exe 已安装"
  Write-Host "    路径：$cl"
  if (-not [string]::IsNullOrWhiteSpace($info)) { Write-Host "    版本：$info" }
  return $true
}

<#
.SYNOPSIS
  检测 GNU 汇编器 as.exe（Rust GNU toolchain 的 dlltool/import lib 可能依赖）。
.OUTPUTS
  [bool]
.NOTES
  - 优先从 PATH 找 as.exe
  - 若 MSYS2 已安装且 mingw64\bin\as.exe 存在，会临时加入 PATH
#>
function Test-GnuAssembler {
  $as = Get-ExePath 'as.exe'
  if ($as) {
    Write-Ok "GNU 汇编器 as 已安装"
    Write-Host "    路径：$as"
    return $true
  }
  if (Test-Path -LiteralPath $script:MingwAsExe) {
    Add-PathPrefix $script:MingwBin
    Write-Ok "GNU 汇编器 as 已安装（已添加到 PATH）"
    Write-Host "    路径：$($script:MingwAsExe)"
    return $true
  }
  return $false
}

<#
.SYNOPSIS
  检测 GNU GCC 编译器（gcc.exe）及汇编器 as.exe 是否可用。
.OUTPUTS
  [bool]
.NOTES
  - 优先从 PATH 查找 gcc，若 MSYS2 已安装但未加入 PATH 会自动探测
  - 同时检查 g++ 和 as.exe，缺失时给出警告（不会自动安装）
#>
function Test-Gnu {
  $gcc = Get-ExePath 'gcc.exe'
  if (-not $gcc) {
    if (Test-Path -LiteralPath $script:MingwGccExe) {
      Add-PathPrefix $script:MingwBin
      $gcc = $script:MingwGccExe
    }
  }
  if (-not $gcc) { return $false }
  $info = (Invoke-NativeText -FilePath 'gcc' -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "GNU GCC 编译器已安装"
  Write-Host "    路径：$gcc"
  if (-not [string]::IsNullOrWhiteSpace($info)) { Write-Host "    版本：$info" }
  if (-not (Get-ExePath 'g++.exe')) { Write-Warn "GCC 已找到但 G++ 未找到，部分 C++ 依赖可能编译失败" }
  if (-not (Test-GnuAssembler)) { Write-Warn "GNU 汇编器 as.exe 未找到，Rust dlltool 可能失败" }
  return $true
}


<#
.SYNOPSIS
  检测 rustc/rustup 是否可用，并解析 toolchain host/版本信息。
.PARAMETER Quiet
  静默模式：不输出提示日志，仅返回 true/false 并设置脚本变量。
.OUTPUTS
  [bool]
.NOTES
  会写入 $script:RustcVersion / $script:RustcHost，供后续摘要展示使用。
#>
function Test-RustToolchain {
  param([switch]$Quiet)
  $rustc = Get-ExePath 'rustc.exe'
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

  $rustupVersion = ''
  $rustup = Get-ExePath 'rustup.exe'
  if ($rustup) {
    $rustupVersion = (Invoke-NativeText -FilePath 'rustup' -Arguments @('--version') | Select-Object -First 1)
  }

  if (-not $Quiet) {
    Write-Ok "Rust 工具链已安装"
    if ($rustupVersion) { Write-Host "    rustup：$rustupVersion" }
    if (-not [string]::IsNullOrWhiteSpace($script:RustcVersion)) { Write-Host "    rustc：$($script:RustcVersion)" }
    if (-not [string]::IsNullOrWhiteSpace($script:RustcHost)) { Write-Host "    toolchain：$($script:RustcHost)" }
  }
  return $true
}

# ─── Android SDK / NDK discovery ─────────────────────────────────────────────
<#
.SYNOPSIS
  获取 Android SDK 根目录候选列表（按优先级）。
.PARAMETER PreferredRoot
  显式指定的优先路径（通常来自脚本参数）。
.OUTPUTS
  [string[]] 候选路径列表（不保证存在）。
#>
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

<#
.SYNOPSIS
  解析可用的 ANDROID_HOME（存在且可 Resolve-Path）。
.PARAMETER PreferredRoot
  优先使用的 SDK 根目录（可为空）。
.OUTPUTS
  [string] SDK 根目录；不存在返回 $null。
#>
function Resolve-AndroidHome {
  param([string]$PreferredRoot)
  foreach ($p in (Get-AndroidSdkRootCandidate -PreferredRoot $PreferredRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) {
      return (Resolve-Path -LiteralPath $p).Path
    }
  }
  return $null
}

<#
.SYNOPSIS
  在候选 SDK 根目录中查找 sdkmanager.bat。
.PARAMETER PreferredRoot
  优先使用的 SDK 根目录（可为空）。
.OUTPUTS
  [string] sdkmanager.bat 的绝对路径；未找到返回 $null。
#>
function Find-SdkManager {
  param([string]$PreferredRoot)
  foreach ($r in (Get-AndroidSdkRootCandidate -PreferredRoot $PreferredRoot)) {
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    $p = Join-Path $r 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
  }
  return $null
}

<#
.SYNOPSIS
  根据 sdkmanager.bat 的路径反推出 SDK 根目录（ANDROID_HOME）。
.PARAMETER SdkManagerPath
  sdkmanager.bat 的绝对路径。
.OUTPUTS
  [string] SDK 根目录。
#>
function Get-AndroidHomeFromSdkManager([string]$SdkManagerPath) {
  $binDir = Split-Path -Parent $SdkManagerPath
  $latestDir = Split-Path -Parent $binDir
  $cmdlineDir = Split-Path -Parent $latestDir
  $sdkRoot = Split-Path -Parent $cmdlineDir
  return (Resolve-Path -LiteralPath $sdkRoot).Path
}

<#
.SYNOPSIS
  在 ANDROID_HOME 下定位 NDK（优先 ndk/<版本>，其次 ndk-bundle）。
.PARAMETER AndroidHome
  Android SDK 根目录。
.OUTPUTS
  [hashtable] 包含 Path/Version/Kind；未找到返回 $null。
#>
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

<#
.SYNOPSIS
  为每个 Rust Android 目标设置 CC/CXX/AR 环境变量，指向 Android NDK 的 LLVM 工具链。
.DESCRIPTION
  Rust 交叉编译时，cc-rs 通过 CC_<target>/CXX_<target>/AR_<target> 找编译器。
  不设置的话会回退到 host 端 gcc，编译 Android 目标必然失败。
  注：故意不把 NDK toolchain bin 加进 PATH，避免覆盖 host 链接器。
.PARAMETER AndroidNdkHome
  Android NDK 根目录（含 toolchains\llvm\prebuilt\windows-x86_64\bin）。
.PARAMETER ApiLevel
  Android API 级别（决定 clang 文件名后缀，如 21 → aarch64-linux-android21-clang.cmd）。默认 21。
#>
function Set-AndroidNdkEnv {
  param(
    [Parameter(Mandatory)] [string]$AndroidNdkHome,
    [int]$ApiLevel = 21
  )

  if ([string]::IsNullOrWhiteSpace($AndroidNdkHome)) {
    Write-Warn "ANDROID_NDK_HOME 为空，跳过 NDK 环境变量配置"
    return
  }

  $toolchainBin = Join-Path $AndroidNdkHome 'toolchains\llvm\prebuilt\windows-x86_64\bin'
  if (-not (Test-Path -LiteralPath $toolchainBin)) {
    Write-Warn "NDK toolchain 目录未找到：$toolchainBin"
    Write-Warn "将使用系统默认编译器"
    return
  }

  $llvmAr = Join-Path $toolchainBin 'llvm-ar.exe'
  foreach ($t in (Get-AndroidRustTarget)) {
    $underscore = $t -replace '-', '_'
    Set-Item -Path "env:CC_$underscore"  -Value (Join-Path $toolchainBin "${t}${ApiLevel}-clang.cmd")
    Set-Item -Path "env:CXX_$underscore" -Value (Join-Path $toolchainBin "${t}${ApiLevel}-clang++.cmd")
    Set-Item -Path "env:AR_$underscore"  -Value $llvmAr
  }
  Write-Ok "NDK clang/clang++/llvm-ar 已配置（CC/CXX/AR_<target>）：$toolchainBin"
}

<#
.SYNOPSIS
  将 gradle-wrapper.properties 的 distributionUrl 替换为国内镜像源。
.PARAMETER GenAndroidDir
  gen\android 目录路径。
.NOTES
  每次 pnpm tauri android init 会重置为官方 URL，需在 init 之后调用。
#>
function Set-GradleWrapperMirror {
  param([Parameter(Mandatory)][string]$GenAndroidDir)

  $wrapperProps = Join-Path $GenAndroidDir 'gradle\wrapper\gradle-wrapper.properties'
  if (-not (Test-Path -LiteralPath $wrapperProps)) { return }

  $content = Get-Content -LiteralPath $wrapperProps -Raw
  if ($content -match 'mirrors\.cloud\.tencent\.com') { return }

  $content = $content -replace 'https\\://services\.gradle\.org/distributions/', 'https\://mirrors.cloud.tencent.com/gradle/'
  [System.IO.File]::WriteAllText($wrapperProps, $content, [System.Text.UTF8Encoding]::new($false))
  Write-Ok "gradle-wrapper.properties 已切换为腾讯云镜像 ($wrapperProps)"
}

<#
.SYNOPSIS
  获取当前 java 的主版本号（如 17）。
.OUTPUTS
  [int] 主版本号；未找到 java 时返回 $null。
#>
function Get-JavaMajorVersion {
  if ($null -eq (Get-ExePath 'java.exe')) { return $null }
  $line = (Invoke-NativeText -FilePath 'java' -Arguments @('-version') | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($line)) { return $null }
  $m = [regex]::Match($line, '([0-9]+)')
  if (-not $m.Success) { return $null }
  return [int]$m.Groups[1].Value
}

<#
.SYNOPSIS
  断言 Java 版本 >= 17（Android/Tauri 构建所需）。
.OUTPUTS
  [bool] 满足返回 $true；不满足会输出失败提示并返回 $false。
.NOTES
  本函数只负责校验与输出；是否 exit 由调用脚本决定。
#>
function Assert-Java17 {
  # 检查 Java >= 17。OK 时 Write-Ok 并返回 $true；不满足时 Write-Fail 两条提示并返回 $false。
  # 由调用方决定是 exit 1 还是仅累积 $Failed。
  $ver = Get-JavaMajorVersion
  $hint = '请从 https://adoptium.net/ 下载 JDK 17+，或运行：winget install EclipseAdoptium.Temurin.17.JDK'
  if ($null -eq $ver) {
    Write-Fail "未找到 Java，需要 JDK 17+"
    Write-Fail $hint
    return $false
  }
  if ($ver -lt 17) {
    Write-Fail "检测到 Java $ver，但需要 JDK 17+"
    Write-Fail $hint
    return $false
  }
  Write-Ok "Java $ver 已安装：$(Get-ExePath 'java.exe')"
  return $true
}

# ─── Misc helpers ────────────────────────────────────────────────────────────
<#
.SYNOPSIS
  从类似 properties 的文本行数组里读取 key=value 的 value（自动去引号）。
.PARAMETER Lines
  文本行数组。
.PARAMETER Key
  键名。
.OUTPUTS
  [string] value；不存在返回空字符串。
#>
function Get-PropValue {
  param([string[]]$Lines, [string]$Key)
  $line = $Lines | Where-Object { $_ -match ('^' + [regex]::Escape($Key) + '\s*=') } | Select-Object -First 1
  if (-not $line) { return '' }
  return ($line -replace ('^' + [regex]::Escape($Key) + '\s*=\s*'), '').Trim().Trim('"').Trim("'")
}
