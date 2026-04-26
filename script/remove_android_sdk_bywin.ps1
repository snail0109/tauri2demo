param(
  [Alias('y')]
  [switch]$Yes,

  [Alias('WhatIf')]
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

function Stop-AndroidProcess {
  Write-Warn "正在结束 adb / Android Studio / Gradle 相关进程..."
  $names = @('adb', 'studio64', 'studio', 'gradle', 'gradlew', 'fsnotifier')
  foreach ($n in $names) {
    $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
    if (-not $procs) { continue }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Ok "已结束 $n"
  }
  Start-Sleep -Seconds 1
  Write-Ok "进程清理完成"
}

function Remove-RustAndroidTarget {
  if (-not (Get-ExePath 'rustup.exe')) {
    Write-Warn "未检测到 rustup，跳过 Rust Android 编译目标卸载"
    return
  }
  $required = @('aarch64-linux-android', 'armv7-linux-androideabi', 'i686-linux-android', 'x86_64-linux-android')
  $installed = Get-RustupInstalledTarget
  $present = $required | Where-Object { $installed -contains $_ }
  if (-not $present -or $present.Count -eq 0) {
    Write-Warn "未检测到任何 Android Rust 编译目标，跳过"
    return
  }
  if (-not (Confirm-Remove "卸载 $($present.Count) 个 Rust Android 编译目标")) {
    Write-Warn "已跳过 Rust Android 编译目标卸载"
    return
  }
  foreach ($t in $present) {
    if ($DryRun) { Write-Warn "DryRun: rustup target remove $t"; continue }
    Invoke-NativeStream -Block { & rustup target remove $t }
    if ($LASTEXITCODE -eq 0) { Write-Ok "已卸载 $t" } else { Write-Fail "rustup target remove $t 失败" }
  }
}

function Remove-AndroidSdkDir {
  $sdk = Resolve-AndroidHome
  if (-not $sdk) {
    Write-Warn "未检测到 Android SDK 安装目录，跳过"
    return
  }
  Write-Warn "删除 SDK 目录将移除以下组件：platform-tools / cmdline-tools / ndk / platforms / build-tools"
  if (-not (Confirm-Remove "删除整个 Android SDK 目录：$sdk")) {
    Write-Warn "已跳过 Android SDK 目录删除"
    return
  }

  if ($DryRun) {
    Write-Warn "DryRun: Stop-AndroidProcess"
    Write-Warn "DryRun: Remove-Item -Recurse -Force `"$sdk`""
    return
  }

  Stop-AndroidProcess
  try {
    Remove-Item -LiteralPath $sdk -Recurse -Force -ErrorAction Stop
    Write-Ok "Android SDK 目录已删除：$sdk"
  } catch {
    Write-Fail "删除 $sdk 失败（可能仍有文件被占用）"
    Write-Fail "请手动删除（PowerShell 管理员）：Remove-Item -Recurse -Force `"$sdk`""
  }
}

function Remove-AndroidEnvVar {
  if (-not (Confirm-Remove "清理 ANDROID_HOME / ANDROID_NDK_HOME 用户环境变量及 PATH 中的 platform-tools 段")) {
    Write-Warn "已跳过环境变量清理"
    return
  }

  if ($DryRun) {
    Write-Warn "DryRun: 清理用户环境变量 ANDROID_HOME / ANDROID_NDK_HOME / PATH(platform-tools)"
    return
  }

  if (Set-UserEnv -Name 'ANDROID_HOME' -ValueOrNull $null) { Write-Ok "ANDROID_HOME 已从用户环境变量移除" } else { Write-Fail "移除 ANDROID_HOME 失败" }
  if (Set-UserEnv -Name 'ANDROID_NDK_HOME' -ValueOrNull $null) { Write-Ok "ANDROID_NDK_HOME 已从用户环境变量移除" } else { Write-Fail "移除 ANDROID_NDK_HOME 失败" }

  $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
  if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $kept = ($userPath -split ';' | Where-Object { $_ -and ($_ -notmatch 'platform-tools') }) -join ';'
    if (Set-UserEnv -Name 'PATH' -ValueOrNull $kept) {
      Write-Ok "用户 PATH 中的 platform-tools 段已清理"
    } else {
      Write-Fail "清理用户 PATH 失败，请手动到「环境变量」中编辑 PATH"
    }
  } else {
    Write-Warn "用户 PATH 为空，跳过"
  }

  Write-Ok "环境变量清理完成（新开终端窗口后生效）"
}

function Show-DirChildren {
  param([string]$Label, [string]$Path, [string]$NotInstalledLabel = '未装')
  if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "  $Label（$NotInstalledLabel）"; return }
  $names = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
  if ($names) { Write-Ok ("  {0} → {1}" -f $Label, ($names -join ' ')) } else { Write-Warn "  $Label（$NotInstalledLabel）" }
}

