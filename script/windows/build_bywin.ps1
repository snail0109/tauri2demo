<#
.SYNOPSIS
  在 Windows 上检查并构建 Tauri Android（dev/build），并做必要的环境自愈与内存参数优化。
.DESCRIPTION
  主要流程：
  - 先做 8 项环境检查（C/C++、Rust、Java 17、Android SDK/NDK、Rust targets、pnpm、keystore.properties）
  - 准备阶段：pnpm install、修复/重建 gen\android、前端构建、keystore 文件检查/生成
  - 运行 pnpm tauri android <dev|build>
.PARAMETER Command
  dev=开发模式，build=发布构建，check=仅检查环境不构建。
.PARAMETER Yes
  自动确认（静默模式）。
#>
param(
  [Parameter(Position = 0)]
  [ValidateSet('dev', 'build', 'check')]
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
  'password=tauri2demo_pass',
  'storeFile=./config/release.keystore'
)

<#
.SYNOPSIS
  判断 gen\android 是否为“结构完整”的 Android 工程（避免 tauri init/build 报错）。
.PARAMETER GenAndroidDir
  gen\android 目录路径。
.OUTPUTS
  [bool]
#>
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

<#
.SYNOPSIS
  修复/重建 gen\android 目录：必要时清理残留、重新执行 tauri android init，并恢复签名/权限配置。
.PARAMETER ProjectRoot
  项目根目录（用于运行 pnpm tauri android init）。
.PARAMETER GenAndroidDir
  gen\android 目录路径。
.PARAMETER ScriptDir
  脚本目录路径（用于定位 android-permission-sign 下的覆盖文件）。
.NOTES
  - 会尽量停止可能锁定目录的 Gradle Daemon/JVM 进程，降低删除失败概率
  - 会备份并恢复 keystore.properties，避免重建后丢失签名配置
