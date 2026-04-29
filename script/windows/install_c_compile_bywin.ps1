param(
  [Alias('y')]
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$Failed = $false

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Yes) { Enable-AutoConfirm }

$MsysRoot     = 'C:\msys64'
$MsysBash     = Join-Path $MsysRoot 'usr\bin\bash.exe'
$MingwBin     = Join-Path $MsysRoot 'mingw64\bin'
$MingwGccExe  = Join-Path $MingwBin 'gcc.exe'
$MingwAsExe   = Join-Path $MingwBin 'as.exe'

function Test-Msvc {
  $cl = Get-ExePath 'cl.exe'
  if (-not $cl) { return $false }
  $info = (Invoke-NativeText -FilePath $cl | Select-Object -First 2) -join ' '
  Write-Ok "MSVC cl.exe 已安装"
  Write-Host "    路径：$cl"
  if (-not [string]::IsNullOrWhiteSpace($info)) { Write-Host "    版本：$info" }
  return $true
}

function Test-GnuAssembler {
  $as = Get-ExePath 'as.exe'
  if ($as) {
    Write-Ok "GNU 汇编器 as 已安装"
    Write-Host "    路径：$as"
    return $true
  }
  if (Test-Path -LiteralPath $MingwAsExe) {
    Add-PathPrefix $MingwBin
    Write-Ok "GNU 汇编器 as 已安装（已添加到 PATH）"
    Write-Host "    路径：$MingwAsExe"
    return $true
  }
  return $false
}

function Set-Msys2ChinaMirror {
  $d = Join-Path $MsysRoot 'etc\pacman.d'
  if (-not (Test-Path -LiteralPath $d)) { return $true }
  $marker = Join-Path $d '.china_mirrors_added'
  if (Test-Path -LiteralPath $marker) { return $true }
  Write-Host "  配置 MSYS2 国内镜像源（清华 TUNA）..." -ForegroundColor Cyan
  $map = @(
    @{ File = 'mirrorlist.mingw32';    Line = 'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/i686/' },
    @{ File = 'mirrorlist.mingw64';    Line = 'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/x86_64/' },
    @{ File = 'mirrorlist.ucrt64';     Line = 'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/ucrt64/' },
    @{ File = 'mirrorlist.clang64';    Line = 'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/clang64/' },
    @{ File = 'mirrorlist.clangarm64'; Line = 'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/clangarm64/' },
    @{ File = 'mirrorlist.msys';       Line = 'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/msys/$arch/' }
  )
  foreach ($item in $map) {
    $file = Join-Path $d $item.File
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $content = Get-Content -LiteralPath $file -ErrorAction SilentlyContinue
    if ($content -and ($content | Where-Object { $_ -eq $item.Line })) { continue }
    @($item.Line) + $content | Set-Content -LiteralPath $file -Encoding ASCII
  }
  New-Item -ItemType File -Force -Path $marker | Out-Null
  Write-Ok "MSYS2 国内镜像源已配置"
  return $true
}

function Install-GnuAssembler {
  if (Test-GnuAssembler) { return $true }
  Write-Warn "未找到 GNU 汇编器 as.exe，Rust dlltool 将无法创建导入库（编译会报 CreateProcess 错误）"
  if (-not (Test-Path -LiteralPath $MsysBash)) {
    Write-Fail "缺少 MSYS2，无法自动安装 binutils"
    return $false
  }
  if (-not (Confirm-Install "通过 MSYS2 pacman 安装 mingw-w64-x86_64-binutils")) { return $false }
  Set-Msys2ChinaMirror | Out-Null
  Invoke-NativeStream -Block { & $MsysBash -lc "pacman -S --noconfirm --needed mingw-w64-x86_64-binutils" }
  if (Test-Path -LiteralPath $MingwAsExe) {
    Add-PathPrefix $MingwBin
    Write-Ok "mingw-w64-x86_64-binutils 安装成功，as.exe 已添加到 PATH"
    return $true
  }
  Write-Fail "缺少 GNU 汇编器 as.exe，Android 交叉编译将失败。"
  Write-Fail "请安装 MSYS2（https://www.msys2.org/）并运行：pacman -S mingw-w64-x86_64-binutils"
  Write-Fail "然后将 $MingwBin 添加到 PATH"
  return $false
}

