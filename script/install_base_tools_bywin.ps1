param(
  [Alias('y')]
  [switch]$Yes,

  [string[]]$AddTools,

  [string[]]$RemoveTools
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

# ─── 工具注册表 ───────────────────────────────────────────────────────────────
# 每个工具：Id（参数名）、Name（显示名）、Description
$ToolDefs = @(
  @{ Id = 'winget'; Name = 'winget'; Description = 'Windows 包管理器' },
  @{ Id = 'terminal'; Name = 'Windows 终端'; Description = 'Windows Terminal（多标签终端）' }
)

# ─── winget ───────────────────────────────────────────────────────────────────


function Test-Winget {
  $winget = Get-ExePath 'winget.exe'
  if (-not $winget) { return $false }
  $ver = (Invoke-NativeText -FilePath $winget -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "winget 已安装"
  Write-Host "    路径：$winget"
  if (-not [string]::IsNullOrWhiteSpace($ver)) { Write-Host "    版本：$ver" }
  return $true
}


function Add-WingetMirrorSource {
  $winget = Get-ExePath 'winget.exe'
  if (-not $winget) { return }

  # 获取 winget 版本号
  $ver = $null
  try {
    $verStr = (Invoke-NativeText -FilePath $winget -Arguments @('--version') | Select-Object -First 1).Trim()
    $ver = [version]::new($verStr.Substring(0, [Math]::Min($verStr.Length, 10 - 1))) # 取前缀避免多余字符
  }
  catch {
    $ver = $null
  }

  # 检查是否已存在同名源
  $sourceList = $null
  try {
    $sourceList = Invoke-NativeText -FilePath $winget -Arguments @('source', 'list')
  }
  catch {
    $sourceList = ''
  }

  $mirrorUrl = 'https://mirrors.ustc.edu.cn/winget-source'
  $alreadyHas = $false
  if ($sourceList) {
    $alreadyHas = ($sourceList | Where-Object { $_ -match 'winget' -and $_ -match [regex]::Escape($mirrorUrl) }) -ne $null
  }

  if ($alreadyHas) {
    Write-Ok "winget 国内镜像源已配置（ustc）"
    return
  }

  Write-Host "  配置 winget 国内镜像源（ustc）..." -ForegroundColor Cyan

  # 移除 msstore 源（证书验证问题，且开发者通常不需要）
  if ($sourceList -and ($sourceList | Where-Object { $_ -match 'msstore' })) {
    try {
      Invoke-NativeStream -Block { & $winget source remove msstore }
      Write-Ok "已移除 msstore 源（避免证书验证报错）"
    }
    catch {
      Write-Warn "移除 msstore 源失败：$($_.Exception.Message)"
    }
  }

  # 如果已有默认 winget 源，先移除再添加镜像源
  if ($sourceList -and ($sourceList | Where-Object { $_ -match 'winget\s' })) {
    try {
      Invoke-NativeStream -Block { & $winget source remove winget }
    }
    catch {
      Write-Warn "移除默认 winget 源失败：$($_.Exception.Message)"
    }
  }

  # WinGet 1.8+ 支持 --trust-level 参数
  if ($ver -and $ver -ge [version]'1.8') {
    try {
      Invoke-NativeStream -Block { & $winget source add winget $mirrorUrl --trust-level trusted }
      Write-Ok "winget 国内镜像源配置成功（ustc，trust-level trusted）"
    }
    catch {
      Write-Warn "配置镜像源失败：$($_.Exception.Message)"
    }
  }
  else {
    try {
      Invoke-NativeStream -Block { & $winget source add winget $mirrorUrl }
      Write-Ok "winget 国内镜像源配置成功（ustc）"
    }
    catch {
      Write-Warn "配置镜像源失败：$($_.Exception.Message)"
    }
  }
}

function Install-WingetTool {
  Write-Host ""
  Write-Host "═══ 安装 winget ═══" -ForegroundColor Cyan
  Write-Host ""

  if (Test-Winget) {
    Write-Host ""
    Add-WingetMirrorSource
    return $true
  }

  Write-Host "  ✗ 未检测到 winget" -ForegroundColor Red
  Write-Host ""

  if (-not (Confirm-Install "安装 winget（Windows 包管理器）")) { return $false }

  Write-Host "  安装 winget ..." -ForegroundColor Cyan
  try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ForceApplicationShutdown -ErrorAction Stop
    Write-Ok "winget 安装成功"
  }
  catch {
    Write-Fail "winget 安装失败：$($_.Exception.Message)"
    Write-Fail "请手动安装 winget："
    Write-Fail "  • 运行：Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ForceApplicationShutdown"
    Write-Fail "  • 或打开 Microsoft Store 搜索「应用安装程序」并安装/更新"
    return $false
  }

  Write-Host ""
  if (Test-Winget) {
    Add-WingetMirrorSource
    Write-Banner -Title 'winget 安装成功' -Color Green
    return $true
  }
  Write-Warn "winget 安装流程已执行，但当前 shell 未检测到 winget"
  Write-Warn "请重新打开终端后再次运行此脚本验证"
  return $false
}

function Uninstall-WingetTool {
  Write-Host ""
  Write-Host "═══ 禁用 winget ═══" -ForegroundColor Cyan
  Write-Host ""

  # 查找 winget 命令
  $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $wingetCmd) {
    Write-Host ""
    Write-Banner -Title 'winget 未安装或已被禁用' -Color Green
    return $true
  }

  Write-Host "  找到 winget: $($wingetCmd.Source)" -ForegroundColor White
  Write-Host ""

  if (-not (Confirm-Continue "确认禁用 winget（通过重命名 winget.exe 为 .bak）")) { return $false }

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
    Write-Warn "未找到 winget.exe 文件"
    return $false
  }

  Write-Host "  找到以下 winget.exe 文件:" -ForegroundColor Cyan
  foreach ($t in $targets) {
    Write-Host "    $t"
  }
  Write-Host ""

  $success = $true
  foreach ($exe in $targets) {
    Write-Host "  处理: $exe" -ForegroundColor Cyan

    # 第1步: 获取父目录所有权
    $dir = Split-Path $exe
    Write-Host "    获取目录所有权..." -NoNewline
    try {
      $null = & takeown /f $dir /r /d Y 2>&1
      Write-Host " 完成" -ForegroundColor Green
    }
    catch {
      Write-Host " 失败" -ForegroundColor Red
      $success = $false
      continue
    }

    # 第2步: 授予管理员完全控制权限
    Write-Host "    设置权限..." -NoNewline
    try {
      $null = & icacls $dir /grant "Administrators:(OI)(CI)F" /t /c 2>&1
      Write-Host " 完成" -ForegroundColor Green
    }
    catch {
      Write-Host " 失败" -ForegroundColor Red
      $success = $false
      continue
    }

    # 第3步: 重命名
    Write-Host "    重命名 winget.exe -> winget.exe.bak ..." -NoNewline
    try {
      Rename-Item -Path $exe -NewName "winget.exe.bak" -Force -ErrorAction Stop
      Write-Host " 完成" -ForegroundColor Green
    }
    catch {
      Write-Host ""
      Write-Warn "    重命名失败: $($_.Exception.Message)"
      Write-Host "    尝试替代方案: 用空文件覆盖..." -NoNewline
      try {
        [System.IO.File]::WriteAllBytes($exe, @())
        Write-Host " 完成" -ForegroundColor Green
      }
      catch {
        Write-Host " 失败" -ForegroundColor Red
        Write-Warn "    替代方案也失败: $($_.Exception.Message)"
        $success = $false
      }
    }
  }

  Write-Host ""
  # 验证
  $check = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $check) {
    Write-Banner -Title 'winget 已成功禁用' -Color Green
    Write-Host "  恢复方法: 将 winget.exe.bak 重命名回 winget.exe" -ForegroundColor DarkGray
    return $true
  }
  else {
    Write-Warn "winget 仍然可用: $($check.Source)"
    Write-Warn "可能需要重启后生效，或存在其他副本"
    return $false
  }
}

