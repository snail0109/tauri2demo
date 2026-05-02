<#
.SYNOPSIS
  在 Windows 上检查并构建 Tauri Android（dev/build），并做必要的环境自愈与内存参数优化。
.DESCRIPTION
  主要流程：
  - 先做 8 项环境检查（C/C++、Rust、Java 17、Android SDK/NDK、Rust targets、pnpm、keystore.properties）
  - 准备阶段：pnpm install、修复/重建 gen\android、前端构建
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
  重建 gen\android 工程：清残留 → pnpm tauri android init → 调优 gradle.properties。
.PARAMETER ProjectRoot
  项目根目录（用于运行 pnpm tauri android init）。
.PARAMETER GenAndroidDir
  gen\android 目录路径。
.NOTES
  - 会停止可能锁定目录的 Gradle/Kotlin Daemon，降低 Windows 删除失败概率
  - keystore.properties 已统一放在 config\，不再在 gen\android 下管理
#>
function Restore-AndroidProject {
  param(
    [Parameter(Mandatory)] [string]$ProjectRoot,
    [Parameter(Mandatory)] [string]$GenAndroidDir
  )

  # 停止可能锁定 gen\android 的 Gradle/Kotlin Daemon，否则 Windows 上删不动
  if (Get-Command 'jps' -ErrorAction SilentlyContinue) {
    $procs = (& jps) | Where-Object { $_ -match 'GradleDaemon|GradleServer|KotlinCompileDaemon' }
    if ($procs) {
      Write-Warn "检测到 Gradle/Kotlin Daemon，正在停止 ..."
      foreach ($p in $procs) {
        $procId = ($p -split '\s+')[0]
        if ($procId -match '^\d+$') {
          Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
      }
      Start-Sleep -Milliseconds 500
    }
  }

  # 删除残留 gen\android（带一次重试，应对偶发文件锁定）
  if (Test-Path -LiteralPath $GenAndroidDir) {
    Write-Warn "清理安卓 gen\android 目录 : $GenAndroidDir"
    Remove-Item -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $GenAndroidDir) {
      Start-Sleep -Milliseconds 200
      Get-ChildItem -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $GenAndroidDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $GenAndroidDir) {
      Write-Fail "gen\android 删除失败，请手动删除后重试"
      return
    }
  }

  # 重新初始化 Android 工程
  Write-Host "  运行命令：pnpm tauri android init" -ForegroundColor Cyan
  Invoke-NativeStreamIn -Path $ProjectRoot -Block { & pnpm tauri android init }
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "pnpm tauri android init 失败（exit code $LASTEXITCODE）"
    return
  }

  # 调整 gradle.properties：限制内存，避免 ≤7GB RAM 机器上 OOM
  $gradlePropsPath = Join-Path $GenAndroidDir 'gradle.properties'
  write-host "Gradle配置 (gradle.properties) : $gradlePropsPath"
  if (Test-Path -LiteralPath $gradlePropsPath) {
    $propsContent = Get-Content -LiteralPath $gradlePropsPath -Raw
    $propsContent = $propsContent -replace 'org\.gradle\.jvmargs=.*', 'org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8'
    if ($propsContent -notmatch 'org\.gradle\.daemon=') {
      $propsContent += "`norg.gradle.daemon=true"
    }
    else {
      $propsContent = $propsContent -replace 'org\.gradle\.daemon=false', 'org.gradle.daemon=true'
    }
    [System.IO.File]::WriteAllText($gradlePropsPath, $propsContent, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "gradle.properties 已调整：启用 Daemon、-Xmx2048m"
  }

  Set-GradleWrapperMirror $GenAndroidDir

  Write-Ok "gen\android 已重建"
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
$hasGnu = Test-Gnu
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
    }
    else {
      Write-Fail "pnpm 自动安装失败，请手动安装：npm install -g pnpm"
    }
  }
}

Write-Host "[8/8] 检查 keystore.properties" -ForegroundColor Cyan
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$keystoreProps = Join-Path $projectRoot 'config\keystore.properties'

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
  # 获取 storeFile 路径
  $storeFileResolved = if ([System.IO.Path]::IsPathRooted($storeFileRaw)) {
    $storeFileRaw # 绝对路径，直接使用
  }
  else {
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot $storeFileRaw)) # 相对路径，转换为绝对路径
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

Write-Host "[准备 1/3] npm 依赖" -ForegroundColor Cyan
Write-Warn "正在运行 pnpm install ..."
write-host "  运行命令：pnpm install --config.node-linker=hoisted" -ForegroundColor Cyan
Invoke-NativeStreamIn -Path $projectRoot -Block { & pnpm install --config.node-linker=hoisted }
if ($LASTEXITCODE -ne 0) { Write-Fail "pnpm install 失败" }
else { Write-Ok "pnpm install 完成" }

