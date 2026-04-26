param(
  [Parameter(Position = 0)]
  [ValidateSet('dev', 'build')]
  [string]$Command,

  [Parameter(Position = 1)]
  [Alias('y')]
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

$DefaultKeystoreLines = @(
  'keyAlias=tauri2demo_key',
  'password=abc009988',
  'storeFile="C:\SyncData\release.keystore"'
)

function Test-AndroidProjectComplete([string]$GenAndroidDir) {
  $required = @(
    'settings.gradle.kts',
    'gradlew',
    'app\src\main\java'
  )
  foreach ($r in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $GenAndroidDir $r))) {
      Write-Warn "$r 缺失"
      return $false
    }
  }
  return $true
}

function Restore-AndroidProject {
  param([string]$ProjectRoot, [string]$GenAndroidDir, [string]$ScriptDir)

  $keystorePropsInGen = Join-Path $GenAndroidDir 'keystore.properties'
  $keystoreBackup = $null
  if (Test-Path -LiteralPath $keystorePropsInGen) {
    $keystoreBackup = [System.IO.Path]::GetTempFileName()
    Copy-Item -LiteralPath $keystorePropsInGen -Destination $keystoreBackup -Force
    Write-Warn "已备份 keystore.properties"
  }

  Write-Warn "正在删除不完整的 gen\android 目录 ..."
  if (Test-Path -LiteralPath $GenAndroidDir) {
    Remove-Item -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Warn "正在运行 pnpm tauri android init ..."
  Invoke-NativeStreamIn -Path $ProjectRoot -Block { & pnpm tauri android init }

  if ($keystoreBackup -and (Test-Path -LiteralPath $keystoreBackup)) {
    Copy-Item -LiteralPath $keystoreBackup -Destination $keystorePropsInGen -Force
    Remove-Item -LiteralPath $keystoreBackup -Force -ErrorAction SilentlyContinue
    Write-Ok "keystore.properties 已恢复"
  } elseif (-not (Test-Path -LiteralPath $keystorePropsInGen)) {
    Write-Warn "正在写入 keystore.properties ..."
    New-DirectoryIfMissing (Split-Path -Parent $keystorePropsInGen)
    $DefaultKeystoreLines | Set-Content -LiteralPath $keystorePropsInGen -Encoding UTF8
    Write-Ok "keystore.properties 已写入"
  }

  $genAndroidApp = Join-Path $GenAndroidDir 'app'
  Write-Host "  替换 Android 签名和权限文件" -ForegroundColor Cyan

  $copies = @(
    @{ Src = Join-Path $ScriptDir 'android-permission-sign\build.gradle.kts'; Dst = Join-Path $genAndroidApp 'build.gradle.kts'; Label = 'build.gradle.kts' },
    @{ Src = Join-Path $ScriptDir 'android-permission-sign\AndroidManifest.xml'; Dst = Join-Path $genAndroidApp 'src\main\AndroidManifest.xml'; Label = 'AndroidManifest.xml' }
  )
  foreach ($c in $copies) {
    if (Test-Path -LiteralPath $c.Src) {
      New-DirectoryIfMissing (Split-Path -Parent $c.Dst)
      Copy-Item -LiteralPath $c.Src -Destination $c.Dst -Force
      Write-Ok "$($c.Label) 已替换"
    } else {
      Write-Warn "$($c.Label) 源文件不存在，跳过替换"
    }
  }

  Write-Ok "pnpm tauri android init 完成"
}

function New-Keystore {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'keystore.properties stores password as plain text by design; this script merely passes it to keytool')]
  param([string]$StoreFile, [string]$Alias, [string]$Password)
  if ($null -eq (Get-ExePath 'keytool.exe')) {
    Write-Fail "keytool 未找到，无法自动生成 keystore"
    Write-Fail "请手动运行：keytool -genkeypair -v -keystore `"$StoreFile`" -alias $Alias -keyalg RSA -keysize 2048 -validity 10000"
    return
  }
  $storeDir = Split-Path -Parent $StoreFile
  if (-not [string]::IsNullOrWhiteSpace($storeDir)) { New-DirectoryIfMissing $storeDir }
  Invoke-NativeStream -Block {
    & keytool -genkeypair -v `
      -keystore $StoreFile `
      -alias $Alias `
      -keyalg RSA `
      -keysize 2048 `
      -validity 10000 `
      -storepass $Password `
      -keypass $Password `
      -dname 'CN=Tauri2Demo, OU=Dev, O=Dev, L=Unknown, ST=Unknown, C=CN'
  }
  if ($LASTEXITCODE -eq 0) {
    Write-Ok "Keystore 已生成：$StoreFile"
  } else {
    Write-Fail "keytool 生成 keystore 失败"
    Write-Fail "请手动运行：keytool -genkeypair -v -keystore `"$StoreFile`" -alias $Alias -keyalg RSA -keysize 2048 -validity 10000"
  }
}

