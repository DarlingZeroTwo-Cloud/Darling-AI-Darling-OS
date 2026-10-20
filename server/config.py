# -*- coding: utf-8 -*-
"""darling-ai-server 默认配置。GUI 里改端口等。"""

# 监听
HOST_V4 = "0.0.0.0"
HOST_V6 = "::"
# 默认 1611（>1024 不需要管理员权限）；想改成 611 在 GUI 里改，
# 但 <1024 端口在 Linux/macOS 需要 root、Windows 需要管理员启动。
PORT = 1611

# CORS（客户端是桌面端，宽松允许）
CORS_ORIGIN = "*"

# 免费额度（每 5 小时窗口）
FREE_LIMITS = {
    "text_tokens": 50_000_000,   # 5000 万 token
    "images": 10,
    "videos": 2,
}

# Token TTL
TOKEN_TTL = 30 * 86400  # 30 天

# IPv6 监听开关（部分 Windows 环境 getaddrinfo 失败，默认关）
ENABLE_V6 = False