# ─── Windows 终端 ─────────────────────────────────────────────────────────────

function Test-WindowsTerminal {
  $wt = Get-ExePath 'wt.exe'
  if (-not $wt) {
    $localWt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path -LiteralPath $localWt) { $wt = $localWt }
  }
  if (-not $wt) { return $false }
  $ver = (Invoke-NativeText -FilePath $wt -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "Windows 终端 已安装"
  Write-Host "    路径：$wt"
  if (-not [string]::IsNullOrWhiteSpace($ver)) { Write-Host "    版本：$ver" }
  return $true
}

function Install-WindowsTerminalTool {
  Write-Host ""
  Write-Host "═══ 安装 Windows 终端 ═══" -ForegroundColor Cyan
  Write-Host ""

  if (Test-WindowsTerminal) {
    Write-Host ""
    Write-Banner -Title 'Windows 终端 已就绪' -Color Green
    return $true
  }

  Write-Host "  ✗ 未检测到 Windows 终端" -ForegroundColor Red
  Write-Host ""

  if (-not (Confirm-Install "安装 Windows 终端")) { return $false }

  $installed = $false

  # 方式一：通过 winget 安装
  if (Get-ExePath 'winget.exe') {
    Write-Host "  通过 winget 安装 Windows 终端 ..." -ForegroundColor Cyan
    try {
      Invoke-NativeStream -Block { & winget install --id Microsoft.WindowsTerminal --source winget --accept-package-agreements --accept-source-agreements }
      $installed = $true
    }
    catch {
      Write-Fail "winget 安装失败：$($_.Exception.Message)"
    }
    if ($installed -and -not (Test-WindowsTerminal)) {
      Write-Warn "winget 报告成功但未检测到 wt.exe"
      $installed = $false
    }
  }

  # 方式二：从 GitHub releases 下载 .msixbundle 安装
  if (-not $installed) {
    Write-Host "  下载 Windows 终端安装包 ..." -ForegroundColor Cyan
    $wtInstaller = Join-Path $env:TEMP ("WindowsTerminal_{0}.msixbundle" -f ([guid]::NewGuid().ToString('N')))
    try {
      $releaseApiUrl = 'https://api.github.com/repos/microsoft/terminal/releases/latest'
      $downloadUrl = $null
      try {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $release = Invoke-RestMethod -Uri $releaseApiUrl -TimeoutSec 15
        $asset = $release.assets | Where-Object { $_.name -like '*_x64.msixbundle' } | Select-Object -First 1
        if ($asset) { $downloadUrl = $asset.browser_download_url }
        $ErrorActionPreference = $prev
      }
      catch {
        Write-Warn "无法获取 Windows 终端最新版下载地址，使用固定版本 ..."
      }

      $urls = @()
      if ($downloadUrl) { $urls += $downloadUrl }
      $urls += 'https://github.com/microsoft/terminal/releases/download/v1.25.923.0/Microsoft.WindowsTerminalPreview_1.25.923.0_x64.zip'
      if (Save-WebFile -Urls $urls -OutFile $wtInstaller -TimeoutSec 120) {
        try {
          Add-AppxPackage -Path $wtInstaller -ErrorAction Stop
          Write-Ok "Windows 终端安装成功"
          $installed = $true
        }
        catch {
          Write-Fail "Windows 终端安装失败：$($_.Exception.Message)"
        }
      }
      else {
        Write-Fail "下载 Windows 终端安装包失败"
      }
    }
    finally {
      Remove-Item -LiteralPath $wtInstaller -Force -ErrorAction SilentlyContinue
    }
  }

  # 方式三：打开 Microsoft Store
  if (-not $installed) {
    Write-Host "  尝试从 Microsoft Store 安装 ..." -ForegroundColor Cyan
    try {
      Start-Process 'ms-windows-store://pdp/?ProductId=9n0dx20hk701'
      Write-Warn "已打开 Microsoft Store 页面，请在 Store 中点击「安装」"
      Write-Warn "安装完成后按 Enter 继续 ..."
      Read-Host
      $installed = Test-WindowsTerminal
    }
    catch {
      Write-Warn "无法打开 Microsoft Store：$($_.Exception.Message)"
    }
  }

  Write-Host ""
  if (Test-WindowsTerminal) {
    Write-Banner -Title 'Windows 终端 安装成功' -Color Green
    return $true
  }
  if ($installed) {
    Write-Warn "Windows 终端安装流程已执行，但当前 shell 未检测到 wt.exe"
    Write-Warn "请重新打开终端后再次运行此脚本验证"
    return $false
  }
  Write-Fail "Windows 终端自动安装失败"
  Write-Fail "请手动安装 Windows 终端："
  Write-Fail "  • 打开 Microsoft Store 搜索「Windows 终端」并安装"
  Write-Fail "  • 或访问 https://github.com/microsoft/terminal/releases 下载安装"
  return $false
}

