# Darling AI for Darling OS

为 **Darling OS**（Arch Linux + Hyprland）专门定制的 Darling AI 专属发行版。

## 特点

- **Arch 专属格式**：`.pkg.tar.zst`（pacman 直接安装），无通用发行版残留
- **悬浮球常驻**：小圆点 02 常驻所有虚拟桌面，点击弹出悬浮对话窗快速 AI 对话
- **全局快捷键**：`Win + Ctrl + D` 唤起/收起完整窗口（唤起时悬浮球自动隐藏，关闭后恢复）
- **屏幕读取**：悬浮窗内一键「读屏翻译 / 读屏提问」（grim 截图 + tesseract OCR）
- **后台常驻**：systemd 用户服务开机自启、崩溃自动重启、常驻后台
- **共享账号**：与通用版/官网同一云端账号，登录后直接使用官方模型 02

## 安装（Darling OS / Arch）

```bash
# 从 Release 下载 darling-ai-darling-os-4.1.9-1-x86_64.pkg.tar.zst
sudo pacman -U darling-ai-darling-os-4.1.9-1-x86_64.pkg.tar.zst
```

依赖：`gtk3 python python-requests tesseract tesseract-data-chi_sim grim hyprland`

## Hyprland 集成

把仓库 `archlinux/hyprland-darling-ai.conf` 复制到 `~/.config/hypr/`，并在 `hyprland.conf` 加一行：

```
source = ~/.config/hypr/hyprland-darling-ai.conf
```

包含：`Win+Ctrl+D` 全局快捷键、开机自启常驻、悬浮球常驻所有虚拟桌面（special workspace）。

## 手动运行 / 调试

```bash
systemctl --user start darling-ai.service   # 常驻启动
darling-ai-toggle                           # 快捷键对应的唤起脚本（socket 通知）
darling-ai                                  # 前台运行
```

## 与通用版关系

- 与通用版 Darling AI 共享云端账号 / 官方模型 02 / 官网 API
- 移除 Windows 安装器、deb、tar.gz 等通用发行版，仅保留 Arch 专属包
- 代码基础：v4.1.9（通用版），叠加 Darling OS 专属多窗口/常驻功能

## 构建

`flutter build linux --release` 后由 GitHub Actions 在 Arch 容器内 `makepkg` 打包 `.pkg.tar.zst`。构建产物不包含 DeepSeek Harness / dsh 本地运行时（云端官方模型直连）。
