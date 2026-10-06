#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AI 控制台助手 (AI Console Assistant) v0.1.0
============================================
一个无 GUI 的命令行 AI 助手：

  1. 连接已有模型 —— 选择模型后进入对话，支持流式输出、工作区命令执行
  2. 添加供应商   —— 内置 OpenAI / DeepSeek / 通义千问 / 智谱GLM / Kimi / 硅基流动 / Ollama，
                     也支持自定义供应商（填 API 地址 + API Key，
                     可选择填的地址是否为"完整接口地址"）
  3. 设置         —— AI 访问模式（完全访问 / 按需访问）、温度、最大 tokens、
                     系统提示词、工作区、供应商与模型管理、对话历史清理

特性：
  - 配置保存在程序同目录 config.json（可用环境变量 AI_CONSOLE_CONFIG 覆盖路径）
  - 工作区：AI 可以在你选定的目录里执行命令
      * 按需访问：每次执行前询问你是否允许
      * 完全访问：自动执行（请谨慎使用，AI 可执行任意命令）
  - 对话历史按模型自动保存

运行：
  python ai_console.py
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
import uuid


# ---- 控制台初始化：切到 UTF-8 代码页 + 按 UTF-8 输出（解决中文乱码）----
# 用 ctypes 直接调用 Win32 API，避免 os.system("chcp") 派生 cmd.exe 吃掉标准输入
if os.name == "nt":
    try:
        import ctypes
        ctypes.windll.kernel32.SetConsoleOutputCP(65001)  # CP_UTF8
        ctypes.windll.kernel32.SetConsoleCP(65001)
    except Exception:
        pass
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    sys.stdin.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    import requests
except ImportError:
    print("缺少依赖库 requests，请先执行: pip install requests")
    sys.exit(1)


