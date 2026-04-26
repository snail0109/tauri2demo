param(
  [Parameter(Position = 0)]
  [ValidateSet('dev', 'build')]
  [string]$Command,

  [Parameter(Position = 1)]
  [Alias('y')]
  [switch]$Yes,

  [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

$DefaultKeystoreLines = @(
  'keyAlias=tauri2demo_key',
  'password=abc009988',
  'storeFile=./config/release.keystore'
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

if ([string]::IsNullOrWhiteSpace($Command) -and -not $CheckOnly) {
  Write-Host "用法：$($MyInvocation.MyCommand.Name) <dev|build> [-y] [-CheckOnly]" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  dev        启动 Tauri Android 开发模式（热重载）"
  Write-Host "  build      构建 Android APK/AAB 发布包"
  Write-Host "  -y         自动确认所有安装提示（静默模式）"
  Write-Host "  -CheckOnly 仅检查环境，不执行构建"
  exit 1
}

Write-Host ""
Write-Banner -Title 'Android 构建环境检查（Windows PowerShell）' -Color Cyan
Write-Host ""

# 静默解析 ANDROID_HOME / NDK：后续 $env:ANDROID_HOME / ANDROID_NDK_HOME / CC / CXX 都依赖它们。
# C/C++ 编译器、Rust、Java、SDK 工具的体检放在 install_c_compile_bywin.ps1 / install_android_sdk_bywin.ps1，
# 本脚本不再重复，只在必需路径缺失时给出明确的"请去跑哪个脚本"提示。
$androidHome = Resolve-AndroidHome
if ($null -eq $androidHome) {
  Write-Fail "ANDROID_HOME 未设置且未检测到 Android SDK"
  Write-Fail "请先运行 .\script\install_android_sdk_bywin.ps1"
  exit 1
}
$env:ANDROID_HOME = $androidHome

$ndkInfo = Resolve-AndroidNdk $androidHome
if ($ndkInfo -and [string]::IsNullOrWhiteSpace($env:ANDROID_NDK_HOME)) {
  $env:ANDROID_NDK_HOME = $ndkInfo.Path
}

Write-Host "[1/3] Rust Android 编译目标" -ForegroundColor Cyan
$requiredTargets = Get-AndroidRustTarget
if ($null -eq (Get-ExePath 'rustup.exe')) {
  Write-Fail "未找到 rustup，请先运行 .\script\install_c_compile_bywin.ps1"
} else {
  $installedTargets = Get-RustupInstalledTarget
  $missing = @($requiredTargets | Where-Object { $installedTargets -notcontains $_ })
  foreach ($t in $requiredTargets) {
    if ($installedTargets -contains $t) { Write-Ok "  $t" } else { Write-Fail "  $t（未安装）" }
  }
  if ($missing.Count -gt 0) {
    Write-Fail "缺少 $($missing.Count) 个 Rust Android 编译目标，请运行 .\script\install_android_sdk_bywin.ps1 安装"
  }
}

Write-Host "[2/3] pnpm" -ForegroundColor Cyan
$pnpmExe = Get-PnpmExe
if ($pnpmExe) {
  $v = (Invoke-NativeText -FilePath $pnpmExe -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "pnpm $v 已安装"
} else {
  Write-Fail "未找到 pnpm，请手动运行：npm install -g pnpm"
}

Write-Host "[3/3] keystore.properties" -ForegroundColor Cyan
$scriptDir = $PSScriptRoot
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
if ($Failed) {
  Write-Banner -Title '环境检查未通过，请修复以上问题后重试。' -Color Cyan -TitleColor Red
  exit 1
}
Write-Banner -Title '所有检查通过！' -Color Cyan -TitleColor Green
Write-Host ""
if ($CheckOnly) { exit 0 }

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

  # gradle 在 gen\android\app\build.gradle.kts 里通过 file() 解析 storeFile，
  # 相对路径基准是 gen\android\app。脚本侧对齐这个基准，避免脚本生成的 keystore 跟 gradle 找的不是同一个文件。
  $storeFileResolved = $storeFileRaw
  if (-not [string]::IsNullOrWhiteSpace($storeFileRaw) -and -not [System.IO.Path]::IsPathRooted($storeFileRaw)) {
    $storeFileResolved = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $genAndroidDir 'app') $storeFileRaw))
  }

  if (-not [string]::IsNullOrWhiteSpace($storeFileRaw) -and (Test-Path -LiteralPath $storeFileResolved)) {
    Write-Ok "Keystore 文件已存在：$storeFileResolved"
  } elseif (-not [string]::IsNullOrWhiteSpace($storeFileRaw)) {
    Write-Warn "Keystore 文件不存在：$storeFileResolved"
    Write-Warn "正在自动生成 keystore ..."
    $aliasToUse = if ([string]::IsNullOrWhiteSpace($keyAlias)) { 'tauri2demo_key' } else { $keyAlias }
    $passwordToUse = if ([string]::IsNullOrWhiteSpace($keyPassword)) { 'changeit' } else { $keyPassword }
    New-Keystore -StoreFile $storeFileResolved -Alias $aliasToUse -Password $passwordToUse
  } else {
    Write-Warn "keystore.properties 中未找到 storeFile=，跳过 keystore 文件检查"
  }
} else {
  Write-Warn "keystore.properties 不存在，跳过 keystore 文件检查"
}

Write-Host ""
Write-Host "  构建准备完成！" -ForegroundColor Green
Write-Host ""

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