function Uninstall-WindowsTerminalTool {
  Write-Host ""
  Write-Host "═══ 卸载 Windows 终端 ═══" -ForegroundColor Cyan
  Write-Host ""

  if (-not (Test-WindowsTerminal)) {
    Write-Host ""
    Write-Banner -Title 'Windows 终端 未安装，无需卸载' -Color Green
    return $true
  }

  Write-Host ""
  if (-not (Confirm-Continue "确认卸载 Windows 终端")) { return $false }

  $uninstalled = $false

  # 方式一：通过 Remove-AppxPackage 卸载
  $wtPackage = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -ErrorAction SilentlyContinue
  if ($wtPackage) {
    Write-Host "  通过 Remove-AppxPackage 卸载 Windows 终端 ..." -ForegroundColor Cyan
    try {
      Remove-AppxPackage -Package $wtPackage.PackageFullName -ErrorAction Stop
      Write-Ok "Windows 终端已卸载"
      $uninstalled = $true
    }
    catch {
      Write-Warn "Remove-AppxPackage 卸载失败：$($_.Exception.Message)"
    }
  }

  # 方式二：通过 winget 卸载
  if (-not $uninstalled -and (Get-ExePath 'winget.exe')) {
    Write-Host "  通过 winget 卸载 Windows 终端 ..." -ForegroundColor Cyan
    try {
      Invoke-NativeStream -Block { & winget uninstall --id Microsoft.WindowsTerminal --source winget --accept-source-agreements }
      $uninstalled = $true
    }
    catch {
      Write-Fail "winget 卸载失败：$($_.Exception.Message)"
    }
  }

  # 方式三：打开 Microsoft Store 卸载
  if (-not $uninstalled) {
    Write-Host "  尝试通过 Microsoft Store 卸载 ..." -ForegroundColor Cyan
    try {
      Start-Process 'ms-windows-store://pdp/?ProductId=9n0dx20hk701'
      Write-Warn "已打开 Microsoft Store 页面，请在 Store 中点击「卸载」"
      Write-Warn "卸载完成后按 Enter 继续 ..."
      Read-Host
      $uninstalled = -not (Test-WindowsTerminal)
    }
    catch {
      Write-Warn "无法打开 Microsoft Store：$($_.Exception.Message)"
    }
  }

  Write-Host ""
  if (-not (Test-WindowsTerminal)) {
    Write-Banner -Title 'Windows 终端 卸载成功' -Color Green
    return $true
  }
  if ($uninstalled) {
    Write-Warn "Windows 终端卸载流程已执行，但当前 shell 仍检测到 wt.exe"
    Write-Warn "请重新打开终端后再次运行此脚本验证"
    return $false
  }
  Write-Fail "Windows 终端自动卸载失败"
  Write-Fail "请手动卸载 Windows 终端："
  Write-Fail "  • 打开 Microsoft Store 搜索「Windows 终端」并卸载"
  Write-Fail "  • 或在「设置 → 应用」中找到「Windows 终端」并卸载"
  Write-Fail "  • 或运行：Get-AppxPackage Microsoft.WindowsTerminal | Remove-AppxPackage"
  return $false
}