#>
function Restore-AndroidProject {
  param([string]$ProjectRoot, [string]$GenAndroidDir, [string]$ScriptDir)

  $keystorePropsInGen = Join-Path $GenAndroidDir 'keystore.properties'
  $keystoreBackup = $null
  if (Test-Path -LiteralPath $keystorePropsInGen) {
    $keystoreBackup = [System.IO.Path]::GetTempFileName()
    Copy-Item -LiteralPath $keystorePropsInGen -Destination $keystoreBackup -Force
    Write-Warn "已备份 keystore.properties"
  }

  # 停止可能锁定 gen\android 的 Gradle Daemon，否则删除会失败
  $jpsExe = Get-Command 'jps' -ErrorAction SilentlyContinue
  if ($jpsExe) {
    $gradleProcs = (& jps) | Where-Object { $_ -match 'GradleDaemon|GradleServer|KotlinCompileDaemon' }
    if ($gradleProcs) {
      Write-Warn "检测到 Gradle Daemon 进程，正在停止 ..."
      foreach ($proc in $gradleProcs) {
        $procId = ($proc -split '\s+')[0]
        if ($procId -match '^\d+$') {
          Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
      }
      Start-Sleep -Milliseconds 500
    }
  }

  Write-Warn "正在删除不完整的 gen\android 目录 ... $GenAndroidDir"
  if (Test-Path -LiteralPath $GenAndroidDir) {
    Remove-Item -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue
    # Windows 上 Remove-Item 偶尔会有残留，确认清理
    if (Test-Path -LiteralPath $GenAndroidDir) {
      Start-Sleep -Milliseconds 200
      Remove-Item -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $GenAndroidDir) {
      Write-Warn "未能完全删除 gen\android，尝试强制清理 ..."
      Get-ChildItem -LiteralPath $GenAndroidDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  # Confirm-Step -Desc "$Desc 是否继续？"

  write-host "  运行命令：pnpm tauri android init" -ForegroundColor Cyan
  Invoke-NativeStreamIn -Path $ProjectRoot -Block { & pnpm tauri android init }
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "pnpm tauri android init 失败（exit code $LASTEXITCODE）"
    if ($keystoreBackup -and (Test-Path -LiteralPath $keystoreBackup)) {
      Remove-Item -LiteralPath $keystoreBackup -Force -ErrorAction SilentlyContinue
    }
    return
  }

  Write-Host "  keystore.properties => $keystorePropsInGen" -ForegroundColor Cyan
  Write-Host "  keystore.properties (备份) => $keystoreBackup" -ForegroundColor Cyan
  if ($keystoreBackup -and (Test-Path -LiteralPath $keystoreBackup) -and (Test-Path -LiteralPath $GenAndroidDir)) {
    Copy-Item -LiteralPath $keystoreBackup -Destination $keystorePropsInGen -Force
    Remove-Item -LiteralPath $keystoreBackup -Force -ErrorAction SilentlyContinue
    Write-Ok "keystore.properties 已恢复"
  }
  elseif (-not (Test-Path -LiteralPath $keystorePropsInGen) -and (Test-Path -LiteralPath $GenAndroidDir)) {
    Write-Warn "正在写入 keystore.properties ..."
    New-DirectoryIfMissing (Split-Path -Parent $keystorePropsInGen)
    [System.IO.File]::WriteAllLines($keystorePropsInGen, $DefaultKeystoreLines, [System.Text.UTF8Encoding]::new($false))
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
    }
    else {
      Write-Warn "$($c.Label) 源文件不存在，跳过替换"
    }
  }

  # 降低 Gradle Daemon 内存限制7GB 内7GB 内存系统上崩溃
  $gradlePropsPath = Join-Path $GenAndroidDir 'gradle.properties'
  write-host "  降低 Gradle Daemon 内存限制7GB 内7GB 内存系统上崩溃 ($gradlePropsPath)" -ForegroundColor Cyan
  if (Test-Path -LiteralPath $gradlePropsPath) {
    $propsContent = Get-Content -LiteralPath $gradlePropsPath -Raw
    # 禁用 Daemon + 降低堆内存 + 降低线程栈大小
    $propsContent = $propsContent -replace 'org\.gradle\.jvmargs=-Xmx2048m', 'org.gradle.jvmargs=-Xmx768m -Xss256k -Dfile.encoding=UTF-8'
    if ($propsContent -notmatch 'org\.gradle\.daemon=') {
      $propsContent += "`norg.gradle.daemon=false"
    }
    [System.IO.File]::WriteAllText($gradlePropsPath, $propsContent, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "gradle.properties 已调整：禁用 Daemon、-Xmx768m、-Xss256k"
  }

  Write-Ok "pnpm tauri android init 完成"
}

<#
.SYNOPSIS
  通过 keytool 生成 Android 签名 keystore 文件（供 release 构建使用）。
.PARAMETER StoreFile
  keystore 文件路径（可为绝对路径）。
.PARAMETER Alias
  keyAlias。
.PARAMETER Password
  store/key 密码（keystore.properties 里通常明文存储）。
.NOTES
  若未找到 keytool.exe，会给出手动命令提示。
#>
function New-Keystore {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'keystore.properties stores password as plain text by design; this script merely passes it to keytool')]
  param([string]$StoreFile, [string]$Alias, [string]$Password)
  if ($null -eq (Get-ExePath 'keytool.exe')) {
    Write-Fail "keytool 未找到，无法自动生成 keystore"
    Write-Fail "请手动运行：keytool -genkeypair -v -keystore `"$StoreFile`" -alias $Alias --storepass $Password -keypass $Password -keyalg RSA -keysize 2048 -validity 10000 -dname `"CN=Alex, OU=NJ, O=YjSoft, L=City, S=State, C=CN`""
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
  }
  else {
    Write-Fail "keytool 生成 keystore 失败"
    Write-Fail "请手动运行：keytool -genkeypair -v -keystore `"$StoreFile`" -alias $Alias --storepass $Password -keypass $Password -keyalg RSA -keysize 2048 -validity 10000 -dname `"CN=Alex, OU=NJ, O=YjSoft, L=City, S=State, C=CN`""
  }
}

if ([string]::IsNullOrWhiteSpace($Command)) {
  Write-Host "用法：$($MyInvocation.MyCommand.Name) <dev|build|check> [-y]" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  dev        启动 Tauri Android 开发模式（热重载）"
  Write-Host "  build      构建 Android APK/AAB 发布包"
  Write-Host "  check      仅检查环境，不执行构建"
  Write-Host "  -y         自动确认所有安装提示（静默模式）"
  exit 1
}

Write-Host ""
Write-Banner -Title 'Android 构建环境检查（Windows PowerShell）' -Color Cyan
Write-Host ""

