# -*- coding: utf-8 -*-
"""本地推理引擎：加载 GGUF 模型，流式生成。

设计：
- 模型按路径懒加载，常驻缓存（避免每次对话重新加载几 GB）。
- 同一时刻只服务一个生成请求（llama.cpp 实例本身非线程安全并发）。
- GPU offload 层数可配（0=纯 CPU）。
- 多模态：VLM 模型带 mmproj，v1 先做文本。
"""
import os
import threading
import time

import ai_console as core

# 模块级状态
_loaded = {}          # model_path -> {"llm": Llama, "lock": threading.Lock, "at": float}
_meta_lock = threading.Lock()
_active_lock = threading.Lock()   # 全局串行：同一时刻只跑一次推理


def models_dir():
    # 与 config.json 同目录（%APPDATA%\darling-ai\models），Program Files 只读也能写
    d = os.path.join(os.path.dirname(core.config_path()), "models")
    os.makedirs(d, exist_ok=True)
    return d


def _safe_name(path):
    return os.path.splitext(os.path.basename(path))[0]


def list_local_models():
    """扫描 models 目录下的 .gguf，返回可对话模型列表。"""
    out = []
    d = models_dir()
    for fn in sorted(os.listdir(d)):
        if not fn.lower().endswith(".gguf"):
            continue
        fp = os.path.join(d, fn)
        try:
            size = os.path.getsize(fp)
        except OSError:
            size = 0
        out.append({
            "id": "local::" + fn,
            "name": _safe_name(fp),
            "path": fp,
            "size_mb": round(size / 1024 / 1024),
        })
    return out


def detect_gpu():
    """探测本机 GPU，返回 {"has_nvidia": bool, "cards": [str], "recommend_gpu_layers": int}。"""
    cards = []
    has_nvidia = False
    try:
        import subprocess
        # Windows: wmic 取显卡名
        si = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name"],
            capture_output=True, text=True, timeout=10,
        )
        for line in (si.stdout or "").splitlines():
            line = line.strip()
            if line:
                cards.append(line)
                low = line.lower()
                if "nvidia" in low or "geforce" in low or "rtx" in low or "gtx" in low:
                    has_nvidia = True
    except Exception:
        pass
    # Linux 兜底
    if not cards:
        try:
            import subprocess
            si = subprocess.run(["lspci"], capture_output=True, text=True, timeout=10)
            for line in (si.stdout or "").splitlines():
                if "VGA" in line or "3D controller" in line:
                    cards.append(line.strip())
                    low = line.lower()
                    if "nvidia" in low:
                        has_nvidia = True
        except Exception:
            pass
    return {
        "has_nvidia": has_nvidia,
        "cards": cards,
        "recommend_gpu_layers": 35 if has_nvidia else 0,
    }


def _get_llm(path, n_gpu_layers, n_ctx):
    with _meta_lock:
        entry = _loaded.get(path)
    if entry is None:
        from llama_cpp import Llama  # 延迟导入
        llm = Llama(
            model_path=path,
            n_ctx=n_ctx,
            n_gpu_layers=n_gpu_layers,
            verbose=False,
            use_mmap=True,
        )
        entry = {"llm": llm, "lock": threading.Lock(), "at": time.time()}
        with _meta_lock:
            _loaded[path] = entry
    return entry


def chat_stream(messages, settings, local_path):
    """流式生成。messages=[{role,content},...]。yield token 字符串。"""
    n_ctx = int(settings.get("local_n_ctx", 4096) or 4096)
    n_gpu = int(settings.get("local_gpu_layers", 0) or 0)
    if settings.get("local_gpu_mode", "cpu") == "cpu":
        n_gpu = 0
    temp = float(settings.get("temperature", 0.7) or 0.7)
    max_tok = int(settings.get("max_tokens", 1024) or 1024)

    entry = _get_llm(local_path, n_gpu, n_ctx)
    llm = entry["llm"]
    with _active_lock:
        with entry["lock"]:
            resp = llm.create_chat_completion(
                messages=messages,
                stream=True,
                temperature=temp,
                max_tokens=max_tok,
            )
            for chunk in resp:
                try:
                    delta = chunk["choices"][0]["delta"].get("content") or ""
                except (KeyError, IndexError, TypeError):
                    delta = ""
                if delta:
                    yield delta


def warmup(local_path, settings):
    """预热加载模型（首次切换到本地模型时调用，避免对话时卡很久）。"""
    n_ctx = int(settings.get("local_n_ctx", 4096) or 4096)
    n_gpu = int(settings.get("local_gpu_layers", 0) or 0)
    if settings.get("local_gpu_mode", "cpu") == "cpu":
        n_gpu = 0
    _get_llm(local_path, n_gpu, n_ctx)