function Install-Msvc {
  Write-Host ""
  Write-Host "═══ 安装 MSVC (Visual Studio Build Tools) ═══" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  MSVC 需要通过 Visual Studio Installer 安装，步骤如下："
  Write-Host ""
  Write-Host "  方式一：自动下载安装器" -ForegroundColor Yellow
  Write-Host "    脚本将下载 vs_BuildTools.exe 并启动安装"
  Write-Host ""
  Write-Host "  方式二：手动安装" -ForegroundColor Yellow
  Write-Host "    1. 访问 https://visualstudio.microsoft.com/visual-cpp-build-tools/"
  Write-Host "    2. 下载 Build Tools for Visual Studio"
  Write-Host "    3. 安装时勾选「使用 C++ 的桌面开发」工作负载"
  Write-Host ""

  if (-not (Confirm-Install "自动下载并启动 MSVC Build Tools 安装器")) {
    Write-Warn "已跳过 MSVC 自动安装，请手动安装后重新运行此脚本"
    return $false
  }

  $installerPath = Join-Path $env:TEMP ("vs_buildtools_{0}.exe" -f ([guid]::NewGuid().ToString('N')))
  if (-not (Save-WebFile -Urls @('https://aka.ms/vs/17/release/vs_BuildTools.exe') -OutFile $installerPath -TimeoutSec 60)) {
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    Write-Fail "下载 Visual Studio Build Tools 安装器失败"
    Write-Fail "请手动访问 https://visualstudio.microsoft.com/visual-cpp-build-tools/ 下载安装"
    return $false
  }

  Write-Ok "正在启动安装器 ..."
  Write-Host "  请在安装器中勾选「使用 C++ 的桌面开发」工作负载" -ForegroundColor Yellow
  try {
    Start-Process -FilePath $installerPath -ArgumentList @('--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended', '--passive', '--wait') -Wait -NoNewWindow | Out-Null
  } catch {}
  Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue

  Write-Host ""
  Write-Host "  重新检查 MSVC ..." -ForegroundColor Cyan
  if (Test-Msvc) {
    Write-Ok "MSVC 安装成功！"
  } else {
    Write-Warn "MSVC 安装器已运行，但当前 shell 未检测到 cl.exe"
    Write-Warn "请重新打开终端后再次运行此脚本验证"
  }
  return $true
}

function Confirm-MingwGccReady {
  # 找到 gcc.exe 后的统一收尾：把 mingw64\bin 前置到 PATH，跑一次自检。3 处共用。
  param([string]$SuccessMessage)
  Add-PathPrefix $MingwBin
  Add-UserPathSegment -Segment $MingwBin | Out-Null
  Write-Ok $SuccessMessage
  Test-Gnu | Out-Null
  return $true
}

function Install-MsysGcc {
  if (-not (Confirm-Install "通过 MSYS2 pacman 安装 mingw-w64-x86_64-gcc")) { return $false }
  Set-Msys2ChinaMirror | Out-Null
  Invoke-NativeStream -Block { & $MsysBash -lc "pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils" }
  if (Test-Path -LiteralPath $MingwGccExe) {
    return (Confirm-MingwGccReady -SuccessMessage "mingw-w64-x86_64-gcc 安装成功")
  }
  Write-Warn "pacman 安装完成但未找到 gcc.exe，可能需要更新 MSYS2："
  Write-Warn "  pacman -Syu --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-gcc"
  return $false
}

function Install-Gnu {
  Write-Host ""
  Write-Host "═══ 安装 GNU gcc (MinGW-w64) ═══" -ForegroundColor Cyan
  Write-Host ""

  if (Test-Path -LiteralPath $MsysRoot) {
    Write-Ok "检测到 MSYS2 已安装在 $MsysRoot"
    if (Test-Path -LiteralPath $MingwGccExe) {
      return (Confirm-MingwGccReady -SuccessMessage "gcc 已存在于 $MingwBin，已添加到 PATH")
    }
    if (Install-MsysGcc) { return $true }
  } else {
    $msysInstaller = Join-Path $env:TEMP ("msys2_installer_{0}.exe" -f ([guid]::NewGuid().ToString('N')))
    if (-not (Confirm-Install "通过国内镜像（USTC/清华）安装 MSYS2，然后安装 mingw-w64-x86_64-gcc")) { return $false }

    # 优先通过国内镜像下载 MSYS2 安装程序（顺序降级），避免从 GitHub 下载
    # 注：Save-WebFile 多地址模式会同时从所有源下载（平分带宽），实际反而更慢，因此逐个尝试
    $mirrors = @(
      'https://mirrors.ustc.edu.cn/msys2/distrib/msys2-x86_64-latest.exe',
      'https://mirrors.tuna.tsinghua.edu.cn/msys2/distrib/msys2-x86_64-latest.exe'
    )
    $downloaded = $false
    foreach ($mirror in $mirrors) {
      if (Save-WebFile -Urls @($mirror) -OutFile $msysInstaller -MinSizeKB 10240) {
        $downloaded = $true
        break
      }
      Write-Warn "镜像 $mirror 下载失败，尝试下一个..."
    }

    if ($downloaded) {
      Write-Ok "正在静默安装 MSYS2 到 $MsysRoot ..."
      try {
        Start-Process -FilePath $msysInstaller -ArgumentList @('/S', "/D=$MsysRoot") -Wait -NoNewWindow | Out-Null
      } catch {}
      Remove-Item -LiteralPath $msysInstaller -Force -ErrorAction SilentlyContinue
    } else {
      Remove-Item -LiteralPath $msysInstaller -Force -ErrorAction SilentlyContinue
      # 国内镜像失败，回退到 winget
      if (-not (Get-ExePath 'winget.exe')) {
        Write-Fail "国内镜像下载失败且 winget 未找到，无法自动安装 MSYS2"
        Write-Fail "请手动访问 https://mirrors.ustc.edu.cn/msys2/distrib/ 下载安装"
        return $false
      }
      Write-Warn "国内镜像下载失败，回退到 winget 安装（注意：winget 仍会从 GitHub 下载安装包）..."
      Invoke-NativeStream -Block { & winget install MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements }
    }

    if (Test-Path -LiteralPath $MsysRoot) {
      Set-Msys2ChinaMirror | Out-Null
      Invoke-NativeStream -Block { & $MsysBash -lc "pacman-key --init && pacman-key --populate msys2 && pacman -Sy --noconfirm archlinux-msys2-keyring && pacman -Su --noconfirm && pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils" }
      if (Test-Path -LiteralPath $MingwGccExe) {
        return (Confirm-MingwGccReady -SuccessMessage "MSYS2 + mingw-w64-gcc 安装成功")
      }
      Write-Warn "MSYS2 已安装但 gcc 安装可能不完整，请手动执行："
      Write-Warn "  $MsysBash -lc 'pacman -S --noconfirm mingw-w64-x86_64-gcc'"
    } else {
      Write-Warn "MSYS2 安装后未在 $MsysRoot 找到安装目录"
    }
  }

  Write-Fail "GNU gcc 自动安装失败或被跳过"
  Write-Fail "请手动安装以下工具链："
  Write-Fail "  • MSYS2: https://www.msys2.org/ 安装后运行 pacman -S mingw-w64-x86_64-gcc"
  Write-Fail "  • MinGW-w64: https://www.mingw-w64.org/"
  return $false
}