if ([string]::IsNullOrWhiteSpace($Command)) {
  Write-Host "用法：$($MyInvocation.MyCommand.Name) <dev|build> [-y]" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  dev    启动 Tauri Android 开发模式（热重载）"
  Write-Host "  build  构建 Android APK/AAB 发布包"
  Write-Host "  -y     自动确认所有安装提示（静默模式）"
  exit 1
}

Write-Host ""
Write-Banner -Title 'Android 环境检查（Windows PowerShell）  ' -Color Cyan
Write-Host ""

Write-Host "[1/8] C/C++ 编译工具 + Rust" -ForegroundColor Cyan

$hasMsvc = $false
$hasGnu = $false

$cl = Get-ExePath 'cl.exe'
if ($cl) {
  Write-Ok "MSVC cl.exe 已安装：$cl"
  $hasMsvc = $true
}

$gcc = Get-ExePath 'gcc.exe'
if ($gcc) {
  Write-Ok "GNU gcc 已安装：$gcc"
  $hasGnu = $true
}

if (-not $hasMsvc -and -not $hasGnu) {
  Write-Fail "未检测到 C/C++ 编译器（MSVC 或 GNU gcc）"
  Write-Fail "请先运行 .\script\install_c_compile_bywin.ps1 安装"
}

if ($null -ne (Get-ExePath 'rustc.exe')) {
  $ver = (Invoke-NativeText -FilePath 'rustc' -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "Rust 已安装：$ver"
} else {
  Write-Fail "未检测到 rustc/rustup"
  Write-Fail "请先运行 .\script\install_c_compile_bywin.ps1 安装"
}

if ($Failed) {
  Write-Host ""
  Write-Banner -Title 'C/C++ 编译工具或 Rust 未就绪，已中止。 ' -Color Red
  exit 1
}

Write-Host "[2/8] Java JDK（17+）" -ForegroundColor Cyan
$javaVer = Get-JavaMajorVersion
if ($null -eq $javaVer) {
  Write-Fail "未找到 Java"
  Write-Fail "请从 https://adoptium.net/ 下载 JDK 17+，或运行：winget install EclipseAdoptium.Temurin.17.JDK"
} elseif ($javaVer -lt 17) {
  Write-Fail "检测到 Java $javaVer，但需要 JDK 17+"
  Write-Fail "请从 https://adoptium.net/ 下载，或运行：winget install EclipseAdoptium.Temurin.17.JDK"
} else {
  Write-Ok "Java $javaVer 已安装：$(Get-ExePath 'java.exe')"
}

Write-Host "[3/8] ANDROID_HOME" -ForegroundColor Cyan
$androidHome = Resolve-AndroidHome
if ($null -ne $androidHome) {
  $env:ANDROID_HOME = $androidHome
  Write-Ok "ANDROID_HOME=$androidHome"
} else {
  Write-Fail "ANDROID_HOME 未设置且未检测到 Android SDK 安装路径"
  Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装"
}

Write-Host "[4/8] Android SDK 工具（adb、sdkmanager）" -ForegroundColor Cyan
if ($androidHome) {
  $adb = Join-Path $androidHome 'platform-tools\adb.exe'
  if (Test-Path -LiteralPath $adb) {
    Write-Ok "adb 已找到：$adb"
  } else {
    Write-Fail "未找到 adb.exe（$adb）"
    Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装 platform-tools"
  }

  $sdkmanager = Join-Path $androidHome 'cmdline-tools\latest\bin\sdkmanager.bat'
  if (Test-Path -LiteralPath $sdkmanager) {
    Write-Ok "sdkmanager 已找到：$sdkmanager"
  } else {
    Write-Fail "sdkmanager 未找到：$sdkmanager"
    Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装 cmdline-tools;latest"
  }
}

Write-Host "[5/8] Android NDK" -ForegroundColor Cyan
$ndkInfo = if ($androidHome) { Resolve-AndroidNdk $androidHome } else { $null }
if ($ndkInfo) {
  if ([string]::IsNullOrWhiteSpace($env:ANDROID_NDK_HOME)) { $env:ANDROID_NDK_HOME = $ndkInfo.Path }
  Write-Ok "NDK 版本：$($ndkInfo.Version) → $($ndkInfo.Path)"
  if ($ndkInfo.Kind -eq 'ndk-bundle') {
    Write-Warn "检测到旧版 ndk-bundle（版本 $($ndkInfo.Version)），建议安装新版 NDK"
  }
} else {
  Write-Fail "未找到 NDK（路径：$androidHome\ndk 和 $androidHome\ndk-bundle 均不存在）"
  Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装"
}

if ($Failed) {
  Write-Host ""
  Write-Host "══════════════════════════════════════════" -ForegroundColor Red
  Write-Host "  Android 工具链未就绪，已中止。         " -ForegroundColor Red
  Write-Host "  请运行 .\script\install_android_sdk_bywin.ps1" -ForegroundColor Red
  Write-Host "══════════════════════════════════════════" -ForegroundColor Red
  exit 1
}

Write-Host "[6/8] Rust Android 编译目标" -ForegroundColor Cyan
$requiredTargets = @(
  'aarch64-linux-android',
  'armv7-linux-androideabi',
  'i686-linux-android',
  'x86_64-linux-android'
)

if ($null -eq (Get-ExePath 'rustup.exe')) {
  Write-Fail "未找到 rustup，请从 https://rustup.rs 安装"
} else {
  $installedTargets = Get-RustupInstalledTarget
  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($t in $requiredTargets) {
    if ($installedTargets -contains $t) {
      Write-Ok "  $t"
    } else {
      $missing.Add($t) | Out-Null
      Write-Fail "  $t（未安装）"
    }
  }

  if ($missing.Count -gt 0) {
    Write-Host ""
    if (Confirm-Install "安装缺失的 Rust Android 编译目标（$($missing.Count) 个）") {
      Enable-AutoConfirm
      foreach ($t in $missing) {
        Write-Host "  rustup target add $t" -ForegroundColor Cyan
        Invoke-NativeStream -Block { & rustup target add $t }
        if ($LASTEXITCODE -eq 0) { Write-Ok "  $t 安装成功" }
        else { Write-Warn "  $t 安装失败，请手动运行：rustup target add $t" }
      }
    } else {
      Write-Warn "请手动运行以下命令安装缺失的编译目标："
      foreach ($t in $missing) { Write-Host "    rustup target add $t" }
    }
  }
}

Write-Host "[7/8] pnpm" -ForegroundColor Cyan
$pnpmExe = Get-PnpmExe
if ($pnpmExe) {
  $v = (Invoke-NativeText -FilePath $pnpmExe -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "pnpm $v 已安装"
} else {
  Write-Fail "未找到 pnpm"
  if (Confirm-Install "通过 npm 全局安装 pnpm") {
    Enable-AutoConfirm
    Invoke-NativeStream -Block { & npm install -g pnpm }
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "npm install -g pnpm 失败"
    } else {
      $pnpmExe = Get-PnpmExe
      $v = (Invoke-NativeText -FilePath $pnpmExe -Arguments @('--version') | Select-Object -First 1)
      Write-Ok "pnpm $v 安装成功"
    }
  } else {
    Write-Fail "请手动安装：npm install -g pnpm"
  }
}

Write-Host "[8/8] keystore.properties" -ForegroundColor Cyan
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$keystoreProps = Join-Path $scriptDir '..\backend\src-tauri\gen\android\keystore.properties'

if (Test-Path -LiteralPath $keystoreProps) {
  Write-Ok "keystore.properties 已找到：$keystoreProps"
} else {
  Write-Warn "keystore.properties 未找到：$keystoreProps"
  if (Confirm-Install "创建默认 keystore.properties 文件") {
    New-DirectoryIfMissing (Split-Path -Parent $keystoreProps)
    $DefaultKeystoreLines | Set-Content -LiteralPath $keystoreProps -Encoding UTF8
    Write-Ok "keystore.properties 已创建：$keystoreProps"
  } else {
    Write-Warn "请手动创建该文件，内容如下："
    Write-Host "    storeFile=C:\path\to\release.keystore"
    Write-Host "    storePassword=your_store_password"
    Write-Host "    keyAlias=your_key_alias"
    Write-Host "    keyPassword=your_key_password"
    Write-Warn "生成 keystore："
    Write-Host "    keytool -genkeypair -v -keystore release.keystore -alias tauri2demo-key -keyalg RSA -keysize 2048 -validity 10000"
  }
}

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
if ($Failed) {
  Write-Host "  环境检查未通过，请修复以上问题后重试。" -ForegroundColor Red
  Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
  exit 1
}
Write-Host "  所有检查通过！" -ForegroundColor Green
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Banner -Title '构建准备                                ' -Color Cyan
Write-Host ""

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..')).Path
$genAndroidDir = Join-Path $projectRoot 'backend\src-tauri\gen\android'

Write-Host "[准备 1/4] npm 依赖" -ForegroundColor Cyan
if (Test-Path -LiteralPath (Join-Path $projectRoot 'node_modules')) {
  Write-Ok "node_modules 已存在"
} else {
  Write-Warn "node_modules 不存在，正在运行 pnpm install ..."
  Invoke-NativeStreamIn -Path $projectRoot -Block { & pnpm install }
  Write-Ok "pnpm install 完成"
}

Write-Host "[准备 2/4] Tauri Android 项目" -ForegroundColor Cyan
if (Test-AndroidProjectComplete $genAndroidDir) {
  Write-Ok "gen\android 项目完整"
} else {
  Restore-AndroidProject -ProjectRoot $projectRoot -GenAndroidDir $genAndroidDir -ScriptDir $scriptDir
}

Write-Host "[准备 3/4] 前端构建" -ForegroundColor Cyan
if (Test-Path -LiteralPath (Join-Path $projectRoot 'frontend\dist')) {
  Write-Ok "frontend\dist 已存在"
} else {
  Write-Warn "frontend\dist 不存在，正在运行前端构建 ..."
  Invoke-NativeStreamIn -Path $projectRoot -Block { & pnpm build }
  Write-Ok "前端构建完成"
}

Write-Host "[准备 4/4] Keystore 签名文件" -ForegroundColor Cyan
$keystoreProps2 = Join-Path $genAndroidDir 'keystore.properties'
if (Test-Path -LiteralPath $keystoreProps2) {
  $props = Get-Content -LiteralPath $keystoreProps2 -ErrorAction SilentlyContinue
  $storeFileRaw = Get-PropValue -Lines $props -Key 'storeFile'
  $keyAlias = Get-PropValue -Lines $props -Key 'keyAlias'
  $keyPassword = Get-PropValue -Lines $props -Key 'password'

  if (-not [string]::IsNullOrWhiteSpace($storeFileRaw) -and (Test-Path -LiteralPath $storeFileRaw)) {
    Write-Ok "Keystore 文件已存在：$storeFileRaw"
  } elseif (-not [string]::IsNullOrWhiteSpace($storeFileRaw)) {
    Write-Warn "Keystore 文件不存在：$storeFileRaw"
    Write-Warn "正在自动生成 keystore ..."
    $aliasToUse = if ([string]::IsNullOrWhiteSpace($keyAlias)) { 'tauri2demo_key' } else { $keyAlias }
    $passwordToUse = if ([string]::IsNullOrWhiteSpace($keyPassword)) { 'changeit' } else { $keyPassword }
    New-Keystore -StoreFile $storeFileRaw -Alias $aliasToUse -Password $passwordToUse
  } else {
    Write-Warn "keystore.properties 中未找到 storeFile=，跳过 keystore 文件检查"
  }
} else {
  Write-Warn "keystore.properties 不存在，跳过 keystore 文件检查"
}

Write-Host ""
Write-Host "  构建准备完成！" -ForegroundColor Green
Write-Host ""

$env:ANDROID_HOME = $androidHome
Add-PathPrefix (Join-Path $androidHome 'platform-tools')

if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_NDK_HOME)) {
  $toolchainBin = Join-Path $env:ANDROID_NDK_HOME 'toolchains\llvm\prebuilt\windows-x86_64\bin'
  if (Test-Path -LiteralPath $toolchainBin) {
    $env:CC = Join-Path $toolchainBin 'clang.exe'
    $env:CXX = Join-Path $toolchainBin 'clang++.exe'
    Write-Host "  使用 NDK clang：$toolchainBin" -ForegroundColor Yellow
  } else {
    Write-Warn "NDK toolchain 目录未找到：$toolchainBin"
    Write-Warn "将使用系统默认编译器"
  }
}

