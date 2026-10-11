# darling-ai

本地 AI 工作台：Flutter GUI（Material 3）+ Python 核心（本地 HTTP 服务）。
多供应商对话、插件系统、命令执行工作区、本地模型运行时，支持 Windows 与 Linux。

## 特性

- **双 UI 模式**：精简（opencode 风格居中输入框）/ 经典（Zed 风格侧边栏，抽屉式可收起）
- **多模型共用一个对话**：所有模型共享同一会话，可随时切换模型，记忆按对话保存
- **多供应商**：内置 OpenAI / Anthropic / 智谱等预设，支持自定义供应商（API 地址 + Key）
- **插件系统**：`plugins/*.json` 声明式插件，AI 可调用，也支持 AI 自写插件（写好自动加载）
  - 内置：联网搜索（Bing）、插件工坊（AI 写插件）
- **本地模型**：内置轻量本地 AI 框架，模型市场可下载 GGUF 模型接入对话（可选 GPU 加速）
- **安全模式**：完全访问 / 按需访问（每次操作前确认）
- **外观**：跟随系统深浅色，可自定义背景图片与不透明度

## 目录结构

```
app_src/                 Flutter 源码（lib/ + pubspec.yaml）
app/                     Flutter 发布工程（build 用）
backend/                 Python 核心（bridge_server.py 等，PyInstaller 打包）
  plugins/               内置插件 JSON
build/                   构建脚本（Windows Inno / Linux tar+deb）
assets/icon/             图标
```

## 运行

- Windows：安装 `darling-ai-2.0.0-setup.exe`，或解压免安装版后运行 `darling_ai.exe`
- Linux：安装 `darling-ai_2.0.0_amd64.deb`，或解压 `darling-ai-2.0.0-linux-x64.tar.gz` 后运行 `./run.sh`

GUI 启动后会自动拉起本地后端（`127.0.0.1:19730`）。

## 从源码构建

- Windows：`build/build_windows_v2.py`（需 Flutter SDK 与 Inno Setup）
- Linux：WSL/Ubuntu 下 `flutter build linux --release` + PyInstaller 打 backend，参考 `build/pack_linux_v2.sh`