function Test-Gnu {
  $gcc = Get-ExePath 'gcc.exe'
  if (-not $gcc) {
    if (Test-Path -LiteralPath $MingwGccExe) { Add-PathPrefix $MingwBin; $gcc = $MingwGccExe }
  }
  if (-not $gcc) { return $false }
  $info = (Invoke-NativeText -FilePath 'gcc' -Arguments @('--version') | Select-Object -First 1)
  Write-Ok "GNU GCC 编译器已安装"
  Write-Host "    路径：$gcc"
  if (-not [string]::IsNullOrWhiteSpace($info)) { Write-Host "    版本：$info" }

  if (-not (Get-ExePath 'g++.exe')) { Write-Warn "GCC 已找到但 G++ 未找到，部分 C++ 依赖可能编译失败" }

  if (-not (Test-GnuAssembler)) { Install-GnuAssembler | Out-Null }
  return $true
}

function Write-EnvSummary {
  param([bool]$HasMsvc, [bool]$HasGnu)
  Write-StatusLine -Label 'MSVC      ' -Ok:$HasMsvc
  Write-StatusLine -Label 'GNU GCC   ' -Ok:$HasGnu
}

Write-Host ""
Write-Banner -Title 'C/C++ 编译工具检查与安装（Windows）    ' -Color Cyan
Write-Host ""

Write-Host "[1/2] 检查 C/C++ 编译器" -ForegroundColor Cyan
$hasMsvc = Test-Msvc
$hasGnu = Test-Gnu

if ($hasMsvc -or $hasGnu) {
  Write-Host ""
  Write-Banner -Title 'C/C++ 编译工具已就绪' -Color Green

  Write-Host ""
  Write-Host "[2/2] 环境摘要" -ForegroundColor Cyan
  Write-EnvSummary -HasMsvc $hasMsvc -HasGnu $hasGnu
  Write-Host ""
  Write-Host "  检查完成，C/C++ 编译工具可用。" -ForegroundColor Green
  exit 0
}

Write-Host ""
Write-Host "  ✗ 未检测到 C/C++ 编译器" -ForegroundColor Red
Write-Host ""
Write-Host "[2/2] 选择安装方式" -ForegroundColor Cyan

$selected = Select-MenuOption -Prompt '请选择要安装的编译工具链：' -Options @(
  'MSVC (Visual Studio Build Tools)',
  'GNU (MinGW-w64 / MSYS2)'
)

switch ($selected) {
  1 {
    Enable-AutoConfirm
    Install-Msvc | Out-Null
  }
  2 {
    Enable-AutoConfirm
    Install-Gnu | Out-Null
  }
  0 {
    Exit-NoOp "已退出，未安装任何工具链。" -Code 1
  }
}

Write-Host ""
Write-Host "环境摘要" -ForegroundColor Cyan
$msvcNow = $null -ne (Get-ExePath 'cl.exe')
$gnuNow = $null -ne (Get-ExePath 'gcc.exe')
Write-EnvSummary -HasMsvc $msvcNow -HasGnu $gnuNow
Write-Host ""
if (-not $Failed) {
  Write-Host "  C/C++ 编译工具安装完成！" -ForegroundColor Green
} else {
  Write-Host "  安装已完成，但部分步骤可能需要手动处理。" -ForegroundColor Yellow
}
