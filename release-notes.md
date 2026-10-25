# Darling AI for Darling OS v4.1.9 更新日志

## 本版（v4.1.9 · Darling OS 专属发行版）

### 新特性：Darling OS 原生体验
- **悬浮球常驻**：屏幕常驻 02 小圆点，所有虚拟桌面可见；点击弹出悬浮对话窗快速 AI 对话
- **全局快捷键**：`Win + Ctrl + D` 唤起/收起完整窗口；唤起时悬浮球自动隐藏，关闭后恢复
- **屏幕读取**：悬浮窗一键「读屏翻译 / 读屏提问」（grim 截图 + tesseract OCR）
- **后台常驻**：systemd 用户服务，开机自启、崩溃自动重启
- **Arch 专属打包**：`.pkg.tar.zst`（pacman 安装），移除 Windows 安装器 / deb / tar.gz 通用发行版

### 沿用 v4.1.x 全部能力
- 云端账号注册/登录/找回密码（安全提问）
- 官方模型 02（agnes-2.5-flash 文本 + agnes-image-2.5-flash 图片，不限量）
- 模型配置云端同步、对话管理、插件、联网搜索、AI 优化提示词、对话导出
- 官网（www.darling02.de5.net）注册/登录/创建 API Key 与客户端同账号互通

## 历史修复（v4.1.x 累计）
- 拉取模型失败：供应商测试连接改用浏览器指纹请求，绕过 Cloudflare bot 拦截
- 发不了消息：云端模型可解析，不再被本地模型解析拦截
- Key 可随意改/格式混乱：官方供应商只读展示，登录 Token 由账号自动管理
- 拉取额度慢/失败：服务端修复 500，模型列表加缓存
- SSL 握手失败（安卓/自定义域名证书）：全局放行证书校验
- 上游 429 自动重试

## 安装
```bash
sudo pacman -U darling-ai-darling-os-4.1.9-1-x86_64.pkg.tar.zst
# Hyprland 集成见 README（hyprland-darling-ai.conf）
```