# ─── 工具调度 ─────────────────────────────────────────────────────────────────

# Id → Install 函数 的映射
$ToolInstallers = @{
  'winget'   = ${function:Install-WingetTool}
  'terminal' = ${function:Install-WindowsTerminalTool}
}

# Id → Uninstall 函数 的映射
$ToolUninstallers = @{
  'winget'   = ${function:Uninstall-WingetTool}
  'terminal' = ${function:Uninstall-WindowsTerminalTool}
}

function Write-Usage {
  Write-Host ""
  Write-Banner -Title '基础工具管理（Windows）    ' -Color Cyan
  Write-Host ""
  Write-Host "用法：" -ForegroundColor Cyan
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools <工具1,工具2,...>     安装指定工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools all                  安装所有工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -y -AddTools all               静默安装所有工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -RemoveTools <工具1,工具2,...>  卸载指定工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -RemoveTools all               卸载所有工具"
  Write-Host ""
  Write-Host "可用工具：" -ForegroundColor Cyan
  foreach ($t in $ToolDefs) {
    Write-Host ("  {0,-10} {1}" -f $t.Id, $t.Description)
  }
  Write-Host ""
  Write-Host "示例：" -ForegroundColor Cyan
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget,terminal"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools all"
  Write-Host "  .\install_base_tools_bywin.ps1 -RemoveTools winget"
  Write-Host "  .\install_base_tools_bywin.ps1 -RemoveTools winget,terminal"
  Write-Host "  .\install_base_tools_bywin.ps1 -RemoveTools all"
  Write-Host ""
}

# ─── 主流程 ───────────────────────────────────────────────────────────────────

if ((-not $AddTools -or $AddTools.Count -eq 0) -and (-not $RemoveTools -or $RemoveTools.Count -eq 0)) {
  Write-Usage
  exit 0
}