Write-Host "[1/8] C/C++ 编译工具" -ForegroundColor Cyan
$hasMsvc = Test-Msvc
$hasGnu   = Test-Gnu
if (-not $hasMsvc -and -not $hasGnu) {
  Write-Fail "未检测到 C/C++ 编译器（MSVC 或 GNU gcc）"
  Write-Fail "请运行 .\script\install_2_c_compile_bywin.ps1 安装"
}

Write-Host "[2/8] Rust" -ForegroundColor Cyan
if ($null -ne (Get-ExePath 'rustc.exe')) {
Test-RustToolchain | Out-Null
}
else {
  Write-Fail "未检测到 rustc/rustup"
  Write-Fail "请运行 .\script\install_c_compile_bywin.ps1 安装"
}

Write-Host "[3/8] Java JDK（17+）" -ForegroundColor Cyan
Assert-Java17 | Out-Null

Write-Host "[4/8] Android SDK" -ForegroundColor Cyan
$androidHome = Resolve-AndroidHome
if ($null -ne $androidHome) {
  $env:ANDROID_HOME = $androidHome
  $platformsDir = Join-Path $androidHome 'platforms'
  $sdkDetails = if (Test-Path -LiteralPath $platformsDir) {
    @(Get-ChildItem -LiteralPath $platformsDir -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^android-(\d+)$' } |
      Sort-Object { [int]($Matches[0] -replace '\D') } |
      ForEach-Object {
        $api = $Matches[1]
        $sp = Join-Path $_.FullName 'source.properties'
        $platVer = if (Test-Path -LiteralPath $sp) { (Get-PropValue -Lines (Get-Content -LiteralPath $sp) -Key 'Platform.Version') } else { '' }
        if ($platVer) { "API $api (Android $platVer)" } else { "API $api" }
      })
  }
  else { @() }
  $sdkStr = if ($sdkDetails.Count -gt 0) { $sdkDetails -join ', ' } else { '无 platform' }
  Write-Ok "Android SDK：$sdkStr（$androidHome）"
}
else {
  Write-Fail "ANDROID_HOME 未设置且未检测到 Android SDK"
  Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装"
}

Write-Host "[5/8] Android NDK" -ForegroundColor Cyan
$ndkInfo = if ($androidHome) { Resolve-AndroidNdk $androidHome } else { $null }
if ($ndkInfo) {
  if ([string]::IsNullOrWhiteSpace($env:ANDROID_NDK_HOME)) { $env:ANDROID_NDK_HOME = $ndkInfo.Path }
  # 从 ndk/source.properties 提取精确版本号
  $ndkProp = Join-Path $ndkInfo.Path 'source.properties'
  $ndkVer = if (Test-Path -LiteralPath $ndkProp) { (Get-PropValue -Lines (Get-Content -LiteralPath $ndkProp) -Key 'Pkg.Revision') } else { $ndkInfo.Version }
  Write-Ok "Android NDK：$ndkVer（$($ndkInfo.Path)）"
}
else {
  Write-Fail "未找到 Android NDK"
  Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装"
}

Write-Host "[6/8] Rust Android 编译目标" -ForegroundColor Cyan
$requiredTargets = Get-AndroidRustTarget
if ($null -eq (Get-ExePath 'rustup.exe')) {
  Write-Fail "未找到 rustup"
  Write-Fail "请运行 .\script\install_c_compile_bywin.ps1 安装"
}
else {
  $installedTargets = Get-RustupInstalledTarget
  $missing = @($requiredTargets | Where-Object { $installedTargets -notcontains $_ })
  foreach ($t in $requiredTargets) {
    if ($installedTargets -contains $t) { Write-Ok "  $t" } else { Write-Fail "  $t（未安装）" }
  }
  if ($missing.Count -gt 0) {
    Write-Fail "缺少 $($missing.Count) 个 Rust Android 编译目标"
    Write-Fail "请运行 .\script\install_android_sdk_bywin.ps1 安装"
  }
}