Write-Host "[准备 2/3] Tauri Android 项目" -ForegroundColor Cyan
# GRADLE_USER_HOME：避免 Users 目录下 Windows 安全策略阻止 daemon fork 子进程
# 若用户级环境变量已有值则沿用，否则写入默认值 C:\GradleHome
$userGradleHome = [Environment]::GetEnvironmentVariable('GRADLE_USER_HOME', 'User')
if (-not [string]::IsNullOrWhiteSpace($userGradleHome)) {
  $gradleHome = $userGradleHome
  Write-Ok "GRADLE_USER_HOME 已存在（用户级）：$gradleHome"
}
else {
  $gradleHome = 'C:\GradleHome'
  [Environment]::SetEnvironmentVariable('GRADLE_USER_HOME', $gradleHome, 'User')
  Write-Ok "GRADLE_USER_HOME 已写入用户环境变量：$gradleHome"
}
if (-not (Test-Path -LiteralPath $gradleHome)) { New-Item -ItemType Directory -Force -Path $gradleHome | Out-Null }
$env:GRADLE_USER_HOME = $gradleHome
$genAndroidDir = Join-Path $projectRoot 'backend\src-tauri\gen\android'
if (Test-AndroidProjectComplete $genAndroidDir) {
  Write-Ok "gen\android 项目完整"
  Set-GradleWrapperMirror $genAndroidDir
  # 修复 gradle.properties（tauri init 生成的默认值会导致 Windows 上 daemon 启动失败）
  $gp = Join-Path $genAndroidDir 'gradle.properties'
  if (Test-Path -LiteralPath $gp) {
    $pc = Get-Content -LiteralPath $gp -Raw
    $pc = $pc -replace 'org\.gradle\.jvmargs=.*', 'org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8'
    if ($pc -notmatch 'org\.gradle\.daemon=') { $pc += "`norg.gradle.daemon=true" }
    else { $pc = $pc -replace 'org\.gradle\.daemon=false', 'org.gradle.daemon=true' }
    [System.IO.File]::WriteAllText($gp, $pc, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "gradle.properties 已检查：Daemon=true、-Xmx2048m"
  }
}
else {
  Restore-AndroidProject -ProjectRoot $projectRoot -GenAndroidDir $genAndroidDir
  if ($Failed) { exit 1 }
}

Write-Host "[准备 3/3] 前端构建" -ForegroundColor Cyan
Write-Warn "正在运行前端构建 ..."
write-host "  运行命令：pnpm build" -ForegroundColor Cyan
Invoke-NativeStreamIn -Path $projectRoot -Block { & pnpm build }
if ($LASTEXITCODE -ne 0) { Write-Fail "前端构建失败" }
else { Write-Ok "前端构建完成" }

Write-Host ""
Write-Host "  构建准备完成！" -ForegroundColor Green
Write-Host ""
Add-PathPrefix (Join-Path $androidHome 'platform-tools')
Set-AndroidNdkEnv -AndroidNdkHome $env:ANDROID_NDK_HOME

# ── Cargo 交叉编译 linker 环境变量（双重保障 .cargo/config.toml） ──
$ndkToolchainBin = Join-Path $env:ANDROID_NDK_HOME 'toolchains\llvm\prebuilt\windows-x86_64\bin'
if (Test-Path -LiteralPath $ndkToolchainBin) {
  $apiLevel = 21
  foreach ($t in (Get-AndroidRustTarget)) {
    $linker = Join-Path $ndkToolchainBin "${t}${apiLevel}-clang.cmd"
    if (Test-Path -LiteralPath $linker) {
      $envName = "CARGO_TARGET_$(($t -replace '-', '_').ToUpper())_LINKER"
      Set-Item -Path "env:$envName" -Value $linker
      Write-Ok "$envName = $linker"
    }
  }
}

# ── GNU 工具链 Android 交叉编译说明 ──
# dlltool 和 MinGW 库目录仅供 Windows 桌面构建使用（GNU 工具链链接 Windows DLL 导入库）。
# Android 交叉编译使用 NDK 工具链（clang/llvm-ar），不需要 dlltool。
# 若将 dlltool 加入 PATH，cc crate / rustc 可能误用于 Android 目标，导致 CreateProcess 失败。
if ($RustcHost -match 'gnu') {
  Write-Host "  GNU 工具链 + Android 交叉编译：跳过 dlltool / MinGW 配置（Android 使用 NDK 工具链）" -ForegroundColor Cyan
}

# 加载 .env 文件中的环境变量（env!() 宏在编译时需要）
$envFile = Join-Path $projectRoot '.env'
Write-Ok "  加载环境变量文件：$envFile"
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
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2'
$env:NODE_OPTIONS = '--max-old-space-size=8192 --max-semi-space-size=512'
Write-Ok "  Set CARGO_BUILD_JOBS=1, Gradle workers=2, NODE_OPTIONS=--max-old-space-size=8192（避免内存溢出）"
Write-Host ""

Write-Host "  运行命令：pnpm tauri android $Command" -ForegroundColor Cyan
Write-Host ""

$code = 1
Push-Location $projectRoot
try {
  & pnpm tauri android $Command
  $code = $LASTEXITCODE
}
finally {
  Pop-Location
}
exit $code