# 展开别名：all → 所有工具 Id
$validIds = $ToolDefs | ForEach-Object { $_.Id }

# 校验 -AddTools 参数
if ($AddTools -and $AddTools.Count -gt 0) {
  if ($AddTools -contains 'all') {
    $AddTools = @($validIds)
  }
  $unknown = $AddTools | Where-Object { $_ -notin $validIds }
  if ($unknown) {
    Write-Fail "未知工具（-AddTools）：$($unknown -join ', ')"
    Write-Host ""
    Write-Host "可用工具：$($validIds -join ', ')" -ForegroundColor Yellow
    exit 1
  }
}

# 校验 -RemoveTools 参数
if ($RemoveTools -and $RemoveTools.Count -gt 0) {
  if ($RemoveTools -contains 'all') {
    $RemoveTools = @($validIds)
  }
  $unknown = $RemoveTools | Where-Object { $_ -notin $validIds }
  if ($unknown) {
    Write-Fail "未知工具（-RemoveTools）：$($unknown -join ', ')"
    Write-Host ""
    Write-Host "可用工具：$($validIds -join ', ')" -ForegroundColor Yellow
    exit 1
  }
}

# 不允许同时安装和卸载同一工具
if ($AddTools -and $RemoveTools) {
  $conflict = $AddTools | Where-Object { $_ -in $RemoveTools }
  if ($conflict) {
    Write-Fail "不能同时安装和卸载同一工具：$($conflict -join ', ')"
    exit 1
  }
}

Write-Host ""
Write-Banner -Title '基础工具管理（Windows）    ' -Color Cyan
Write-Host ""

# ── 卸载流程 ──
if ($RemoveTools -and $RemoveTools.Count -gt 0) {
  # 卸载 winget 时，如果其他工具也依赖 winget，提示先卸载依赖工具
  if ('winget' -in $RemoveTools) {
    $dependents = $RemoveTools | Where-Object { $_ -ne 'winget' }
    if ($dependents) {
      Write-Warn "winget 是其他工具的依赖，建议先卸载依赖工具再卸载 winget"
    }
  }

  $step = 0
  $total = $RemoveTools.Count
  $removeResults = @{}

  foreach ($id in $RemoveTools) {
    $step++
    $def = $ToolDefs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    Write-Host "[$step/$total] 卸载 $($def.Name)" -ForegroundColor Cyan
    $removeResults[$id] = & $ToolUninstallers[$id]
    Write-Host ""
  }

  # 卸载摘要
  Write-Host "═══ 卸载摘要 ═══" -ForegroundColor Cyan
  foreach ($id in $RemoveTools) {
    $def = $ToolDefs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    Write-StatusLine -Label $def.Name -Ok:$removeResults[$id]
  }
  Write-Host ""

  if ($removeResults.Values -notcontains $false) {
    Write-Host "  所有工具卸载完成！" -ForegroundColor Green
  }
  else {
    Write-Host "  部分工具卸载未成功，请查看上方日志。" -ForegroundColor Yellow
  }
  Write-Host ""
}

# ── 安装流程 ──
if ($AddTools -and $AddTools.Count -gt 0) {
  # winget 是其他工具的前置依赖，如果选了非 winget 工具但缺少 winget，自动前置安装
  $needsWinget = $AddTools | Where-Object { $_ -ne 'winget' }
  if ($needsWinget -and -not (Get-ExePath 'winget.exe') -and 'winget' -notin $AddTools) {
    Write-Warn "安装其他工具需要 winget，将先安装 winget"
    $AddTools = @('winget') + @($AddTools)
  }

  $step = 0
  $total = $AddTools.Count
  $addResults = @{}

  foreach ($id in $AddTools) {
    $step++
    $def = $ToolDefs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    Write-Host "[$step/$total] 安装 $($def.Name)" -ForegroundColor Cyan
    $addResults[$id] = & $ToolInstallers[$id]
    Write-Host ""
  }

  # 安装摘要
  Write-Host "═══ 安装摘要 ═══" -ForegroundColor Cyan
  foreach ($id in $AddTools) {
    $def = $ToolDefs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    Write-StatusLine -Label $def.Name -Ok:$addResults[$id]
  }
  Write-Host ""

  if ($addResults.Values -notcontains $false) {
    Write-Host "  所有工具安装完成！" -ForegroundColor Green
  }
  else {
    Write-Host "  部分工具安装未成功，请查看上方日志。" -ForegroundColor Yellow
  }
}
