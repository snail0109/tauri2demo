param(
  [Alias('y')]
  [switch]$Yes,

  [string]$SdkRoot
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

function Save-WebFile {
  param([string[]]$Urls, [string]$OutFile)
  foreach ($u in $Urls) {
    Write-Host "  尝试下载：$u" -ForegroundColor Cyan
    try {
      Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -TimeoutSec 30 | Out-Null
      Write-Ok "下载完成（来源：$u）"
      return $true
    } catch {
      Write-Warn "下载失败，尝试下一个镜像 ..."
    }
  }
  return $false
}

function Install-SdkManagerBootstrap {
  param([string]$SdkRootPath)

  $zipName = 'commandlinetools-win-11076708_latest.zip'
  $urls = @(
    "https://mirrors.huaweicloud.com/android/repository/$zipName",
    "https://mirrors.cloud.tencent.com/AndroidSDK/$zipName",
    "https://dl.google.com/android/repository/$zipName"
  )

  New-DirectoryIfMissing (Join-Path $SdkRootPath 'cmdline-tools')

  $tmpZip = Join-Path $env:TEMP ("cmdline-tools_{0}.zip" -f ([guid]::NewGuid().ToString('N')))
  $tmpExtract = Join-Path $env:TEMP ("cmdline-tools_extract_{0}" -f ([guid]::NewGuid().ToString('N')))
  New-DirectoryIfMissing $tmpExtract

  try {
    if (-not (Save-WebFile -Urls $urls -OutFile $tmpZip)) {
      Write-Fail "所有镜像源下载失败"
      return $false
    }

    Write-Host "  解压到临时目录 ..." -ForegroundColor Cyan
    try {
      Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpExtract -Force
    } catch {
      Write-Fail "Expand-Archive 解压失败"
      return $false
    }

    $extracted = Join-Path $tmpExtract 'cmdline-tools'
    if (-not (Test-Path -LiteralPath $extracted)) {
      Write-Fail "解压后未找到 cmdline-tools 目录"
      return $false
    }

    $latest = Join-Path $SdkRootPath 'cmdline-tools\latest'
    if (Test-Path -LiteralPath $latest) {
      Remove-Item -LiteralPath $latest -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $extracted -Destination $latest -Force

    $sdkmanager = Join-Path $latest 'bin\sdkmanager.bat'
    if (Test-Path -LiteralPath $sdkmanager) {
      Write-Ok "SDKManager 已安装：$sdkmanager"
      return $true
    }
    Write-Fail "安装后仍未找到 SDKManager.bat"
    return $false
  } finally {
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Show-SdkManagerVersion([string]$SdkManagerPath) {
  $ver = Invoke-NativeText -FilePath $SdkManagerPath -Arguments @('--version') |
    Where-Object { $_ -match '^[0-9]' } |
    Select-Object -First 1
  if ($ver) {
    Write-Ok "    版本：$ver"
  } else {
    Write-Warn "    无法读取 SDKManager 版本（可能 Java 未就绪，下一步会校验）"
  }
}

function Invoke-SdkManager {
  param(
    [string]$SdkManagerPath,
    [string]$AndroidHome,
    [string[]]$Packages
  )
  $sdkRootArg = "--sdk_root=$AndroidHome"
  $pkgArgs = ($Packages | ForEach-Object { '"{0}"' -f $_ }) -join ' '

  if ($Yes) {
    Write-Host "  静默模式：自动接受所有许可协议" -ForegroundColor Yellow
    Write-Host ""
    $yesFile = Join-Path $env:TEMP ("sdkmanager_yes_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
    (1..2500 | ForEach-Object { 'y' }) | Set-Content -LiteralPath $yesFile -Encoding ASCII
    try {
      $cmd = "type `"$yesFile`" | `"$SdkManagerPath`" `"$sdkRootArg`" $pkgArgs"
      & cmd.exe /c $cmd | Out-Host
      if ($LASTEXITCODE -ne 0) { throw "sdkmanager exit code $LASTEXITCODE" }
      return $true
    } catch {
      Write-Fail "Android SDK 组件安装失败"
      return $false
    } finally {
      Remove-Item -LiteralPath $yesFile -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Host "  交互模式：安装过程中需要手动接受许可协议" -ForegroundColor Yellow
  Write-Host "  （如需自动接受，请使用 -y 参数重新运行）" -ForegroundColor Yellow
  Write-Host ""

  try {
    $cmd = "`"$SdkManagerPath`" `"$sdkRootArg`" $pkgArgs"
    & cmd.exe /c $cmd | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "sdkmanager exit code $LASTEXITCODE" }
    return $true
  } catch {
    Write-Fail "Android SDK 组件安装失败"
    return $false
  }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Android SDK 自动安装脚本（Windows PowerShell）       " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$sdkRootDefault = $SdkRoot
if ([string]::IsNullOrWhiteSpace($sdkRootDefault)) { $sdkRootDefault = $env:ANDROID_HOME }
if ([string]::IsNullOrWhiteSpace($sdkRootDefault)) { $sdkRootDefault = 'C:\DevDisk\DevTools\AndroidSDK' }
$sdkRootDefault = $sdkRootDefault.Trim('"')

Write-Host "[1/6] 定位 SDKManager" -ForegroundColor Cyan
$sdkmanager = Find-SdkManager -PreferredRoot $sdkRootDefault
if ($sdkmanager) {
  Write-Ok "SDKManager 已找到：$sdkmanager"
  Show-SdkManagerVersion $sdkmanager
} else {
  $expected = Join-Path $sdkRootDefault 'cmdline-tools\latest\bin\sdkmanager.bat'
  Write-Warn "SDKManager 未找到：$expected"
  if (-not (Confirm-Continue "自动下载 Android 命令行工具包到 $sdkRootDefault")) {
    Write-Fail "已跳过命令行工具包下载，无法继续"
    exit 1
  }
  New-DirectoryIfMissing $sdkRootDefault
  if (-not (Install-SdkManagerBootstrap -SdkRootPath $sdkRootDefault)) {
    Write-Fail "命令行工具包下载/安装失败"
    Write-Fail "请手动下载：https://developer.android.com/studio#command-tools"
    exit 1
  }
  $sdkmanager = Find-SdkManager -PreferredRoot $sdkRootDefault
  if (-not $sdkmanager) {
    Write-Fail "安装后仍未找到 sdkmanager.bat"
    exit 1
  }
}

$androidHome = Get-AndroidHomeFromSdkManager -SdkManagerPath $sdkmanager
Write-Ok "ANDROID_HOME 推导为：$androidHome"
$env:ANDROID_HOME = $androidHome

Write-Host "[2/6] 检查 Java 环境" -ForegroundColor Cyan
$javaVer = Get-JavaMajorVersion
if ($null -eq $javaVer) {
  Write-Fail "未找到 Java，sdkmanager 需要 JDK 17+ 才能运行。"
  Write-Fail "请从 https://adoptium.net/ 下载 JDK 17+"
  exit 1
}
if ($javaVer -lt 17) {
  Write-Fail "检测到 Java $javaVer，但 sdkmanager 需要 JDK 17+。"
  Write-Fail "请从 https://adoptium.net/ 下载 JDK 17+"
  exit 1
}
Write-Ok "Java $javaVer 已安装：$(Get-ExePath 'java.exe')"

Write-Host "[3/6] 准备安装的 Android SDK 组件" -ForegroundColor Cyan
$packages = @(
  'platform-tools',
  'ndk;27.0.12077973',
  'platforms;android-34',
  'build-tools;34.0.0'
)
$sdkmanagerOnDisk = Join-Path $androidHome 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkmanagerOnDisk)) {
  $packages = @('cmdline-tools;latest') + $packages
}

$latest2 = Join-Path $androidHome 'cmdline-tools\latest-2'
if (Test-Path -LiteralPath $latest2) {
  Write-Warn "检测到遗留目录 cmdline-tools\latest-2，正在清理 ..."
  Remove-Item -LiteralPath $latest2 -Recurse -Force -ErrorAction SilentlyContinue
  Write-Ok "已清理 cmdline-tools\latest-2"
}

foreach ($p in $packages) { Write-Host "    $p" }
Write-Host ""

Write-Host "[4/6] 安装 Android SDK 组件" -ForegroundColor Cyan
if (-not (Invoke-SdkManager -SdkManagerPath $sdkmanager -AndroidHome $androidHome -Packages $packages)) {
  exit 1
}

Write-Host ""
Write-Host "  ✓ Android SDK 组件安装完成！" -ForegroundColor Green
Write-Host ""

Write-Host "[5/6] 安装 Rust Android 编译目标" -ForegroundColor Cyan
$requiredTargets = @(
  'aarch64-linux-android',
  'armv7-linux-androideabi',
  'i686-linux-android',
  'x86_64-linux-android'
)

$cargoBin = Join-Path $HOME '.cargo\bin'
if ($null -eq (Get-ExePath 'rustup.exe') -and (Test-Path -LiteralPath (Join-Path $cargoBin 'rustup.exe'))) {
  Add-PathPrefix $cargoBin
}

if ($null -ne (Get-ExePath 'rustup.exe')) {
  $installedTargets = Get-RustupInstalledTarget
  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($t in $requiredTargets) {
    if ($installedTargets -contains $t) {
      Write-Ok "  $t（已安装）"
    } else {
      $missing.Add($t) | Out-Null
      Write-Warn "  $t（未安装）"
    }
  }
  if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "  正在安装缺失的 Rust 编译目标..." -ForegroundColor Yellow
    foreach ($t in $missing) {
      Write-Host "  rustup target add $t" -ForegroundColor Cyan
      try {
        Invoke-NativeStream -Block { & rustup target add $t }
        if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
      } catch { Write-Warn "  $t 安装失败，请手动运行：rustup target add $t" }
    }
    Write-Ok "Rust Android 编译目标安装完成"
  } else {
    Write-Ok "所有 Rust Android 编译目标已就绪"
  }
} else {
  Write-Warn "未找到 rustup，跳过 Rust Android 编译目标安装"
  Write-Warn "请从 https://rustup.rs 安装 Rust 后手动执行："
  foreach ($t in $requiredTargets) { Write-Host "    rustup target add $t" }
}

Write-Host "[6/6] 配置环境变量" -ForegroundColor Cyan
$ndkInfo = Resolve-AndroidNdk -AndroidHome $androidHome
$ndkHome = if ($ndkInfo) { $ndkInfo.Path } else { $null }
$platformTools = Join-Path $androidHome 'platform-tools'

$currentAhUser = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
if ([string]::IsNullOrWhiteSpace($currentAhUser) -or ($currentAhUser.Trim('"') -ne $androidHome)) {
  if (Set-UserEnv -Name 'ANDROID_HOME' -ValueOrNull $androidHome) {
    Write-Ok "ANDROID_HOME 已写入用户环境变量：$androidHome"
    Write-Ok "（新开终端窗口后生效）"
  } else {
    Write-Warn "写入 ANDROID_HOME 失败，请手动设置"
    Write-Warn "  系统设置 → 环境变量 → 用户变量 → 新建 ANDROID_HOME = $androidHome"
  }
} else {
  Write-Ok "ANDROID_HOME 环境变量已正确设置：$androidHome"
}

if ($ndkHome) {
  $currentNdkUser = [Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME', 'User')
  if ([string]::IsNullOrWhiteSpace($currentNdkUser) -or ($currentNdkUser.Trim('"') -ne $ndkHome)) {
    if (Set-UserEnv -Name 'ANDROID_NDK_HOME' -ValueOrNull $ndkHome) {
      Write-Ok "ANDROID_NDK_HOME 已写入用户环境变量：$ndkHome"
      Write-Ok "（新开终端窗口后生效）"
    } else {
      Write-Warn "写入 ANDROID_NDK_HOME 失败，请手动设置"
      Write-Warn "  系统设置 → 环境变量 → 用户变量 → 新建 ANDROID_NDK_HOME = $ndkHome"
    }
  } else {
    Write-Ok "ANDROID_NDK_HOME 环境变量已正确设置：$ndkHome"
  }
} else {
  Write-Warn "未检测到 NDK 版本，跳过 ANDROID_NDK_HOME 设置"
}

if (Add-UserPathSegment -Segment $platformTools) {
  Write-Ok "PATH 已追加：$platformTools"
  Write-Ok "（新开终端窗口后生效）"
} else {
  Write-Warn "写入用户 PATH 失败，请手动添加"
  Write-Warn "  系统设置 → 环境变量 → 用户变量 → 编辑 PATH → 添加 $platformTools"
}

# 修复历史遗留：旧版脚本曾用 setx 写入带引号的值
$ahRaw = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
$ndkRaw = [Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME', 'User')
$fixNeeded = ($ahRaw -and $ahRaw.StartsWith('"')) -or ($ndkRaw -and $ndkRaw.StartsWith('"'))
if ($fixNeeded) {
  Write-Warn "检测到环境变量值包含多余引号，正在修复 ..."
  Set-UserEnv -Name 'ANDROID_HOME' -ValueOrNull $androidHome | Out-Null
  if ($ndkHome) { Set-UserEnv -Name 'ANDROID_NDK_HOME' -ValueOrNull $ndkHome | Out-Null }
  Write-Ok "环境变量引号问题已修复（新开终端窗口后生效）"
}

$env:ANDROID_HOME = $androidHome
if ($ndkHome) { $env:ANDROID_NDK_HOME = $ndkHome }
$env:Path = "$platformTools;$env:Path"
Write-Ok "当前 shell 环境变量已生效（export）"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Android SDK 安装 & 配置完成！                         " -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  注意：写入的用户环境变量需要新开终端窗口才会生效" -ForegroundColor Yellow
Write-Host ""
Write-Host "  现在可以运行构建脚本：" -ForegroundColor Cyan
Write-Host "    .\script\build_bywin.ps1 dev"
Write-Host "    .\script\build_bywin.ps1 build"
Write-Host ""