if ($null -ne (Get-ExePath 'rustup.exe')) {
  $rustcPath = Invoke-NativeText -FilePath 'rustup' -Arguments @('which', 'rustc') | Select-Object -First 1
  if (-not [string]::IsNullOrWhiteSpace($rustcPath)) {
    $toolchainRoot = Split-Path -Parent (Split-Path -Parent $rustcPath.Trim())
    $selfContained = Join-Path $toolchainRoot 'lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained'
    if (Test-Path -LiteralPath (Join-Path $selfContained 'dlltool.exe')) {
      Add-PathPrefix $selfContained
      Write-Ok "Rust dlltool 已加入 PATH：$selfContained"
    } else {
      Write-Warn "Rust GNU 工具链 self-contained 目录未找到：$selfContained"
      Write-Warn "交叉编译 Android 时可能因找不到 dlltool 而失败"
    }
  }
}

$env:CARGO_BUILD_JOBS = '1'
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=1'
Write-Host "  CARGO_BUILD_JOBS=1, Gradle workers=1（避免内存溢出）" -ForegroundColor Yellow
Write-Host ""

Write-Host "执行：pnpm tauri android $Command" -ForegroundColor Cyan
Write-Host ""

$code = 1
Push-Location $projectRoot
try {
  & pnpm tauri android $Command
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}
exit $code