Write-Host "[7/8] 检查 pnpm 编译环境" -ForegroundColor Cyan
$pnpmExe = Get-PnpmExe
if ($pnpmExe) {
  $v = (Invoke-NativeText -FilePath $pnpmExe -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "pnpm $v 已安装"
}
else {
  Write-Warn "未找到 pnpm，准备自动安装 ..."
    $npm = Get-ExePath 'npm.cmd'
    if (-not $npm) { $npm = Get-ExePath 'npm.exe' }
    if (-not $npm) {
      Write-Fail "未找到 npm，无法自动安装 pnpm"
      Write-Fail "请先安装 Node.js，然后重试"
    }
    else {
      Write-Host "  运行命令：npm install -g pnpm" -ForegroundColor Cyan
      Invoke-NativeStream -Block { & npm install -g pnpm }
      $pnpmExe = Get-PnpmExe
      if ($pnpmExe) {
        $v = (Invoke-NativeText -FilePath $pnpmExe -Arguments @('--version') | Select-Object -First 1)
        Write-Ok "pnpm $v 安装成功"
      } else {
        Write-Fail "pnpm 自动安装失败，请手动安装：npm install -g pnpm"
      }
    }
}

Write-Host "[8/8] 检查 keystore.properties" -ForegroundColor Cyan
$scriptDir = $PSScriptRoot
$keystoreProps = Join-Path $scriptDir '..\..\backend\src-tauri\gen\android\keystore.properties'

# 1. 如果 keystore.properties 不存在，通过 $DefaultKeystoreLines 生成默认文件
if (-not (Test-Path -LiteralPath $keystoreProps)) {
  Write-Warn "keystore.properties 未找到，正在创建默认文件 ..."
  New-DirectoryIfMissing (Split-Path -Parent $keystoreProps)
  [System.IO.File]::WriteAllLines($keystoreProps, $DefaultKeystoreLines, [System.Text.UTF8Encoding]::new($false))
  Write-Ok "keystore.properties 已创建：$keystoreProps"
}
else {
  Write-Ok "keystore.properties 已找到：$keystoreProps"
}

# 2. 读取 keystore.properties 中的 storeFile，检查对应的 keystore 文件是否存在
$props = Get-Content -LiteralPath $keystoreProps -ErrorAction SilentlyContinue
$storeFileRaw = Get-PropValue -Lines $props -Key 'storeFile'
$keyAlias = Get-PropValue -Lines $props -Key 'keyAlias'
$keyPassword = Get-PropValue -Lines $props -Key 'password'

if (-not [string]::IsNullOrWhiteSpace($storeFileRaw)) {
  # storeFile 相对路径基准是项目根目录
  $projectRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
  $storeFileResolved = if ([System.IO.Path]::IsPathRooted($storeFileRaw)) {
    $storeFileRaw
  }
  else {
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot $storeFileRaw))
  }

  if (Test-Path -LiteralPath $storeFileResolved) {
    Write-Ok "Keystore 文件已存在：$storeFileResolved"
  }
  else {
    # 3. 如果 storeFile 对应的文件不存在，通过 keytool 生成
    Write-Warn "Keystore 文件不存在：$storeFileResolved"
    Write-Warn "正在自动生成 keystore ..."
    $aliasToUse = if ([string]::IsNullOrWhiteSpace($keyAlias)) { 'tauri2demo_key' } else { $keyAlias }
    $passwordToUse = if ([string]::IsNullOrWhiteSpace($keyPassword)) { 'tauri2demo_pass' } else { $keyPassword }
    New-Keystore -StoreFile $storeFileResolved -Alias $aliasToUse -Password $passwordToUse
  }
}
else {
  Write-Warn "keystore.properties 中未找到 storeFile=，跳过 keystore 文件检查"
}

Write-Host ""
if ($Failed) {
  Write-Banner -Title '环境检查未通过，请修复以上问题后重试。' -Color Cyan -TitleColor Red
  exit 1
}

if ($Command -eq 'check') {
  Write-Banner -Title '所有检查通过！' -Color Cyan -TitleColor Green
  Write-Host ""
  exit 0
}

Write-Banner -Title '构建准备                                ' -Color Cyan
Write-Host ""

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..')).Path
$genAndroidDir = Join-Path $projectRoot 'backend\src-tauri\gen\android'

Write-Host "[准备 1/4] npm 依赖" -ForegroundColor Cyan
$tauriBin = Join-Path $projectRoot 'node_modules\.bin\tauri.cmd'
if ((Test-Path -LiteralPath (Join-Path $projectRoot 'node_modules')) -and (Test-Path -LiteralPath $tauriBin)) {
  Write-Ok "node_modules 已存在且 tauri CLI 可用"
}
else {
  Write-Warn "正在运行 pnpm install ..."
  write-host "  运行命令：pnpm install --config.node-linker=hoisted" -ForegroundColor Cyan
  Invoke-NativeStreamIn -Path $projectRoot -Block { & pnpm install --config.node-linker=hoisted }
  if ($LASTEXITCODE -ne 0) { Write-Fail "pnpm install 失败" }
  else { Write-Ok "pnpm install 完成" }
}

