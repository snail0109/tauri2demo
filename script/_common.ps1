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

function Exit-NoOp {
  # 用户在菜单或确认提示中选择放弃时的统一退出：黄字提示 + exit。
  # remove_*.ps1 的"菜单选 0 / Confirm-Remove 拒绝"以及 install_c_compile 的"菜单选 0"共用。
  param([string]$Message, [int]$Code = 0)
  Write-Host ""
  Write-Host "  $Message" -ForegroundColor Yellow
  exit $Code
}

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

function Invoke-NativeStreamIn {
  # 在 $Path 目录下运行 $Block；总是恢复 cwd，即便 native 命令出错也不残留。
  param([string]$Path, [scriptblock]$Block)
  Push-Location $Path
  try { Invoke-NativeStream -Block $Block } finally { Pop-Location }
}

# ─── Rustup helpers ──────────────────────────────────────────────────────────
function Get-RustupInstalledTarget {
  # 已安装的 Rust 编译目标列表（string[]）。rustup 不存在时返回空数组。
  if (-not (Get-ExePath 'rustup.exe')) { return @() }
  return @(Invoke-NativeText -FilePath 'rustup' -Arguments @('target', 'list', '--installed') |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-AndroidRustTarget {
  # Tauri Android 构建所需的 4 个 Rust 编译目标。install / remove / build 共用。
  return @(
    'aarch64-linux-android',
    'armv7-linux-androideabi',
    'i686-linux-android',
    'x86_64-linux-android'
  )
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

function Save-WebFile {
  # 并发竞速下载：先同时启动所有 URL 连接，RaceSec（默认 30）秒后保留速度最快的一个继续下载。
  # MinSizeKB 参数：下载完成后校验文件大小，小于此值视为无效（如代理返回错误页面）。
  param([string[]]$Urls, [string]$OutFile, [int]$TimeoutSec = 30, [int]$MinSizeKB = 0, [int]$RaceSec = 5)

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
    return (Save-WebFileSingle -Url $urlList[0] -OutFile $OutFile -TimeoutSec $TimeoutSec)
  }

  Write-Host "  可下载的地址库：" -ForegroundColor Cyan
  for ($i = 0; $i -lt $urlList.Count; $i++) {
    Write-Host ("    {0}) {1}" -f ($i + 1), $urlList[$i]) -ForegroundColor Cyan
  }

  # ── 竞速阶段：并发连接 + 读取，统一计时 ──
  Write-Host "  并发竞速 ${RaceSec}s，选择最快源 ..." -ForegroundColor Cyan

  # 为每个 URL 创建下载上下文
  $contexts = @()
  foreach ($u in $urlList) {
    $ctx = @{
      Url           = $u
      Response      = $null
      Stream        = $null
      Writer        = $null
      TmpFile       = Join-Path $env:TEMP "SaveWebFile_race_$([guid]::NewGuid().ToString('N')).tmp"
      Bytes         = 0L
      ContentLength = -1L
      Error         = $null
      Done          = $false
      Connected     = $false
    }
    $contexts += $ctx
  }

  # 并发发起所有 HTTP 请求
  foreach ($ctx in $contexts) {
    try {
      $req = [System.Net.HttpWebRequest]::Create($ctx.Url)
      $req.Timeout = [Math]::Max($RaceSec, $TimeoutSec) * 1000
      $req.ReadWriteTimeout = $TimeoutSec * 1000
      $req.UserAgent = 'PowerShell/Save-WebFile'
      $req.AllowAutoRedirect = $true
      $ctx.AsyncResult = $req.BeginGetResponse($null, $null)
      $ctx['_Request'] = $req
    }
    catch {
      $ctx.Error = $_.Exception.Message
      $ctx.Done = $true
    }
  }

  # 统一竞速循环：连接建立 + 异步读取，总时间不超过 RaceSec
  $raceSw = [System.Diagnostics.Stopwatch]::StartNew()
  $lastDisplay = 0L
  while ($raceSw.ElapsedMilliseconds -lt ($RaceSec * 1000)) {
    $anyActive = $false

    foreach ($ctx in $contexts) {
      if ($ctx.Done) { continue }

      # 尚未连接：检查连接是否完成
      if (-not $ctx.Connected) {
        $anyActive = $true
        if ($ctx.AsyncResult.AsyncWaitHandle.WaitOne(0)) {
          try {
            $req = $ctx['_Request']
            $resp = $req.EndGetResponse($ctx.AsyncResult)
            $ctx.Response = $resp
            $ctx.ContentLength = $resp.ContentLength
            $ctx.Stream = $resp.GetResponseStream()
            $ctx.Writer = [System.IO.File]::Create($ctx.TmpFile)
            $ctx.Connected = $true
            # 立即发起第一次异步读取
            $ctx['_Buf'] = New-Object byte[] 81920
            $ctx['_AsyncRead'] = $ctx.Stream.BeginRead($ctx['_Buf'], 0, $ctx['_Buf'].Length, $null, $null)
          }
          catch {
            $ctx.Error = $_.Exception.Message
            $ctx.Done = $true
          }
        }
        continue
      }

      # 已连接：检查异步读取是否完成
      $anyActive = $true
      if ($null -ne $ctx['_AsyncRead'] -and $ctx['_AsyncRead'].IsCompleted) {
        try {
          $n = $ctx.Stream.EndRead($ctx['_AsyncRead'])
          if ($n -gt 0) {
            $ctx.Writer.Write($ctx['_Buf'], 0, $n)
            $ctx.Bytes += $n
            $ctx['_AsyncRead'] = $ctx.Stream.BeginRead($ctx['_Buf'], 0, $ctx['_Buf'].Length, $null, $null)
          } else {
            $ctx.Done = $true
            $ctx['_AsyncRead'] = $null
          }
        }
        catch {
          $ctx.Error = $_.Exception.Message
          $ctx.Done = $true
          $ctx['_AsyncRead'] = $null
        }
      }
    }

    if (-not $anyActive) { break }

    # 每 2 秒刷新一次竞速进度
    $now = $raceSw.ElapsedMilliseconds
    if ($now - $lastDisplay -ge 2000) {
      $lastDisplay = $now
      $elapsed = [Math]::Max($raceSw.Elapsed.TotalSeconds, 0.001)
      $parts = @()
      foreach ($ctx in $contexts) {
        try {
          $uri = [System.Uri]::new($ctx.Url)
          $shortName = $uri.Host
        } catch { $shortName = $ctx.Url }
        if ($ctx.Error) {
          $parts += "${shortName}: ✗"
        } elseif (-not $ctx.Connected) {
          $parts += "${shortName}: ..."
        } else {
          $spd = [int](($ctx.Bytes / $elapsed) / 1KB)
          $parts += "${shortName}: ${spd}KB/s"
        }
      }
      $raceDisplay = "    [{0:N0}s] {1}   " -f ([int]$raceSw.Elapsed.TotalSeconds), ($parts -join ' | ')
      [Console]::Write("`r$raceDisplay")
    }

    Start-Sleep -Milliseconds 50
  }

  # 超时未连接的标记失败
  foreach ($ctx in $contexts) {
    if ($ctx.Done -or $ctx.Connected) { continue }
    $ctx.Error = '连接超时'
    $ctx.Done = $true
    try { $ctx['_Request'].Abort() } catch {}
  }

  # 显示竞速结果
  Write-Host ""
  Write-Host "  竞速结果：" -ForegroundColor Cyan
  $elapsed = [Math]::Max($raceSw.Elapsed.TotalSeconds, 0.001)
  foreach ($ctx in $contexts) {
    try {
      $uri = [System.Uri]::new($ctx.Url)
      $shortName = $uri.Host
    } catch { $shortName = $ctx.Url }
    if ($ctx.Error) {
      Write-Host ("    {0} ✗ " -f $shortName) -ForegroundColor Red
    } else {
      $spdKB = [int](($ctx.Bytes / $elapsed) / 1KB)
      Write-Host ("    {0}  {1:N0} KB  {2:N0} KB/s" -f $shortName, ($ctx.Bytes / 1KB), $spdKB) -ForegroundColor Cyan
    }3
  }

  # 选择最快的有效源（按已下载字节数排序）
  $best = $contexts |
    Where-Object { -not $_.Error -and $_.Bytes -gt 0 } |
    Sort-Object -Property Bytes -Descending |
    Select-Object -First 1

  # 关闭并清理非最佳源
  foreach ($ctx in $contexts) {
    if ($ctx -eq $best) { continue }
    if ($ctx.Writer) { try { $ctx.Writer.Close() } catch {} }
    if ($ctx.Stream) { try { $ctx.Stream.Close() } catch {} }
    if ($ctx.Response) { try { $ctx.Response.Close() } catch {} }
    if ($ctx.TmpFile) { Remove-Item -LiteralPath $ctx.TmpFile -Force -ErrorAction SilentlyContinue }
  }

  if (-not $best) {
    Write-Warn "所有下载源均失败"
    return $false
  }

  try {
    $uri = [System.Uri]::new($best.Url)
    $bestShortName = $uri.Host
  } catch { $bestShortName = $best.Url }
  $bestSpdKB = [int](($best.Bytes / $elapsed) / 1KB)
  Write-Host ""
  Write-Ok "选择最快源：$bestShortName（${bestSpdKB} KB/s），继续下载 ..."

  # ── 阶段二：在最快源的连接上继续下载 ──
  # 最快源的 Stream/Writer/Response 保持打开，继续异步读取直到完成
  $total = $best.ContentLength
  $alreadyBytes = $best.Bytes
  [long]$read = $alreadyBytes
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $lastReport = 0L
  $lastLineLen = 0

  # 如果竞速阶段结束时还有未完成的异步读取，先处理它
  if ($null -ne $best['_AsyncRead']) {
    try {
      if ($best['_AsyncRead'].IsCompleted) {
        $n = $best.Stream.EndRead($best['_AsyncRead'])
        if ($n -gt 0) {
          $best.Writer.Write($best['_Buf'], 0, $n)
          $read += $n
        }
      }
      else {
        # 等待当前异步读取完成
        $n = $best.Stream.EndRead($best['_AsyncRead'])
        if ($n -gt 0) {
          $best.Writer.Write($best['_Buf'], 0, $n)
          $read += $n
        }
      }
    }
    catch {
      # 当前读取失败，尝试继续
    }
  }

  # 继续异步读取循环直到下载完成
  $buf = New-Object byte[] 81920
  $asyncRead = $null
  try {
    $asyncRead = $best.Stream.BeginRead($buf, 0, $buf.Length, $null, $null)
  }
  catch {
    # 如果无法发起新读取，检查是否已经下载完成
    if ($best.Done) {
      # 已完成，跳到后续处理
      $asyncRead = $null
    } else {
      Write-Warn "继续下载失败：$($_.Exception.Message)"
      if ($best.Writer) { try { $best.Writer.Close() } catch {} }
      if ($best.Stream) { try { $best.Stream.Close() } catch {} }
      if ($best.Response) { try { $best.Response.Close() } catch {} }
      Remove-Item -LiteralPath $best.TmpFile -Force -ErrorAction SilentlyContinue
      return $false
    }
  }

  while ($null -ne $asyncRead) {
    # 等待异步读取完成
    while (-not $asyncRead.IsCompleted) {
      $now = $sw.ElapsedMilliseconds
      if ($now - $lastReport -ge 200) {
        $lastReport = $now
        $sec = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $speedKB = ($read / $sec) / 1KB
        if ($total -gt 0) {
          $pct = [int]($read / $total * 100)
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
      Start-Sleep -Milliseconds 50
    }

    try {
      $n = $best.Stream.EndRead($asyncRead)
      if ($n -gt 0) {
        $best.Writer.Write($buf, 0, $n)
        $read += $n
        # 发起下一次异步读取
        $asyncRead = $best.Stream.BeginRead($buf, 0, $buf.Length, $null, $null)
      } else {
        # 下载完成
        $asyncRead = $null
      }
    }
    catch {
      # 读取错误，终止
      $asyncRead = $null
    }
  }

  # 刷新进度行
  [Console]::Write("`r" + (' ' * $lastLineLen) + "`r")

  # 关闭最快源的连接
  if ($best.Writer) { try { $best.Writer.Close() } catch {} }
  if ($best.Stream) { try { $best.Stream.Close() } catch {} }
  if ($best.Response) { try { $best.Response.Close() } catch {} }

  $sw.Stop()
  $sec = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
  $avgKB = ($read / $sec) / 1KB
  Write-Ok ("下载完成（{0:N0} KB，{1:N0} KB/s，来源：{2}）" -f ($read/1KB), $avgKB, $bestShortName)

  # 校验文件大小
  if ($MinSizeKB -gt 0 -and ($read / 1KB) -lt $MinSizeKB) {
    Write-Warn "下载文件过小（{0:N0} KB < {1:N0} KB），可能为错误页面" -f ($read/1KB), $MinSizeKB
    Remove-Item -LiteralPath $best.TmpFile -Force -ErrorAction SilentlyContinue
    return $false
  }

  # 将竞速临时文件移动到最终输出路径
  try {
    Move-Item -LiteralPath $best.TmpFile -Destination $OutFile -Force -ErrorAction Stop
  }
  catch {
    Write-Warn "移动临时文件失败：$($_.Exception.Message)"
    Remove-Item -LiteralPath $best.TmpFile -Force -ErrorAction SilentlyContinue
    return $false
  }

  return $true
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
function Get-PropValue {
  param([string[]]$Lines, [string]$Key)
  $line = $Lines | Where-Object { $_ -match ('^' + [regex]::Escape($Key) + '\s*=') } | Select-Object -First 1
  if (-not $line) { return '' }
  return ($line -replace ('^' + [regex]::Escape($Key) + '\s*=\s*'), '').Trim().Trim('"').Trim("'")
}
