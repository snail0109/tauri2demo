# Windows Sandbox（沙盒）学习与使用教程

## 1. 什么是 Windows Sandbox

Windows Sandbox（Windows 沙盒）是 Windows 提供的“临时隔离系统环境”。每次启动都是一个全新的、干净的 Windows 实例，用完关闭即销毁（默认不保留任何变更）。它适合：

- 运行不确定来源的软件/脚本做安全验证
- 快速复现问题、验证安装包/依赖
- 在不污染本机环境的前提下做临时实验

## 2. 系统要求与前置条件

### 2.1 Windows 版本要求

通常需要 Windows 10/11 的 Pro / Enterprise / Education 等版本（Home 版本一般不提供沙盒功能）。

### 2.2 必须开启虚拟化

- BIOS/UEFI 中开启 CPU 虚拟化（Intel VT-x / AMD-V）
- Windows 中相关虚拟化能力可用（沙盒基于虚拟化/容器能力）

### 2.3 可选功能名称（脚本检测依据）

沙盒在系统层面对应的可选功能为：

- `Containers-DisposableClientVM`

本仓库脚本里的 `Test-MicrosoftSandbox` 就是围绕这个功能做检测。

## 3. 如何启用 Windows Sandbox

### 3.1 图形界面启用（推荐）

1. 打开“启用或关闭 Windows 功能”
2. 勾选“Windows 沙盒（Windows Sandbox）”
3. 确认后按提示重启

### 3.2 PowerShell / DISM 启用

PowerShell（管理员）：

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

DISM（管理员）：

```powershell
dism /online /Enable-Feature /FeatureName:Containers-DisposableClientVM /All
```

启用后通常需要重启。

## 4. 如何确认沙盒是否已启用（本仓库脚本）

### 4.1 通过脚本的 all 模式触发检测

脚本在执行安装 `-AddTools all` 时会做一次“附加检测”，其中包含 `Test-MicrosoftSandbox`（只检测，不安装、不卸载）：

```powershell
.\script\windows\install_base_tools_bywin.ps1 -AddTools all
```

### 4.2 手动调用检测函数

如果你想单独检测沙盒状态，可以在 PowerShell 里加载脚本后调用函数：

```powershell
. "c:\MyWork\TmpCode\tauri2demo\script\windows\_common.ps1"
. "c:\MyWork\TmpCode\tauri2demo\script\windows\install_base_tools_bywin.ps1"
Test-MicrosoftSandbox
```

返回值：

- `$true`：沙盒功能启用，且能找到沙盒相关可执行文件并输出版本信息
- `$false`：未启用或不可用

## 5. 基础使用：启动与退出

### 5.1 启动

- 开始菜单搜索：`Windows Sandbox` / `Windows 沙盒`
- 或运行（Win + R）：`WindowsSandbox.exe`（若存在）

首次启动可能会初始化较久。

### 5.2 使用过程中常见操作

- 复制/粘贴：可在宿主机与沙盒之间复制文本、文件（行为依系统策略而定）
- 下载软件：在沙盒里用浏览器下载并安装测试（默认开启网络）
- 运行未知程序：在沙盒里验证其行为，确认无异常再考虑在本机安装

### 5.3 退出

关闭沙盒窗口即可。关闭后沙盒环境会被销毁，默认不保留任何数据与安装的软件。

## 6. 进阶：使用 .wsb 配置文件定制沙盒

Windows Sandbox 支持使用 `.wsb` 文件进行启动配置。你可以把它理解成“沙盒的启动参数文件”。

### 6.1 示例：映射宿主机目录（持久化输出）

将宿主机 `C:\Temp\SandboxShare` 映射到沙盒内 `C:\Users\WDAGUtilityAccount\Desktop\Share`：

```xml
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\Temp\SandboxShare</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\Share</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
</Configuration>
```

保存为 `demo.wsb`，双击即可启动。

### 6.2 示例：禁用 vGPU和网络（更安全）

```xml
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>Disable</Networking>
  <MemoryInMB>2048</MemoryInMB>
</Configuration>
```

### 6.3 示例：启动后自动执行命令（自动化）

```xml
<Configuration>
  <LogonCommand>
    <Command>powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ComputerInfo | Out-File $env:USERPROFILE\\Desktop\\info.txt"</Command>
  </LogonCommand>
</Configuration>
```

### 6.4 示例：在沙盒中启动时安装Visual Studio Code

```xml
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\SandboxScripts</HostFolder>
      <SandboxFolder>C:\temp\sandbox</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>C:\CodingProjects</HostFolder>
      <SandboxFolder>C:\temp\Projects</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>C:\temp\sandbox\VSCodeInstall.cmd</Command>
  </LogonCommand>
</Configuration>
```

安装程序 VSCodeInstall.cmd

```PowerShell
REM Download Visual Studio Code
curl -L "https://update.code.visualstudio.com/latest/win32-x64-user/stable" --output C:\temp\vscode.exe

REM Install and run Visual Studio Code
C:\temp\vscode.exe /verysilent /suppressmsgboxes
```

常见用途：

- 启动即安装/运行某个工具
- 自动收集信息并写到映射目录

## 7. 使用建议（安全与效率）

- 把“需要带回宿主机的输出”写入映射目录，避免关闭后丢失
- 测试高风险软件时建议禁用网络，或者仅在受控网络环境下使用
- 不要在沙盒里登录重要账号、输入敏感密钥（即使沙盒隔离，也要遵循最小暴露原则）

## 8. 常见问题排查

### 8.1 脚本检测不到沙盒（返回 false）

优先检查：

1. 可选功能是否启用（`Containers-DisposableClientVM`）
2. 是否重启过
3. BIOS 虚拟化是否开启
4. Windows 版本是否支持沙盒

查询功能状态：

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
```

或：

```powershell
dism /online /Get-FeatureInfo /FeatureName:Containers-DisposableClientVM
```

### 8.2 启动沙盒报错（初始化失败/无法启动）

通常与虚拟化能力、Hyper-V 组件、系统版本/策略有关。建议：

- 确认虚拟化已开启
- 确认 Windows 功能已启用并重启
- 检查系统策略是否禁用相关功能

### 9 参考资料

[Windows 沙盒命令行 | Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli?source=recommendations)

[使用和配置Windows 沙盒 | Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file?source=recommendations)