Write-Host "[准备 2/4] Tauri Android 项目" -ForegroundColor Cyan
if (Test-AndroidProjectComplete $genAndroidDir) {
  Write-Ok "gen\android 项目完整"
}
else {
  Restore-AndroidProject -ProjectRoot $projectRoot -GenAndroidDir $genAndroidDir -ScriptDir $scriptDir
  if ($Failed) {
    Write-Fail "gen\android 项目初始化失败，无法继续"
    exit 1
  }
}

Write-Host "[准备 3/4] 前端构建" -ForegroundColor Cyan
$tauriConfPath = Join-Path $projectRoot 'backend\src-tauri\tauri.conf.json'
$originalBeforeBuildCommand = $null
if (Test-Path -LiteralPath (Join-Path $projectRoot 'frontend\dist')) {
  Write-Ok "frontend\dist 已存在"
  # 临时清空 beforeBuildCommand，避免 Tauri 再次运行前端构建（在完整构建链中会导致 OOM）
  if (Test-Path -LiteralPath $tauriConfPath) {
    $confRaw = Get-Content -LiteralPath $tauriConfPath -Raw
    $m = [regex]::Match($confRaw, '"beforeBuildCommand"\s*:\s*"([^"]*)"')
    if ($m.Success) {
      $originalBeforeBuildCommand = $m.Groups[1].Value
      $confRaw = $confRaw -replace '"beforeBuildCommand"\s*:\s*"[^"]*"', '"beforeBuildCommand": ""'
      [System.IO.File]::WriteAllText($tauriConfPath, $confRaw, [System.Text.UTF8Encoding]::new($false))
      Write-Ok "已临时清空 tauri.conf.json 中的 beforeBuildCommand"
    }
  }
}
else {
  Write-Warn "frontend\dist 不存在，正在运行前端构建 ..."
  write-host "  运行命令：pnpm build" -ForegroundColor Cyan
  Invoke-NativeStreamIn -Path $projectRoot -Block { & pnpm build }
  if ($LASTEXITCODE -ne 0) { Write-Fail "前端构建失败" }
  else { Write-Ok "前端构建完成" }
}

Write-Host "[准备 4/4] Keystore 签名文件" -ForegroundColor Cyan
$keystoreProps2 = Join-Path $genAndroidDir 'keystore.properties'
if (Test-Path -LiteralPath $keystoreProps2) {
  $props = Get-Content -LiteralPath $keystoreProps2 -ErrorAction SilentlyContinue
  $storeFileRaw = Get-PropValue -Lines $props -Key 'storeFile'
  $keyAlias = Get-PropValue -Lines $props -Key 'keyAlias'
  $keyPassword = Get-PropValue -Lines $props -Key 'password'

  # storeFile 相对路径基准是项目根目录
  $storeFileResolved = $storeFileRaw
  if (-not [string]::IsNullOrWhiteSpace($storeFileRaw) -and -not [System.IO.Path]::IsPathRooted($storeFileRaw)) {
    $storeFileResolved = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $storeFileRaw))
  }

  if (-not [string]::IsNullOrWhiteSpace($storeFileRaw) -and (Test-Path -LiteralPath $storeFileResolved)) {
    Write-Ok "Keystore 文件已存在：$storeFileResolved"
  }
  elseif (-not [string]::IsNullOrWhiteSpace($storeFileRaw)) {
    Write-Warn "Keystore 文件不存在：$storeFileResolved"
    Write-Warn "正在自动生成 keystore ..."
    $aliasToUse = if ([string]::IsNullOrWhiteSpace($keyAlias)) { 'tauri2demo_key' } else { $keyAlias }
    $passwordToUse = if ([string]::IsNullOrWhiteSpace($keyPassword)) { 'changeit' } else { $keyPassword }
    New-Keystore -StoreFile $storeFileResolved -Alias $aliasToUse -Password $passwordToUse
  }
  else {
    Write-Warn "keystore.properties 中未找到 storeFile=，跳过 keystore 文件检查"
  }
}
else {
  Write-Warn "keystore.properties 不存在，跳过 keystore 文件检查"
}

Write-Host ""
Write-Host "  构建准备完成！" -ForegroundColor Green
Write-Host ""

Add-PathPrefix (Join-Path $androidHome 'platform-tools')