# ---- 启用控制台 VT100 颜色转义（Win10+ conhost / PowerShell 原生支持）----
def _enable_vt():
    if os.name != "nt":
        return True
    try:
        import ctypes
        k = ctypes.windll.kernel32
        h = k.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        mode = ctypes.c_uint32()
        k.GetConsoleMode(h, ctypes.byref(mode))
        k.SetConsoleMode(h, mode.value | 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        return True
    except Exception:
        return False


VT_OK = _enable_vt()


def _system_is_light_theme():
    """读取注册表判断 Windows 浅色/深色主题。"""
    if os.name != "nt":
        return False
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                             r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        val, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
        return val == 1
    except Exception:
        return False


LIGHT_THEME = _system_is_light_theme()

# ==================== 颜色 ====================
class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = ""
    RED = GREEN = YELLOW = BLUE = MAGENTA = CYAN = WHITE = ""


def _init_colors():
    """按系统主题 + VT 支持情况配置调色板。"""
    if not VT_OK:
        # 老控制台不支持 ANSI：全部置空，降级为纯文本，避免出现 [32m 乱码
        return
    if LIGHT_THEME:
        C.DIM = "\033[90m"
        C.RED = "\033[31m"     # 深红，浅底上可读
        C.GREEN = "\033[32m"
        C.YELLOW = "\033[33m"
        C.BLUE = "\033[34m"
        C.MAGENTA = "\033[35m"
        C.CYAN = "\033[36m"
        C.WHITE = "\033[30m"   # 浅底上正文用黑
    else:
        C.DIM = "\033[90m"
        C.RED = "\033[91m"     # 亮红，深底上醒目
        C.GREEN = "\033[92m"
        C.YELLOW = "\033[93m"
        C.BLUE = "\033[94m"
        C.MAGENTA = "\033[95m"
        C.CYAN = "\033[96m"
        C.WHITE = "\033[97m"   # 深底上正文用亮白


_init_colors()


def col(text, code):
    return f"{code}{text}{C.RESET}"


def clear_screen():
    """清屏（菜单切换时使用，让每个界面干净独立）。
    使用 ANSI 转义序列而非 os.system("cls")，避免在管道/重定向环境下
    误吃后续标准输入。"""
    if VT_OK:
        print("\033[2J\033[H", end="", flush=True)
    else:
        os.system("cls" if os.name == "nt" else "clear")


# ==================== 常量 ====================
APP_NAME = "AI 控制台助手"
APP_VERSION = "0.2.0"
MAX_AGENT_STEPS = 8          # 一次用户提问后，AI 最多连续执行的命令轮数
MAX_OUTPUT_CHARS = 20000     # 命令输出回传给 AI 的最大字符数
HISTORY_LIMIT = 60           # 每个模型保存的历史消息条数上限
REQUEST_TIMEOUT = (10, 300)  # (连接超时, 读取超时)

# 内置供应商（自带 API 地址，只需填 Key）
DEFAULT_PROVIDERS = [
    {"id": "openai",      "name": "OpenAI",           "base_url": "https://api.openai.com/v1"},
    {"id": "deepseek",    "name": "DeepSeek",         "base_url": "https://api.deepseek.com/v1"},
    {"id": "qwen",        "name": "通义千问(阿里云)",  "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1"},
    {"id": "zhipu",       "name": "智谱 GLM",         "base_url": "https://open.bigmodel.cn/api/paas/v4"},
    {"id": "kimi",        "name": "Moonshot Kimi",    "base_url": "https://api.moonshot.cn/v1"},
    {"id": "siliconflow", "name": "硅基流动",         "base_url": "https://api.siliconflow.cn/v1"},
    {"id": "ollama",      "name": "Ollama(本地)",     "base_url": "http://localhost:11434/v1"},
]

DEFAULT_SYSTEM_PROMPT = (
    "你是运行在用户电脑上的命令行 AI 助手，通过终端与用户交流。\n"
    "你拥有在用户指定的\"工作区\"目录里执行命令的能力。当你需要查看文件、"
    "运行程序、处理数据等实际操作时，请输出如下格式的命令块：\n"
    "[[CMD]]在这里写要执行的命令[[/CMD]]\n"
    "命令会在用户电脑上真实执行，请务必小心谨慎，不要执行任何可能造成破坏"
    "或危险的命令。执行结果会自动返回给你，你可以根据结果继续工作。"
    "如果不需要执行命令，直接正常回答用户即可。"
)

DEFAULT_SETTINGS = {
    "access_mode": "on_demand",  # full=完全访问(自动执行) / on_demand=按需访问(每次询问)
    "temperature": 0.7,
    "max_tokens": 4096,
    "system_prompt": DEFAULT_SYSTEM_PROMPT,
    "workspace": None,           # 首次运行时自动设为程序所在目录
}


def app_dir():
    """程序所在目录（打包成 exe 后为 exe 所在目录）。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def config_path():
    """配置文件路径。打包成 exe 后写到 %APPDATA%\\darling-ai\\，避免 Program Files 无写权限。"""
    if os.environ.get("AI_CONSOLE_CONFIG"):
        return os.environ["AI_CONSOLE_CONFIG"]
    if getattr(sys, "frozen", False):
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        d = os.path.join(base, "darling-ai")
        os.makedirs(d, exist_ok=True)
        return os.path.join(d, "config.json")
    return os.path.join(app_dir(), "config.json")


# ==================== 配置 ====================
class Config:
    def __init__(self):
        self.data = {
            "providers": [],
            "models": [],
            "settings": dict(DEFAULT_SETTINGS),
            "histories": {},
        }
        self.load()

    def load(self):
        path = config_path()
        if not os.path.exists(path):
            self.data["settings"]["workspace"] = app_dir()
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            for key in ("providers", "models", "histories"):
                if isinstance(loaded.get(key), list if key != "histories" else dict):
                    self.data[key] = loaded[key]
            settings = dict(DEFAULT_SETTINGS)
            settings.update(loaded.get("settings", {}))
            if not settings.get("workspace"):
                settings["workspace"] = app_dir()
            self.data["settings"] = settings
        except Exception as e:
            print(col(f"[警告] 配置文件读取失败({e})，已使用默认配置。", C.YELLOW))
            self.data["settings"]["workspace"] = app_dir()

    def save(self):
        try:
            with open(config_path(), "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(col(f"[错误] 保存配置失败: {e}", C.RED))

    # ---- 便捷方法 ----
    def provider(self, pid):
        for p in self.data["providers"]:
            if p["id"] == pid:
                return p
        return None

    def model(self, mid):
        for m in self.data["models"]:
            if m["id"] == mid:
                return m
        return None

    def history(self, model_id):
        return self.data["histories"].get(model_id, [])


# ==================== API 调用 ====================
def chat_url(provider):
    base = (provider.get("base_url") or "").strip().rstrip("/")
    if provider.get("full_endpoint"):
        return base  # 完整接口地址，直接使用
    return base + "/chat/completions"


def auth_headers(provider):
    headers = {"Content-Type": "application/json"}
    key = (provider.get("api_key") or "").strip()
    if key:
        headers["Authorization"] = "Bearer " + key
    return headers


def fetch_models(provider, timeout=30):
    """拉取供应商的模型列表，返回模型 id 列表。失败抛出异常。"""
    base = (provider.get("base_url") or "").strip().rstrip("/")
    if provider.get("full_endpoint"):
        # 完整地址模式下，去掉 /chat/completions 后缀以推导 models 接口
        for suffix in ("/chat/completions", "/v1/chat/completions"):
            if base.endswith(suffix):
                base = base[: -len(suffix)]
                break
    else:
        # 普通模式下用户也可能误填了完整地址，自动修正
        if base.endswith("/chat/completions"):
            base = base[: -len("/chat/completions")]
    url = base + "/models"
    resp = requests.get(url, headers=auth_headers(provider), timeout=timeout)
    resp.raise_for_status()
    data = resp.json()
    ids = []
    for m in data.get("data", []):
        mid = m.get("id")
        if mid:
            ids.append(mid)
    return ids


def chat_request(provider, model, messages, settings, stream=True):
    """发起对话请求。stream=True 时生成 content 增量 token；否则生成单个完整文本。"""
    url = chat_url(provider)
    payload = {
        "model": model,
        "messages": messages,
        "temperature": float(settings.get("temperature", 0.7)),
        "max_tokens": int(settings.get("max_tokens", 4096)),
        "stream": stream,
    }
    resp = requests.post(
        url, headers=auth_headers(provider), json=payload,
        timeout=REQUEST_TIMEOUT, stream=stream,
    )
    if resp.status_code != 200:
        detail = ""
        try:
            err = resp.json().get("error", "")
            if isinstance(err, dict):
                detail = err.get("message", "")
            else:
                detail = str(err)
        except Exception:
            pass
        raise RuntimeError(f"HTTP {resp.status_code} {detail}".strip())
    if not stream:
        data = resp.json()
        try:
            content = data["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError):
            content = json.dumps(data, ensure_ascii=False)[:500]
        yield content
        return
    # 手动按 UTF-8 解码 SSE 行：requests 的 decode_unicode 对未声明 charset 的
    # text/event-stream 会默认按 ISO-8859-1 解码，导致中文乱码
    for raw in resp.iter_lines():
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace")
        if line.startswith("data:"):
            data = line[5:].strip()
        else:
            continue
        if data == "[DONE]":
            break
        try:
            obj = json.loads(data)
        except Exception:
            continue
        if obj.get("error"):
            raise RuntimeError(str(obj.get("error")))
        choices = obj.get("choices") or []
        if not choices:
            continue
        delta = choices[0].get("delta") or {}
        tok = delta.get("content")
        if tok:
            yield tok


# ==================== 流式打印 + 命令块提取 ====================
CMD_OPEN = "[[CMD]]"
CMD_CLOSE = "[[/CMD]]"
_MARKERS = (CMD_OPEN, CMD_CLOSE)


def _is_marker_prefix(s):
    for m in _MARKERS:
        if m.startswith(s):
            return True
    return False


def stream_reply(tokens):
    """流式打印 AI 回复（隐藏 [[CMD]] 块内容），返回 (可见文本, 命令块列表)。

    返回的可见文本用于存入对话历史；命令块稍后单独展示并执行。
    """
    pending = ""
    in_block = False
    block_buf = ""
    blocks = []
    full = []

    def flush_visible(s):
        if s:
            print(s, end="", flush=True)
            full.append(s)

    for tok in tokens:
        pending += tok
        while pending:
            if not in_block:
                idx = pending.find(CMD_OPEN)
                if idx >= 0:
                    flush_visible(pending[:idx])
                    pending = pending[idx + len(CMD_OPEN):]
                    in_block = True
                    block_buf = ""
                    continue
                # 未出现完整开标记：若尾部是标记前缀，则保留等待更多 token
                held = 0
                for k in range(1, len(CMD_OPEN)):
                    if _is_marker_prefix(pending[-k:]):
                        held = k
                if held:
                    if len(pending) > held:
                        flush_visible(pending[:-held])
                    pending = pending[-held:]
                    break  # 等下一个 token，避免 pending 不变导致死循环
                flush_visible(pending)
                pending = ""
            else:
                idx = pending.find(CMD_CLOSE)
                if idx >= 0:
                    block_buf += pending[:idx]
                    pending = pending[idx + len(CMD_CLOSE):]
                    in_block = False
                    if block_buf.strip():
                        blocks.append(block_buf.strip())
                    continue
                # 未出现完整闭标记：若尾部是标记前缀，则保留等待更多 token
                held = 0
                for k in range(1, len(CMD_CLOSE)):
                    if _is_marker_prefix(pending[-k:]):
                        held = k
                if held:
                    if len(pending) > held:
                        block_buf += pending[:-held]
                    pending = pending[-held:]
                    break  # 等下一个 token，避免 pending 不变导致死循环
                block_buf += pending
                pending = ""
    # 流结束后处理残留
    if in_block:
        blocks.append((block_buf + pending).strip())  # 未闭合的命令块
    elif pending:
        flush_visible(pending)  # 残留文本（如未闭合的 "[[")
    print()
    return "".join(full), blocks


# ==================== 命令执行 ====================
def run_command(cmd, workspace, timeout=120):
    """在工作区目录执行命令，返回 (是否成功, 输出文本)。"""
    try:
        proc = subprocess.run(
            cmd, shell=True, cwd=workspace,
            capture_output=True, timeout=timeout,
        )
        out = (proc.stdout or b"") + (proc.stderr or b"")
        text = out.decode("utf-8", errors="replace")
        if "\ufffd" in text:  # UTF-8 解码出乱码，改用 GBK 重解（中文 Windows）
            text = out.decode("gbk", errors="replace")
        text = text.strip()
        if len(text) > MAX_OUTPUT_CHARS:
            text = text[:MAX_OUTPUT_CHARS] + f"\n...(输出过长，已截断到 {MAX_OUTPUT_CHARS} 字符)"
        return proc.returncode == 0, text
    except subprocess.TimeoutExpired:
        return False, f"(命令执行超时，超过 {timeout} 秒已终止)"
    except Exception as e:
        return False, f"(命令执行失败: {e})"


def ask(prompt):
    """读取用户输入：去空白、去 BOM（兼容重定向自带 BOM 的输入文件）。"""
    try:
        return input(prompt).strip().lstrip("\ufeff")
    except (EOFError, KeyboardInterrupt):
        raise


def ask_confirm(cmd):
    """按需模式下询问用户是否允许执行命令。"""
    while True:
        ans = ask(col(f"  允许 AI 执行此命令吗？ [y/n]: ", C.YELLOW)).lower()
        if ans in ("y", "yes", "是", "1"):
            return True
        if ans in ("n", "no", "否", "0"):
            return False
        print(col("  请输入 y 或 n。", C.DIM))


# ==================== 文件夹选择 ====================
def pick_folder():
    """弹出系统文件夹选择窗口（tkinter）。失败返回 None。"""
    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        folder = filedialog.askdirectory(title="选择工作区目录")
        root.destroy()
        return folder if folder else None
    except Exception:
        return None


def choose_workspace(current):
    """选择工作区：支持窗口选择或手动输入路径。返回新路径或 None。"""
    print(col("  1. 弹出文件夹选择窗口", C.CYAN))
    print(col("  2. 手动输入目录路径", C.CYAN))
    print(col("  0. 取消", C.CYAN))
    choice = ask("  请选择: ").strip()
    if choice == "1":
        folder = pick_folder()
        if folder:
            return folder
        print(col("  未选择任何目录。", C.YELLOW))
        return None
    if choice == "2":
        path = ask("  请输入目录路径: ").strip().strip('"')
        if not path:
            return None
        path = os.path.abspath(os.path.expanduser(path))
        try:
            os.makedirs(path, exist_ok=True)
            return path
        except Exception as e:
            print(col(f"  目录无效: {e}", C.RED))
            return None
    return None


# ==================== 对话 ====================
def build_messages(cfg, model_id):
    messages = [{"role": "system", "content": cfg.data["settings"]["system_prompt"]}]
    messages += cfg.history(model_id)[-HISTORY_LIMIT:]
    return messages


class _Spinner:
    """请求期间在控制台打印等待点，首个 token 到达即停止（避免以为程序卡死）。"""

    def __init__(self, text="等待服务器响应"):
        self.text = text
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()

    def _run(self):
        print(col(self.text, C.DIM), end="", flush=True)
        while not self._stop.wait(0.5):
            print(col(".", C.DIM), end="", flush=True)
        print()

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=1)


def _friendly_error(e):
    import requests
    if isinstance(e, requests.exceptions.Timeout):
        return "请求超时：服务器长时间无响应（检查网络，或稍后再试）"
    if isinstance(e, requests.exceptions.ConnectionError):
        return "连接失败：无法到达服务器（检查 API 地址、网络是否可用）"
    if isinstance(e, requests.exceptions.HTTPError):
        return f"HTTP 错误: {e}"
    if isinstance(e, RuntimeError):
        return str(e)
    return f"请求异常: {e}"


def chat_once(cfg, provider, model, messages):
    """调用一次 API 并流式打印，返回 (可见回复文本, 命令块列表)；失败返回 (None, None)。"""
    settings = cfg.data["settings"]
    for attempt, stream in enumerate((True, False)):
        spinner = _Spinner("等待服务器响应")
        spinner.start()
        try:
            tokens = chat_request(provider, model["name"], messages, settings, stream=stream)

            def wrapped():
                first = True
                for tok in tokens:
                    if first:
                        spinner.stop()
                        first = False
                    yield tok

            result = stream_reply(wrapped())
            return result
        except Exception as e:
            spinner.stop()
            tag = C.YELLOW if attempt == 0 else C.RED
            print(col(f"\n[{_friendly_error(e)}]", tag))
            if attempt == 0:
                print(col("正在改用非流式方式重试...", C.DIM))
    return None, None


def chat_loop(cfg, model):
    """与选定模型对话。支持工作区命令执行。"""
    provider = cfg.provider(model.get("provider_id"))
    if not provider:
        print(col("[错误] 模型对应的供应商不存在，请重新添加。", C.RED))
        return

    settings = cfg.data["settings"]
    workspace = settings["workspace"]
    mode = settings["access_mode"]
    mode_text = "完全访问（命令自动执行）" if mode == "full" else "按需访问（命令先询问）"

    messages = build_messages(cfg, model["id"])
    history = messages[1:]  # 不含 system

    clear_screen()
    print(col("=" * 60, C.BLUE))
    print(col(f"  对话模型   : {model['display']}", C.GREEN))
    print(col(f"  工作区     : {workspace}", C.GREEN))
    print(col(f"  访问模式   : {mode_text}", C.GREEN))
    print(col("  输入 /help 查看对话指令", C.DIM))
    print(col("=" * 60, C.BLUE))

    # 继续上次对话时，把最近几轮历史打印出来，方便接着聊
    if history:
        print(col("----- 最近对话 -----", C.DIM))
        for m in history[-6:]:
            role = "你" if m["role"] == "user" else "AI"
            color = C.GREEN if m["role"] == "user" else C.CYAN
            text = m["content"]
            # 命令块执行结果这类内部消息，只显示一行摘要
            if text.startswith("[命令执行结果]"):
                text = "(已执行命令并取回结果)"
            print(col(f"{role}> ", color) + text)
        print(col("----- 历史结束 -----", C.DIM))

    while True:
        try:
            raw = ask(col("你 > ", C.GREEN)).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not raw:
            continue

        # ---- 对话指令 ----
        if raw == "/exit":
            break
        if raw == "/new":
            messages = build_messages(cfg, model["id"])
            history = messages[1:]
            cfg.data["histories"][model["id"]] = []
            cfg.save()
            print(col("(已开启新对话，历史已清空)", C.DIM))
            continue
        if raw == "/clear":
            clear_screen()
            print(col(f"模型: {model['display']} | 工作区: {workspace}", C.BLUE))
            continue
        if raw == "/workspace":
            new_ws = choose_workspace(workspace)
            if new_ws:
                workspace = new_ws
                settings["workspace"] = new_ws
                cfg.save()
                print(col(f"(工作区已切换: {workspace})", C.GREEN))
            continue
        if raw == "/model":
            print(col("(已保存当前对话，返回模型列表重新选择)", C.DIM))
            cfg.save()
            return
        if raw == "/help":
            print(col("""对话指令:
  /exit      退出对话，返回模型列表
  /new       开启新对话（清空当前模型历史）
  /clear     清屏
  /workspace 切换工作区
  /model     返回模型列表重新选择
  /help      显示本帮助""", C.CYAN))
            continue

        messages.append({"role": "user", "content": raw})
        history.append(messages[-1])

        steps = 0
        while steps < MAX_AGENT_STEPS:
            steps += 1
            print(col("AI > ", C.CYAN), end="")
            reply, blocks = chat_once(cfg, provider, model, messages)
            if reply is None:
                break
            messages.append({"role": "assistant", "content": reply})
            history.append(messages[-1])

            if not blocks:
                break

            # 执行命令块
            ran_any = False
            for cmd in blocks:
                print(col(f"\n→ 执行命令: {cmd}", C.MAGENTA))
                should_run = True
                if mode == "on_demand":
                    should_run = ask_confirm(cmd)
                if not should_run:
                    messages.append({"role": "user", "content":
                                     f"用户取消了命令执行：{cmd}，请改用其他方式或询问用户。"})
                    history.append(messages[-1])
                    print(col("(已跳过该命令)", C.DIM))
                    continue
                if mode == "full":
                    print(col("(完全访问模式，自动执行)", C.DIM))
                ok, out = run_command(cmd, workspace)
                status = "成功" if ok else "失败"
                print(col(f"  [{status}] 输出:", C.DIM))
                if out:
                    print(col(out, C.DIM))
                else:
                    print(col("  (无输出)", C.DIM))
                result_note = f"[命令执行结果]\n命令: {cmd}\n状态: {status}\n输出:\n{out}"
                messages.append({"role": "user", "content": result_note})
                history.append(messages[-1])
                ran_any = True

            if not ran_any:
                break
            print(col("— AI 正在根据执行结果继续 —", C.DIM))

        if steps >= MAX_AGENT_STEPS:
            print(col(f"(已达单次连续执行上限 {MAX_AGENT_STEPS} 轮，如需要请继续提问)", C.DIM))

        # 保存历史（截断）
        cfg.data["histories"][model["id"]] = history[-HISTORY_LIMIT:]
        cfg.save()
        print(col("-" * 60, C.BLUE))


# ==================== 主菜单 ====================
def main_menu(cfg):
    s = cfg.data["settings"]
    mode_text = "完全访问" if s["access_mode"] == "full" else "按需访问"
    print()
    print(col("=" * 44, C.BLUE))
    print(col(f"  {APP_NAME} v{APP_VERSION}", C.BOLD))
    print(col(f"  工作区   : {s['workspace']}", C.GREEN))
    print(col(f"  访问模式 : {mode_text}", C.GREEN))
    print(col("=" * 44, C.BLUE))
    print(col(" 1. 连接已有模型", C.CYAN))
    print(col(" 2. 添加供应商", C.CYAN))
    print(col(" 3. 设置", C.CYAN))
    print(col(" 0. 退出", C.CYAN))


def connect_menu(cfg):
    """选项 1：连接已有模型进行对话。"""
    models = cfg.data["models"]
    if not models:
        clear_screen()
        print(col("\n[提示] 还没有任何模型，请先选择“2. 添加供应商”。", C.YELLOW))
        return
    while True:
        clear_screen()
        print(col("========== 选择模型 ==========", C.BLUE))
        for i, m in enumerate(models, 1):
            n = len(cfg.history(m["id"]))
            tag = f"  (历史 {n} 条)" if n else ""
            print(col(f" {i}. {m['display']}", C.CYAN) + col(tag, C.DIM))
        print(col(" 0. 返回主菜单", C.CYAN))
        try:
            choice = ask("请选择: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if choice == "0":
            return
        if not choice.isdigit() or not (1 <= int(choice) <= len(models)):
            print(col("无效选择。", C.YELLOW))
            continue
        model = models[int(choice) - 1]

        # 继续上次对话 / 新建对话
        n = len(cfg.history(model["id"]))
        print()
        if n:
            print(col("========== 对话历史 ==========", C.BLUE))
            print(col(f" 1. 继续上次对话（{n} 条记录）", C.CYAN))
            print(col(" 2. 新建对话", C.CYAN))
            his_choice = ask("请选择: ").strip()
            if his_choice == "2":
                cfg.data["histories"][model["id"]] = []
                cfg.save()
                print(col("(已开启全新对话)", C.DIM))
        else:
            print(col("(首次对话，已开启全新会话)", C.DIM))

        # 工作区选择
        print()
        print(col("========== 工作区 ==========", C.BLUE))
        print(col(f" 1. 使用当前工作区: {cfg.data['settings']['workspace']}", C.CYAN))
        print(col(" 2. 选择其他工作区", C.CYAN))
        ws_choice = ask("请选择: ").strip()
        if ws_choice == "2":
            new_ws = choose_workspace(cfg.data["settings"]["workspace"])
            if new_ws:
                cfg.data["settings"]["workspace"] = new_ws
                cfg.save()
        chat_loop(cfg, model)


def add_provider_menu(cfg):
    """选项 2：添加供应商（内置 + 自定义）并拉取模型。"""
    existing_ids = {p["id"] for p in cfg.data["providers"]}
    while True:
        clear_screen()
        print(col("========== 添加供应商 ==========", C.BLUE))
        options = []
        for i, p in enumerate(DEFAULT_PROVIDERS, 1):
            tag = " (已添加)" if p["id"] in existing_ids else ""
            print(col(f" {i}. {p['name']}  [{p['base_url']}]{tag}", C.CYAN))
            options.append(p)
        print(col(f" {len(options) + 1}. 自定义供应商", C.MAGENTA))
        print(col(" 0. 返回主菜单", C.CYAN))
        try:
            choice = ask("请选择: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if choice == "0":
            return
        if choice.isdigit() and 1 <= int(choice) <= len(options):
            provider = dict(options[int(choice) - 1])
            provider["full_endpoint"] = False
            existing = cfg.provider(provider["id"])
            if existing:
                key_hint = existing.get("api_key") or ""
                key = ask(col(f"该供应商已存在（Key: {key_hint[:6] or '(空)'}...），"
                                f"请输入新的 API Key（回车保留原值）: ", C.YELLOW)).strip()
                if key:
                    existing["api_key"] = key
                    cfg.save()
                provider = existing
            else:
                key = ask(col("请输入 API Key（无鉴权的本地服务可直接回车）: ", C.YELLOW)).strip()
                provider["api_key"] = key
                cfg.data["providers"].append(provider)
                existing_ids.add(provider["id"])
                cfg.save()
            add_models_menu(cfg, provider)
        elif choice == str(len(options) + 1):
            add_custom_provider(cfg, existing_ids)
        else:
            print(col("无效选择。", C.YELLOW))


def add_custom_provider(cfg, existing_ids):
    """自定义供应商：名称 + API 地址 + 是否完整地址 + API Key。"""
    print(col("--- 自定义供应商 ---", C.MAGENTA))
    name = ask(col("供应商名称: ", C.YELLOW)).strip()
    if not name:
        print(col("名称不能为空。", C.YELLOW))
        return
    url = ask(col("API 地址: ", C.YELLOW)).strip()
    if not url:
        print(col("地址不能为空。", C.YELLOW))
        return
    if not url.lower().startswith(("http://", "https://")):
        url = "https://" + url
    full = ask(col("该地址是否已是完整接口地址（含 /chat/completions）？[y/n]: ", C.YELLOW)).strip().lower()
    full_endpoint = full in ("y", "yes", "是", "1")
    key = ask(col("API Key（无鉴权可留空）: ", C.YELLOW)).strip()

    provider = {
        "id": "custom-" + uuid.uuid4().hex[:8],
        "name": name,
        "base_url": url,
        "api_key": key,
        "full_endpoint": full_endpoint,
    }
    cfg.data["providers"].append(provider)
    cfg.save()
    print(col(f"(供应商“{name}”已添加)", C.GREEN))
    add_models_menu(cfg, provider)


def add_models_menu(cfg, provider):
    """拉取供应商模型列表，让用户选择要添加的模型。"""
    print()
    print(col(f"--- 拉取“{provider['name']}”的模型列表 ---", C.MAGENTA))
    ids = []
    try:
        ids = fetch_models(provider)
    except Exception as e:
        print(col(f"[无法拉取模型列表: {e}]", C.YELLOW))
    if ids:
        print(col(f"共获取 {len(ids)} 个模型：", C.CYAN))
        for i, mid in enumerate(ids, 1):
            print(col(f" {i}. {mid}", C.CYAN))
        sel = ask(col("输入要添加的模型序号（多个用逗号分隔，输入 all 全选）: ", C.YELLOW)).strip()
        if sel.lower() == "all":
            picked = ids
        else:
            picked = []
            for part in sel.replace("，", ",").split(","):
                part = part.strip()
                if part.isdigit() and 1 <= int(part) <= len(ids):
                    picked.append(ids[int(part) - 1])
    else:
        manual = ask(col("请手动输入要添加的模型名称（多个用逗号分隔）: ", C.YELLOW)).strip()
        picked = [m.strip() for m in manual.replace("，", ",").split(",") if m.strip()]

    added = 0
    for mid in picked:
        display = f"{provider['name']} - {mid}"
        cfg.data["models"].append({
            "id": "m-" + uuid.uuid4().hex[:8],
            "provider_id": provider["id"],
            "name": mid,
            "display": display,
        })
        added += 1
        print(col(f"  ✓ 已添加模型: {display}", C.GREEN))
    if added:
        cfg.save()
    print(col("(如需继续添加其他模型，可再次进入“添加供应商”。)", C.DIM))


# ==================== 设置 ====================
def settings_menu(cfg):
    while True:
        s = cfg.data["settings"]
        mode_text = "完全访问" if s["access_mode"] == "full" else "按需访问"
        clear_screen()
        print(col("========== 设置 ==========", C.BLUE))
        print(col(f" 1. AI 访问模式       : {mode_text}", C.CYAN))
        print(col(f" 2. 温度 (temperature): {s['temperature']}", C.CYAN))
        print(col(f" 3. 最大回复 tokens   : {s['max_tokens']}", C.CYAN))
        print(col(f" 4. 系统提示词         : (当前 {len(s['system_prompt'])} 字)", C.CYAN))
        print(col(f" 5. 默认工作区         : {s['workspace']}", C.CYAN))
        print(col(" 6. 管理供应商和模型", C.CYAN))
        print(col(" 7. 清除对话历史", C.CYAN))
        print(col(" 0. 返回主菜单", C.CYAN))
        try:
            choice = ask("请选择: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if choice == "0":
            return
        if choice == "1":
            print(col("完全访问: AI 执行命令无需确认，可自行操作工作区（谨慎）。", C.YELLOW))
            print(col("按需访问: AI 每次要执行命令时都会先询问你。", C.YELLOW))
            new_mode = ask(col(f"选择模式 [{s['access_mode']}] (full/on_demand): ", C.YELLOW)).strip()
            if new_mode in ("full", "on_demand"):
                s["access_mode"] = new_mode
                cfg.save()
                print(col("已保存。", C.GREEN))
            else:
                print(col("无效输入。", C.YELLOW))
        elif choice == "2":
            try:
                val = float(ask(col("温度 (0.0~2.0): ", C.YELLOW)).strip())
                if 0.0 <= val <= 2.0:
                    s["temperature"] = val
                    cfg.save()
                    print(col("已保存。", C.GREEN))
                else:
                    print(col("超出范围。", C.YELLOW))
            except ValueError:
                print(col("无效数字。", C.YELLOW))
        elif choice == "3":
            try:
                val = int(ask(col("最大回复 tokens (正整数): ", C.YELLOW)).strip())
                if val > 0:
                    s["max_tokens"] = val
                    cfg.save()
                    print(col("已保存。", C.GREEN))
                else:
                    print(col("无效数字。", C.YELLOW))
            except ValueError:
                print(col("无效数字。", C.YELLOW))
        elif choice == "4":
            print(col("当前系统提示词:", C.CYAN))
            print(col(s["system_prompt"], C.DIM))
            print(col("输入新的系统提示词（输入 . 保持不变，输入 /d 恢复默认）:", C.CYAN))
            new_prompt = ask("> ").strip()
            if new_prompt == ".":
                continue
            if new_prompt == "/d":
                s["system_prompt"] = DEFAULT_SYSTEM_PROMPT
            elif new_prompt:
                s["system_prompt"] = new_prompt
            cfg.save()
            print(col("已保存。", C.GREEN))
        elif choice == "5":
            new_ws = choose_workspace(s["workspace"])
            if new_ws:
                s["workspace"] = new_ws
                cfg.save()
                print(col(f"默认工作区已更新: {new_ws}", C.GREEN))
        elif choice == "6":
            manage_menu(cfg)
        elif choice == "7":
            clear_history_menu(cfg)
        else:
            print(col("无效选择。", C.YELLOW))


def manage_menu(cfg):
    while True:
        print()
        print(col("========== 管理供应商和模型 ==========", C.BLUE))
        print(col(" 1. 查看供应商列表", C.CYAN))
        print(col(" 2. 删除供应商（连带其模型）", C.CYAN))
        print(col(" 3. 查看模型列表", C.CYAN))
        print(col(" 4. 删除模型", C.CYAN))
        print(col(" 0. 返回", C.CYAN))
        try:
            choice = ask("请选择: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if choice == "0":
            return
        if choice == "1":
            providers = cfg.data["providers"]
            if not providers:
                print(col("(暂无供应商)", C.DIM))
                continue
            for i, p in enumerate(providers, 1):
                key = (p.get("api_key") or "")
                key_disp = (key[:6] + "...") if key else "(空)"
                print(col(f" {i}. {p['name']}  [{p['base_url']}]  Key: {key_disp}", C.CYAN))
        elif choice == "2":
            providers = cfg.data["providers"]
            if not providers:
                print(col("(暂无供应商)", C.DIM))
                continue
            for i, p in enumerate(providers, 1):
                print(col(f" {i}. {p['name']}", C.CYAN))
            sel = ask(col("输入要删除的供应商序号: ", C.YELLOW)).strip()
            if not sel.isdigit() or not (1 <= int(sel) <= len(providers)):
                print(col("无效选择。", C.YELLOW))
                continue
            p = providers[int(sel) - 1]
            if ask(col(f"确认删除供应商“{p['name']}”及其全部模型？[y/n]: ", C.RED)).strip().lower() in ("y", "yes"):
                cfg.data["providers"].remove(p)
                cfg.data["models"] = [m for m in cfg.data["models"] if m["provider_id"] != p["id"]]
                for mid in [m["id"] for m in cfg.data["models"]]:
                    cfg.data["histories"].pop(mid, None)
                cfg.save()
                print(col(f"已删除“{p['name']}”。", C.GREEN))
        elif choice == "3":
            models = cfg.data["models"]
            if not models:
                print(col("(暂无模型)", C.DIM))
                continue
            for i, m in enumerate(models, 1):
                print(col(f" {i}. {m['display']}", C.CYAN))
        elif choice == "4":
            models = cfg.data["models"]
            if not models:
                print(col("(暂无模型)", C.DIM))
                continue
            for i, m in enumerate(models, 1):
                print(col(f" {i}. {m['display']}", C.CYAN))
            sel = ask(col("输入要删除的模型序号（多个用逗号分隔）: ", C.YELLOW)).strip()
            idxs = []
            for part in sel.replace("，", ",").split(","):
                part = part.strip()
                if part.isdigit() and 1 <= int(part) <= len(models):
                    idxs.append(int(part) - 1)
            if not idxs:
                print(col("无效选择。", C.YELLOW))
                continue
            for i in sorted(idxs, reverse=True):
                m = models[i]
                cfg.data["models"].remove(m)
                cfg.data["histories"].pop(m["id"], None)
                print(col(f"  ✗ 已删除模型: {m['display']}", C.GREEN))
            cfg.save()


def clear_history_menu(cfg):
    models = cfg.data["models"]
    if not models:
        print(col("(暂无模型)", C.DIM))
        return
    print(col("选择要清除历史的模型（输入 0 清除全部）:", C.CYAN))
    for i, m in enumerate(models, 1):
        n = len(cfg.history(m["id"]))
        print(col(f" {i}. {m['display']}  (历史 {n} 条)", C.CYAN))
    sel = ask(col("请选择: ", C.YELLOW)).strip()
    if sel == "0":
        cfg.data["histories"] = {}
        cfg.save()
        print(col("已清除全部对话历史。", C.GREEN))
    elif sel.isdigit() and 1 <= int(sel) <= len(models):
        m = models[int(sel) - 1]
        cfg.data["histories"][m["id"]] = []
        cfg.save()
        print(col(f"已清除“{m['display']}”的对话历史。", C.GREEN))
    else:
        print(col("无效选择。", C.YELLOW))


# ==================== 入口 ====================
def main():
    cfg = Config()
    clear_screen()
    print(col(f"===== {APP_NAME} v{APP_VERSION} =====", C.BOLD))
    print(col(f"配置: {config_path()}", C.DIM))
    while True:
        main_menu(cfg)
        try:
            choice = ask(col("请选择: ", C.GREEN)).strip()
        except (EOFError, KeyboardInterrupt):
            print(col("\n再见！", C.BLUE))
            break
        try:
            if choice == "1":
                connect_menu(cfg)
            elif choice == "2":
                add_provider_menu(cfg)
            elif choice == "3":
                settings_menu(cfg)
            elif choice in ("0", "q", "exit"):
                print(col("再见！", C.BLUE))
                break
            else:
                print(col("无效选择。", C.YELLOW))
        except (EOFError, KeyboardInterrupt):
            print(col("\n返回主菜单。", C.BLUE))
            break


if __name__ == "__main__":
    main()
