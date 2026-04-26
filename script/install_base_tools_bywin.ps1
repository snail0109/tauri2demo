param(
  [Alias('y')]
  [switch]$Yes,

  [string[]]$AddTools,

  [ValidateSet('auto', 'appx', 'store', 'psgallery', 'onescript')]
  [string]$WingetMethod = 'auto'
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

# ─── 工具注册表 ───────────────────────────────────────────────────────────────
# 每个工具：Id（参数名）、Name（显示名）、Description
$ToolDefs = @(
  @{ Id = 'winget';  Name = 'winget';        Description = 'Windows 包管理器' },
  @{ Id = 'terminal'; Name = 'Windows 终端';  Description = 'Windows Terminal（多标签终端）' }
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

function Install-WingetFromAppx {
  # ── 1. 安装 VCLibs（如果缺失） ──
  $vcLibs = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -ErrorAction SilentlyContinue
  if (-not $vcLibs) {
    Write-Host "  安装 VCLibs 运行时依赖 ..." -ForegroundColor Cyan
    $vcLibsInstaller = Join-Path $env:TEMP ("VCLibs_{0}.appx" -f ([guid]::NewGuid().ToString('N')))
    try {
      if (Save-WebFile -Urls @('https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx') -OutFile $vcLibsInstaller -TimeoutSec 60) {
        try {
          Add-AppxPackage -Path $vcLibsInstaller -ErrorAction Stop
          Write-Ok "VCLibs 安装成功"
        } catch {
          Write-Warn "VCLibs 安装失败：$($_.Exception.Message)"
        }
      } else {
        Write-Warn "VCLibs 下载失败，继续尝试安装 winget ..."
      }
    } finally {
      Remove-Item -LiteralPath $vcLibsInstaller -Force -ErrorAction SilentlyContinue
    }
  } else {
    Write-Ok "VCLibs 已安装"
  }

  # ── 2. 安装 Microsoft.UI.Xaml（如果缺失） ──
  $uiXaml = Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.8' -ErrorAction SilentlyContinue
  if (-not $uiXaml) {
    Write-Host "  安装 Microsoft.UI.Xaml 运行时依赖 ..." -ForegroundColor Cyan
    $xamlInstaller = Join-Path $env:TEMP ("UIXaml_{0}.msix" -f ([guid]::NewGuid().ToString('N')))
    try {
      if (Save-WebFile -Urls @(
        'https://github.com/nicedouble/WinGetInstall/raw/main/Microsoft.UI.Xaml.2.8.msix',
        'https://globalcdn.nuget.org/packages/microsoft.ui.xaml.2.8.6.nupkg'
      ) -OutFile $xamlInstaller -TimeoutSec 60) {
        try {
          Add-AppxPackage -Path $xamlInstaller -ErrorAction Stop
          Write-Ok "Microsoft.UI.Xaml 安装成功"
        } catch {
          Write-Warn "Microsoft.UI.Xaml 安装失败：$($_.Exception.Message)"
        }
      } else {
        Write-Warn "Microsoft.UI.Xaml 下载失败，继续尝试安装 winget ..."
      }
    } finally {
      Remove-Item -LiteralPath $xamlInstaller -Force -ErrorAction SilentlyContinue
    }
  } else {
    Write-Ok "Microsoft.UI.Xaml 已安装"
  }

  # ── 3. 下载并安装 winget .appxbundle ──
  Write-Host "  下载 winget 安装包 ..." -ForegroundColor Cyan
  $wingetInstaller = Join-Path $env:TEMP ("winget_{0}.appxbundle" -f ([guid]::NewGuid().ToString('N')))
  try {
    $releaseApiUrl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $downloadUrl = $null
    try {
      $prev = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      $release = Invoke-RestMethod -Uri $releaseApiUrl -TimeoutSec 15
      $asset = $release.assets | Where-Object { $_.name -like '*.appxbundle' } | Select-Object -First 1
      if ($asset) { $downloadUrl = $asset.browser_download_url }
      $ErrorActionPreference = $prev
    } catch {
      Write-Warn "无法获取 winget 最新版下载地址，使用固定版本 ..."
    }

    $urls = @()
    if ($downloadUrl) { $urls += $downloadUrl }
    $urls += 'https://github.com/microsoft/winget-cli/releases/download/v1.10.340/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'

    if (-not (Save-WebFile -Urls $urls -OutFile $wingetInstaller -TimeoutSec 120)) {
      Write-Fail "下载 winget 安装包失败"
      return $false
    }

    Write-Ok "正在安装 winget ..."
    try {
      Add-AppxPackage -Path $wingetInstaller -ErrorAction Stop
      Write-Ok "winget 安装成功"
      return $true
    } catch {
      Write-Fail "winget 安装失败：$($_.Exception.Message)"
      return $false
    }
  } finally {
    Remove-Item -LiteralPath $wingetInstaller -Force -ErrorAction SilentlyContinue
  }
}

function Install-WingetFromPSGallery {
  Write-Host "  通过 PowerShell Gallery 安装 winget ..." -ForegroundColor Cyan
  try {
    Invoke-NativeStream -Block { & powershell -NoProfile -Command "Install-Script winget-install -Force; winget-install" }
    Write-Ok "winget-install 脚本已执行"
    return $true
  } catch {
    Write-Warn "PowerShell Gallery 安装失败：$($_.Exception.Message)"
    return $false
  }
}

function Install-WingetFromOneScript {
  Write-Host "  通过一键脚本安装 winget ..." -ForegroundColor Cyan
  try {
    Invoke-NativeStream -Block { & powershell -NoProfile -Command "irm asheroto.com/winget | iex" }
    Write-Ok "winget 一键安装脚本已执行"
    return $true
  } catch {
    Write-Warn "一键脚本安装失败：$($_.Exception.Message)"
    return $false
  }
}

function Install-WingetFromStore {
  Write-Host "  尝试从 Microsoft Store 安装 winget ..." -ForegroundColor Cyan
  try {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $appInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prev
    if ($appInstaller) {
      Write-Ok "Microsoft.DesktopAppInstaller 已存在，尝试更新 ..."
    }
    Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
    Write-Warn "已打开 Microsoft Store 页面，请在 Store 中点击「安装」或「更新」"
    Write-Warn "安装完成后按 Enter 继续 ..."
    Read-Host
    return (Test-Winget)
  } catch {
    Write-Warn "无法打开 Microsoft Store：$($_.Exception.Message)"
    return $false
  }
}

function Install-WingetTool {
  Write-Host ""
  Write-Host "═══ 安装 winget ═══" -ForegroundColor Cyan
  Write-Host ""

  if (Test-Winget) {
    Write-Host ""
    Write-Banner -Title 'winget 已就绪' -Color Green
    return $true
  }

  Write-Host "  ✗ 未检测到 winget" -ForegroundColor Red
  Write-Host ""

  if (-not (Confirm-Install "安装 winget（Windows 包管理器）")) { return $false }

  $installed = $false

  # 根据 -WingetMethod 参数决定安装方式
  if ($WingetMethod -ne 'auto') {
    switch ($WingetMethod) {
      'appx' {
        Write-Host ""
        Write-Host "  指定方式：下载 winget 安装包并安装" -ForegroundColor Yellow
        $installed = Install-WingetFromAppx
      }
      'store' {
        Write-Host ""
        Write-Host "  指定方式：通过 Microsoft Store 安装" -ForegroundColor Yellow
        $installed = Install-WingetFromStore
      }
      'psgallery' {
        Write-Host ""
        Write-Host "  指定方式：通过 PowerShell Gallery 安装" -ForegroundColor Yellow
        $installed = Install-WingetFromPSGallery
      }
      'onescript' {
        Write-Host ""
        Write-Host "  指定方式：通过一键脚本安装" -ForegroundColor Yellow
        $installed = Install-WingetFromOneScript
      }
    }
  } else {
    # auto 模式：依次尝试各方式
    if (-not $installed) {
      Write-Host ""
      Write-Host "  方式一：下载 winget 安装包并安装" -ForegroundColor Yellow
      if (Confirm-Continue "通过下载 .appxbundle 安装 winget") {
        $installed = Install-WingetFromAppx
      }
    }

    if (-not $installed) {
      Write-Host ""
      Write-Host "  方式二：通过 PowerShell Gallery 安装" -ForegroundColor Yellow
      if (Confirm-Continue "通过 PowerShell Gallery 安装 winget") {
        $installed = Install-WingetFromPSGallery
      }
    }

    if (-not $installed) {
      Write-Host ""
      Write-Host "  方式三：通过一键脚本安装" -ForegroundColor Yellow
      if (Confirm-Continue "通过 irm asheroto.com/winget | iex 安装 winget") {
        $installed = Install-WingetFromOneScript
      }
    }

    if (-not $installed) {
      Write-Host ""
      Write-Host "  方式四：通过 Microsoft Store 安装" -ForegroundColor Yellow
      if (Confirm-Continue "打开 Microsoft Store 安装 winget") {
        $installed = Install-WingetFromStore
      }
    }
  }

  Write-Host ""
  if (Test-Winget) {
    Write-Banner -Title 'winget 安装成功' -Color Green
    return $true
  }
  if ($installed) {
    Write-Warn "winget 安装流程已执行，但当前 shell 未检测到 winget"
    Write-Warn "请重新打开终端后再次运行此脚本验证"
    return $false
  }
  Write-Fail "winget 自动安装失败"
  Write-Fail "请手动安装 winget："
  Write-Fail "  • 打开 Microsoft Store 搜索「应用安装程序」并安装/更新"
  Write-Fail "  • 或运行：irm asheroto.com/winget | iex"
  Write-Fail "  • 或运行：Install-Script winget-install -Force; winget-install"
  Write-Fail "  • 或访问 https://github.com/microsoft/winget-cli/releases 下载安装"
  return $false
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
      Invoke-NativeStream -Block { & winget install --id Microsoft.WindowsTerminal --accept-package-agreements --accept-source-agreements }
      $installed = $true
    } catch {
      Write-Warn "winget 安装 Windows 终端失败：$($_.Exception.Message)"
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
      } catch {
        Write-Warn "无法获取 Windows 终端最新版下载地址，使用固定版本 ..."
      }

      $urls = @()
      if ($downloadUrl) { $urls += $downloadUrl }
      $urls += 'https://github.com/microsoft/terminal/releases/download/v1.22.3112.0/Microsoft.WindowsTerminal_1.22.3112.0_x64.msixbundle'

      if (Save-WebFile -Urls $urls -OutFile $wtInstaller -TimeoutSec 120) {
        try {
          Add-AppxPackage -Path $wtInstaller -ErrorAction Stop
          Write-Ok "Windows 终端安装成功"
          $installed = $true
        } catch {
          Write-Fail "Windows 终端安装失败：$($_.Exception.Message)"
        }
      } else {
        Write-Fail "下载 Windows 终端安装包失败"
      }
    } finally {
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
    } catch {
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

# ─── 工具调度 ─────────────────────────────────────────────────────────────────

# Id → Install 函数 的映射
$ToolInstallers = @{
  'winget'   = ${function:Install-WingetTool}
  'terminal' = ${function:Install-WindowsTerminalTool}
}

function Write-Usage {
  Write-Host ""
  Write-Banner -Title '基础工具安装（Windows）    ' -Color Cyan
  Write-Host ""
  Write-Host "用法：" -ForegroundColor Cyan
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools <工具1,工具2,...>  安装指定工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools all               安装所有工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -y -AddTools all            静默安装所有工具"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget -WingetMethod psgallery  指定 winget 安装方式"
  Write-Host ""
  Write-Host "可用工具：" -ForegroundColor Cyan
  foreach ($t in $ToolDefs) {
    Write-Host ("  {0,-10} {1}" -f $t.Id, $t.Description)
  }
  Write-Host ""
  Write-Host "WingetMethod 参数（仅安装 winget 时生效）：" -ForegroundColor Cyan
  Write-Host "  auto       自动依次尝试所有方式（默认）"
  Write-Host "  appx       下载 .appxbundle 安装包安装（需访问 GitHub）"
  Write-Host "  store      通过 Microsoft Store 安装（需图形界面）"
  Write-Host "  psgallery  通过 PowerShell Gallery 安装（无需 GitHub）"
  Write-Host "  onescript  通过一键脚本 irm asheroto.com/winget | iex 安装（无需 GitHub）"
  Write-Host ""
  Write-Host "示例：" -ForegroundColor Cyan
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget,terminal"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools all"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget -WingetMethod psgallery"
  Write-Host "  .\install_base_tools_bywin.ps1 -AddTools winget -WingetMethod onescript"
  Write-Host ""
}

# ─── 主流程 ───────────────────────────────────────────────────────────────────

if (-not $AddTools -or $AddTools.Count -eq 0) {
  Write-Usage
  exit 0
}

# 展开别名：all → 所有工具 Id
$validIds = $ToolDefs | ForEach-Object { $_.Id }
if ($AddTools -contains 'all') {
  $AddTools = @($validIds)
}

# 校验参数
$unknown = $AddTools | Where-Object { $_ -notin $validIds }
if ($unknown) {
  Write-Fail "未知工具：$($unknown -join ', ')"
  Write-Host ""
  Write-Host "可用工具：$($validIds -join ', ')" -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Banner -Title '基础工具安装（Windows）    ' -Color Cyan
Write-Host ""

# winget 是其他工具的前置依赖，如果选了非 winget 工具但缺少 winget，自动前置安装
$needsWinget = $AddTools | Where-Object { $_ -ne 'winget' }
if ($needsWinget -and -not (Get-ExePath 'winget.exe') -and 'winget' -notin $AddTools) {
  Write-Warn "安装其他工具需要 winget，将先安装 winget"
  $AddTools = @('winget') + @($AddTools)
}

$step = 0
$total = $AddTools.Count
$results = @{}

foreach ($id in $AddTools) {
  $step++
  $def = $ToolDefs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
  Write-Host "[$step/$total] $($def.Name)" -ForegroundColor Cyan
  $results[$id] = & $ToolInstallers[$id]
  Write-Host ""
}

# 摘要
Write-Host "═══ 安装摘要 ═══" -ForegroundColor Cyan
foreach ($id in $AddTools) {
  $def = $ToolDefs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
  Write-StatusLine -Label $def.Name -Ok:$results[$id]
}
Write-Host ""

if ($results.Values -notcontains $false) {
  Write-Host "  所有工具安装完成！" -ForegroundColor Green
} else {
  Write-Host "  部分工具安装未成功，请查看上方日志。" -ForegroundColor Yellow
}