if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_NDK_HOME)) {
  $toolchainBin = Join-Path $env:ANDROID_NDK_HOME 'toolchains\llvm\prebuilt\windows-x86_64\bin'
  if (Test-Path -LiteralPath $toolchainBin) {
    # 为每个 Android 目标设置 CC / CXX / AR 环境变量，指向 NDK 工具。
    # 不将 NDK toolchain bin 加入 PATH，避免干扰 host 端 (gnu) 链接器。
    $llvmAr = Join-Path $toolchainBin 'llvm-ar.exe'
    foreach ($t in (Get-AndroidRustTarget)) {
      $underscore = $t -replace '-', '_'
      $clangCmd = Join-Path $toolchainBin "${t}21-clang.cmd"
      $clangxxCmd = Join-Path $toolchainBin "${t}21-clang++.cmd"
      Set-Item -Path "env:CC_$underscore" -Value $clangCmd
      Set-Item -Path "env:CXX_$underscore" -Value $clangxxCmd
      Set-Item -Path "env:AR_$underscore" -Value $llvmAr
    }
    Write-Ok "NDK clang/clang++/llvm-ar 已配置（CC/CXX/AR_<target>）：$toolchainBin"
  }
  else {
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
    }
    else {
      Write-Warn "Rust GNU 工具链 self-contained 目录未找到：$selfContained"
      Write-Warn "交叉编译 Android 时可能因找不到 dlltool 而失败"
    }
  }
}

# GNU 工具链链接时需要 MinGW 库目录（crt2.o, libkernel32.a 等）以及 GCC 运行时库目录（libgcc.a, libgcc_eh.a）
$mingwLibDir = 'C:\msys64\mingw64\lib'
$gccLibDirs = @(Get-ChildItem -LiteralPath 'C:\msys64\mingw64\lib\gcc\x86_64-w64-mingw32' -Directory -ErrorAction SilentlyContinue |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1 | ForEach-Object { $_.FullName })
if ((Test-Path -LiteralPath $mingwLibDir) -and $gcc) {
  $libPaths = @($mingwLibDir) + $gccLibDirs
  $env:LIBRARY_PATH = ($libPaths + $(if ($env:LIBRARY_PATH) { $env:LIBRARY_PATH -split ';' } else { @() })) -join ';'
  foreach ($p in $libPaths) { Write-Ok "LIBRARY_PATH 已追加：$p" }
}

# 加载 .env 文件中的环境变量（env!() 宏在编译时需要）
$envFile = Join-Path $projectRoot '.env'
if (Test-Path -LiteralPath $envFile) {
  $loaded = 0
  foreach ($line in (Get-Content -LiteralPath $envFile -ErrorAction SilentlyContinue)) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
    $eqIdx = $trimmed.IndexOf('=')
    if ($eqIdx -lt 1) { continue }
    $key = $trimmed.Substring(0, $eqIdx).Trim()
    $val = $trimmed.Substring($eqIdx + 1).Trim()
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      Set-Item -Path "env:$key" -Value $val
      $loaded++
    }
  }
  if ($loaded -gt 0) { Write-Ok ".env 已加载（$loaded 个环境变量）" }
}

$env:CARGO_BUILD_JOBS = '1'
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=1'
$env:NODE_OPTIONS = '--max-old-space-size=8192 --max-semi-space-size=512'
Write-Host "  CARGO_BUILD_JOBS=1, Gradle workers=1, NODE_OPTIONS=--max-old-space-size=8192（避免内存溢出）" -ForegroundColor Yellow
Write-Host ""

Write-Host "执行：pnpm tauri android $Command" -ForegroundColor Cyan
Write-Host ""

$code = 1
Push-Location $projectRoot
try {
  & pnpm tauri android $Command
  $code = $LASTEXITCODE
}
finally {
  Pop-Location
  # 恢复 beforeBuildCommand
  if ($originalBeforeBuildCommand -ne $null -and (Test-Path -LiteralPath $tauriConfPath)) {
    $confRaw = Get-Content -LiteralPath $tauriConfPath -Raw
    $confRaw = $confRaw -replace '"beforeBuildCommand"\s*:\s*""', "`"beforeBuildCommand`": `"$originalBeforeBuildCommand`""
    [System.IO.File]::WriteAllText($tauriConfPath, $confRaw, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "已恢复 tauri.conf.json 中的 beforeBuildCommand"
  }
}
exit $code
