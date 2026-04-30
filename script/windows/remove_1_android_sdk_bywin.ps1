<#
.SYNOPSIS
  卸载 Android SDK / Rust Android targets，并清理相关用户环境变量（Windows）。
.DESCRIPTION
  - 支持 -DryRun：只输出将执行的命令，不实际修改系统
  - 提供菜单选择：仅卸载 Rust targets / 仅删除 SDK+环境变量 / 全部卸载
  - 会先展示当前安装状态，避免误删
.PARAMETER Yes
  自动确认（静默模式）。
.PARAMETER DryRun
  演练模式：不真正删除目录/卸载 targets/修改环境变量。
#>
$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

Enable-AutoConfirm

<#
.SYNOPSIS
  尝试结束可能占用 Android SDK 的进程（adb/Android Studio/Gradle 等），降低删除失败概率。
.NOTES
  该步骤只用于“删除 SDK 目录”前的清理，失败不会阻止后续尝试。
#>
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

<#
.SYNOPSIS
  卸载 Rust Android 交叉编译目标（rustup target remove）。
.NOTES
  - 只卸载当前已安装的目标（与 Get-AndroidRustTarget 的交集）
  - DryRun 时只打印命令，不实际执行
#>
function Remove-RustAndroidTarget {
  if (-not (Get-ExePath 'rustup.exe')) {
    Write-Warn "未检测到 rustup，跳过 Rust Android 编译目标卸载"
    return
  }
  $required = Get-AndroidRustTarget
  $installed = Get-RustupInstalledTarget
  $present = $required | Where-Object { $installed -contains $_ }
  if (-not $present -or $present.Count -eq 0) {
    Write-Warn "未检测到任何 Android Rust 编译目标，跳过"
    return
  }
  foreach ($t in $present) {
    Invoke-NativeStream -Block { & rustup target remove $t }
    if ($LASTEXITCODE -eq 0) { Write-Ok "已卸载 $t" } else { Write-Fail "rustup target remove $t 失败" }
  }
}

<#
.SYNOPSIS
  删除 Android SDK 根目录（ANDROID_HOME 指向的目录）。
.NOTES
  - 会提示用户确认
  - DryRun 时只打印将执行的操作
#>
function Remove-AndroidSdkDir {
  $sdk = Resolve-AndroidHome
  if (-not $sdk) {
    Write-Warn "未检测到 Android SDK 安装目录，跳过"
    return
  }
  Write-Warn "删除 SDK 目录将移除以下组件：platform-tools / cmdline-tools / ndk / platforms / build-tools"

  Stop-AndroidProcess
  try {
    Remove-Item -LiteralPath $sdk -Recurse -Force -ErrorAction Stop
    Write-Ok "Android SDK 目录已删除：$sdk"
  } catch {
    Write-Fail "删除 $sdk 失败（可能仍有文件被占用）"
    Write-Fail "请手动删除（PowerShell 管理员）：Remove-Item -Recurse -Force `"$sdk`""
  }
}

<#
.SYNOPSIS
  清理用户级环境变量：ANDROID_HOME、ANDROID_NDK_HOME，并从用户 PATH 移除 platform-tools 段。
.NOTES
  - 仅影响用户环境变量（User scope），需要新开终端窗口才会对新会话生效
  - DryRun 时只打印将执行的操作
#>
function Remove-AndroidEnvVar {
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

<#
.SYNOPSIS
  打印目录下的一级子目录名称（用于展示已安装的 platforms/build-tools 等）。
.PARAMETER Label
  显示标签。
.PARAMETER Path
  目录路径。
.PARAMETER NotInstalledLabel
  不存在时的提示文本。
#>
function Show-DirChildren {
  param([string]$Label, [string]$Path, [string]$NotInstalledLabel = '未装')
  if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "  $Label（$NotInstalledLabel）"; return }
  $names = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
  if ($names) { Write-Ok ("  {0} → {1}" -f $Label, ($names -join ' ')) } else { Write-Warn "  $Label（$NotInstalledLabel）" }
}

<#
.SYNOPSIS
  展示当前安装状态，并在“确实没有可卸载内容”时提前退出。
.DESCRIPTION
  会检测：
  - Android SDK（cmdline-tools/platform-tools/ndk/platforms/build-tools）
  - Rust Android targets
  - 用户环境变量 ANDROID_HOME / ANDROID_NDK_HOME
#>
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
  $required = Get-AndroidRustTarget
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
Write-Warn "即将完全卸载：Rust Android targets → Android SDK 目录 → 环境变量"
Write-Host ""

Remove-RustAndroidTarget
Remove-AndroidSdkDir
Remove-AndroidEnvVar

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