function Show-InstallationStatus {
  Write-Banner -Title '当前安装状态检测                         ' -Color Cyan

  Write-Host "[1/3] Android SDK" -ForegroundColor Cyan
  $sdk = Resolve-AndroidHome
  if ($sdk) {
    $script:InstalledSdkRoot = $sdk
    Write-Ok "ANDROID_HOME=$sdk"
    if (Test-Path -LiteralPath (Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat')) { Write-Ok "  cmdline-tools;latest" } else { Write-Warn "  cmdline-tools;latest（未装）" }
    if (Test-Path -LiteralPath (Join-Path $sdk 'platform-tools\adb.exe')) { Write-Ok "  platform-tools" } else { Write-Warn "  platform-tools（未装）" }
    if (Test-Path -LiteralPath (Join-Path $sdk 'ndk')) {
      $latest = Get-ChildItem -LiteralPath (Join-Path $sdk 'ndk') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object | Select-Object -Last 1
      if ($latest) { Write-Ok "  ndk → $latest" } else { Write-Warn "  ndk（未装）" }
    } elseif (Test-Path -LiteralPath (Join-Path $sdk 'ndk-bundle')) {
      Write-Ok "  ndk-bundle（旧版）"
    } else {
      Write-Warn "  ndk（未装）"
    }
    Show-DirChildren -Label 'platforms' -Path (Join-Path $sdk 'platforms')
    Show-DirChildren -Label 'build-tools' -Path (Join-Path $sdk 'build-tools')
  } else {
    Write-Warn "未检测到 Android SDK 根目录"
    $script:InstalledSdkRoot = ''
  }

  Write-Host "[2/3] Rust Android 编译目标" -ForegroundColor Cyan
  $script:InstalledRustCount = 0
  $required = @('aarch64-linux-android', 'armv7-linux-androideabi', 'i686-linux-android', 'x86_64-linux-android')
  if (Get-ExePath 'rustup.exe') {
    $installed = Get-RustupInstalledTarget
    foreach ($t in $required) {
      if ($installed -contains $t) { Write-Ok "  $t"; $script:InstalledRustCount++ } else { Write-Warn "  $t（未装）" }
    }
  } else {
    Write-Warn "未检测到 rustup"
  }

  Write-Host "[3/3] 用户环境变量" -ForegroundColor Cyan
  $script:InstalledEnvAh = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
  $script:InstalledEnvNdk = [Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME', 'User')
  if ($script:InstalledEnvAh) { Write-Ok "ANDROID_HOME=$($script:InstalledEnvAh)" } else { Write-Warn "ANDROID_HOME 未设置" }
  if ($script:InstalledEnvNdk) { Write-Ok "ANDROID_NDK_HOME=$($script:InstalledEnvNdk)" } else { Write-Warn "ANDROID_NDK_HOME 未设置" }

  if ([string]::IsNullOrWhiteSpace($script:InstalledSdkRoot) -and $script:InstalledRustCount -eq 0 -and [string]::IsNullOrWhiteSpace($script:InstalledEnvAh) -and [string]::IsNullOrWhiteSpace($script:InstalledEnvNdk)) {
    Write-Host ""
    Write-Host "  未检测到任何 install_android_sdk_bywin 脚本装过的内容，无需卸载。" -ForegroundColor Green
    exit 0
  }
  Write-Host ""
}

Write-Host ""
Write-Banner -Title 'Android SDK 卸载（Windows PowerShell）  ' -Color Red
Write-Host ""

Show-InstallationStatus
Write-Warn "本脚本会卸载 Android 开发工具，可能影响其它项目。请确认你了解每一步。"
Write-Host ""

$selected = Select-MenuOption -Prompt '请选择要卸载的内容：' -Options @(
  'Rust Android 编译目标（保留 Android SDK）',
  'Android SDK 目录 + 环境变量（保留 Rust Android targets）',
  '全部卸载（Rust targets + Android SDK + 环境变量）'
)

switch ($selected) {
  1 {
    Enable-AutoConfirm
    Remove-RustAndroidTarget
  }
  2 {
    Enable-AutoConfirm
    Remove-AndroidSdkDir
    Remove-AndroidEnvVar
  }
  3 {
    Write-Warn "即将依次卸载：Rust Android targets → Android SDK 目录 → 环境变量"
    if (-not (Confirm-Remove "确认执行全部卸载（请慎重）")) {
      Write-Host ""
      Write-Host "  已退出，未卸载任何内容。" -ForegroundColor Yellow
      exit 0
    }
    Enable-AutoConfirm
    Remove-RustAndroidTarget
    Remove-AndroidSdkDir
    Remove-AndroidEnvVar
  }
  0 {
    Write-Host ""
    Write-Host "  已退出，未卸载任何内容。" -ForegroundColor Yellow
    exit 0
  }
}

Write-Host ""
Write-Banner -Title '卸载结束摘要                            ' -Color Cyan

$sdkNow = Resolve-AndroidHome
Write-RemovedStatus -Label 'Android SDK    ' -NotPresent (-not ($sdkNow -and (Test-Path -LiteralPath $sdkNow))) -Detail $sdkNow

if (Get-ExePath 'rustup.exe') {
  $remain = (Get-RustupInstalledTarget | Where-Object { $_ -match 'linux-android' }).Count
  Write-RemovedStatus -Label 'Rust targets   ' -NotPresent ($remain -eq 0) -NotOkText "仍存在 $remain 个"
} else {
  Write-Warn "  Rust targets   ：rustup 未检测到，无法确认"
}

$envAh = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
$envNdk = [Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME', 'User')
Write-RemovedStatus -Label 'ANDROID_HOME   ' -NotPresent ([string]::IsNullOrWhiteSpace($envAh)) -Detail $envAh
Write-RemovedStatus -Label 'ANDROID_NDK_HOME' -NotPresent ([string]::IsNullOrWhiteSpace($envNdk)) -Detail $envNdk

Write-Host ""
if (-not $Failed) { Write-Host "  卸载完成！" -ForegroundColor Green }
else { Write-Host "  卸载流程已结束，但部分步骤失败或未完成，请查看上方日志手动处理。" -ForegroundColor Yellow }
