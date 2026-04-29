# PowerShell 单函数调试指南

## 基本格式

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "& { . ./script/_common.ps1; <函数名> <参数> }"
```

- `. ./script/_common.ps1` — dot-source 加载，函数进入当前作用域
- `-ExecutionPolicy Bypass` — 绕过执行策略限制
- `& { ... }` — 脚本块包裹，保持变量作用域

## 交互式调试（推荐）

在 PowerShell 窗口中逐步操作：

```powershell
# 1. 加载脚本
. ./script/_common.ps1

# 2. 直接调用函数
Save-WebFile -Urls @('url1','url2') -OutFile "$env:TEMP\test.zip" -RaceSec 10

# 3. 调用单链接下载
Save-WebFileSingle -Url 'url1' -OutFile "$env:TEMP\test.zip"
```

## 有依赖的函数

```powershell
# 先加载依赖，再加载目标脚本
. ./script/_common.ps1
. ./script/install_base_tools_bywin.ps1
Install-WingetTool
```

## 捕获错误

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "& {
  . ./script/_common.ps1
  try {
    Save-WebFile -Urls @('url1') -OutFile 'C:\temp\test.zip'
  } catch {
    Write-Host \"错误: $_\"
    Write-Host $_.ScriptStackTrace
  }
}"
```

## 常用调试技巧

### 查看函数是否存在

```powershell
. ./script/_common.ps1
Get-Command Save-WebFile -ErrorAction SilentlyContinue
```

### 查看函数定义

```powershell
. ./script/_common.ps1
Get-Content Function:\Save-WebFile
```

### 设置断点

```powershell
. ./script/_common.ps1
Set-PSBreakpoint -Command Save-WebFile
Save-WebFile -Urls @('url1') -OutFile "$env:TEMP\test.zip"
```

### 逐行执行（手动断点）

在函数内部插入 `Read-Host` 暂停：

```powershell
# 修改函数代码，在关键位置加：
Read-Host "暂停调试，按 Enter 继续"
```

### 查看变量值

```powershell
# 在函数执行后查看变量
$variable  # 直接输出
Get-Content Variable:\variable  # 通过驱动器查看
```
