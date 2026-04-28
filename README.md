# 西语桌面助手

## 开发环境要求

### Rust

Tauri 以 Rust 构建，必须安装 Rust 工具链。安装后请重启终端使更改生效。

#### Linux / macOS

通过 `rustup` 安装：

```bash
curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh
```

#### Windows

有两种安装方式：

1. 前往 [https://www.rust-lang.org/zh-CN/tools/install](https://www.rust-lang.org/zh-CN/tools/install) 下载 `rustup` 安装程序
2. 或使用 `winget` 安装：

   ```powershell
   winget install --id Rustlang.Rustup
   ```

> **注意**: 安装时请选择 **MSVC** 工具链（如 `x86_64-pc-windows-msvc`），而非 MinGW。
> 如已安装 Rust，可通过 `rustup default stable-msvc` 确认工具链正确。

### 桌面端开发
- Node.js 18+
- pnpm

### 移动端开发

#### Android
- Android Studio
- Android SDK (API 21+)
- Java Development Kit (JDK) 11+

安装 Rust 后还需添加 Android 编译目标：

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
```

#### iOS

> 仅 macOS 支持，需安装完整 Xcode（非仅命令行工具）。

安装 Rust 后还需添加 iOS 编译目标：

```bash
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
```

## 安装依赖

```bash
pnpm install
```

## 讯飞语音评测配置

复制示例文件为本地配置文件：

```bash
cp backend/src-tauri/.env.example backend/src-tauri/.env
```

然后编辑 `backend/src-tauri/.env`，填入你的讯飞凭证：

```bash
XF_APP_ID=your_app_id
XF_API_KEY=your_api_key
XF_API_SECRET=your_api_secret
```

## 百度 OCR 配置
图片识别功能依赖百度 OCR 接口。

请在 `backend/src-tauri/src/lib.rs` 中将以下占位符替换为你自己的百度 OCR 凭证：

```rust
const BAIDU_API_KEY: &str = "YOUR_BAIDU_API_KEY";
const BAIDU_SECRET_KEY: &str = "YOUR_BAIDU_SECRET_KEY";

## 开发运行

### 桌面端
```bash
pnpm tauri dev
```


### Android:
```
pnpm tauri android init
pnpm tauri android dev
# or if you want to dev on a real device
pnpm tauri android dev --host
```

### IOS
```bash
pnpm tauri ios init

pnpm tauri ios dev
```

## 构建应用

### 桌面端
```bash
pnpm tauri build
```

### 移动端
```bash
# Android APK
pnpm tauri android build

# iOS
pnpm tauri ios build
```

## 项目结构

```
tauri2demo/
├── src/                    # Vue 前端代码
│   ├── components/        # Vue 组件目录
│   │   ├── HomePage.vue   # 首页组件
│   │   ├── DetailPage.vue # 详情页组件
│   │   ├── AboutPage.vue  # 说明页组件
│   │   ├── BottomNav.vue  # 底部导航组件
│   │   └── index.ts       # 组件导出索引
│   ├── types/             # TypeScript 类型定义
│   │   └── index.ts       # 类型定义文件
│   ├── App.vue           # 主应用组件
│   ├── main.ts           # 应用入口
│   └── assets/           # 静态资源
├── src-tauri/            # Rust 后端代码
│   ├── src/              # Rust 源代码
│   ├── tauri.conf.json   # Tauri 配置
│   └── Cargo.toml        # Rust 依赖配置
└── package.json          # Node.js 依赖配置
```

## 技术栈

- **前端**: Vue 3 + TypeScript + Vite
- **后端**: Rust + Tauri
- **移动端**: Tauri Mobile (基于 WebView)
- **UI**: 原生 CSS + 响应式设计
- **架构**: 组件化设计 + 类型安全


## 常见问题

### 端口 31420 被占用

`pnpm dev` 启动时如报错 `Port 31420 is already in use`，通常是上次启动的 Vite 进程未正常退出。找到并关闭占用进程即可：

**macOS / Linux：**

```bash
lsof -ti :31420 | xargs kill
```

**Windows：**

```powershell
# 查找占用端口的 PID
netstat -ano | findstr :31420
# 关闭对应进程（替换 <PID>）
taskkill /PID <PID> /F
```

随后重新 `pnpm dev` 启动。

### Android 模拟器无法访问开发服务器

Android 模拟器中运行 Tauri App 时，默认无法直接访问宿主机的 `localhost:31420`。使用 `adb reverse` 将端口映射到模拟器：

```bash
adb reverse tcp:31420 tcp:31420
```

之后重启模拟器中的 App 即可正常访问开发服务器。

## TODO
- [ ] 移动端布局样式兼容问题
- [ ] 移动端选中文本失效
- [ ] 使用 openai 的 api
- [ ] 支持 OCR / AI 密钥本地配置方式
