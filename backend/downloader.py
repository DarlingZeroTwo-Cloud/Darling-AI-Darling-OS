# -*- coding: utf-8 -*-
"""模型下载器：多线程 Range 分块、断点续传、进度查询、暂停/继续/取消。

默认源 hf-mirror.com（国内镜像），可切官方源。
"""
import os
import threading
import time
import urllib.request

import ai_console as core
import local_engine

TASKS = {}
_TLOCK = threading.Lock()
_CHUNK = 8 * 1024 * 1024
_THREADS = 8

MIRROR = "https://hf-mirror.com"
ORIGIN = "https://huggingface.co"


def _base(settings):
    return MIRROR if settings.get("hf_mirror", True) else ORIGIN


def catalog_path():
    import sys
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        p = os.path.join(meipass, "models_catalog.json")
        if os.path.exists(p):
            return p
        # onedir: catalog 放在 exe 同级目录
        exe_dir = os.path.dirname(os.path.abspath(sys.executable))
        p2 = os.path.join(exe_dir, "models_catalog.json")
        if os.path.exists(p2):
            return p2
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "models_catalog.json")


def load_catalog():
    import json
    with open(catalog_path(), "r", encoding="utf-8-sig") as f:
        return json.load(f)["models"]


def find_model(catalog_id):
    for m in load_catalog():
        if m["id"] == catalog_id:
            return m
    return None


def _build_url(base, repo, filename):
    return f"{base}/{repo}/resolve/main/{filename}"


def start_download(catalog_id, settings):
    m = find_model(catalog_id)
    if not m:
        raise ValueError("模型不存在于市场")
    if not m.get("v1_supported", True):
        raise ValueError("该模型 v1 暂不支持（生图/视频在下一版开放）")
    dest_dir = local_engine.models_dir()
    dest = os.path.join(dest_dir, m["file"])
    if os.path.exists(dest):
        return {"status": "existing", "path": dest,
                "size_mb": round(os.path.getsize(dest) / 1024 / 1024)}

    dl_id = catalog_id + "_" + str(int(time.time()))
    base = _base(settings)
    url = _build_url(base, m["repo"], m["file"])
    state = {
        "id": dl_id,
        "catalog_id": catalog_id,
        "name": m["name"],
        "url": url,
        "dest": dest,
        "total": 0,
        "done": 0,
        "speed": 0,
        "status": "starting",
        "error": None,
        "paused": False,
        "cancelled": False,
        "resume_evt": threading.Event(),
        "started_at": time.time(),
    }
    with _TLOCK:
        TASKS[dl_id] = state
    threading.Thread(target=_run_download, args=(state,), daemon=True).start()
    return {"status": "started", "download_id": dl_id}


def status(dl_id):
    with _TLOCK:
        t = TASKS.get(dl_id)
        if not t:
            return None
        out = dict(t)
        out.pop("resume_evt", None)
        return out


def all_status():
    with _TLOCK:
        return [{k: v for k, v in dict(t).items() if k != "resume_evt"}
                for t in TASKS.values()]


def pause(dl_id):
    with _TLOCK:
        t = TASKS.get(dl_id)
        if t:
            t["paused"] = True
            t["resume_evt"].clear()
    return True


def resume(dl_id):
    with _TLOCK:
        t = TASKS.get(dl_id)
        if t:
            t["paused"] = False
            t["resume_evt"].set()
    return True


def cancel(dl_id):
    with _TLOCK:
        t = TASKS.get(dl_id)
        if not t:
            return False
        t["cancelled"] = True
        t["paused"] = False
        t["resume_evt"].set()
        part = t["dest"] + ".part"
    try:
        if os.path.exists(part):
            os.remove(part)
    except Exception:
        pass
    return True


def _wait_if_paused(state):
    """阻塞直到未暂停（或被取消）。"""
    while state["paused"] and not state["cancelled"]:
        state["resume_evt"].wait(timeout=0.5)


def _run_download(state):
    part = state["dest"] + ".part"
    try:
        req = urllib.request.Request(state["url"], method="HEAD")
        with urllib.request.urlopen(req, timeout=30) as r:
            total = int(r.headers.get("Content-Length", 0))
        state["total"] = total
        state["status"] = "downloading"

        have = os.path.getsize(part) if os.path.exists(part) else 0
        if have > total:
            have = 0
            if os.path.exists(part):
                os.remove(part)

        # 预分配文件
        if not os.path.exists(part) or os.path.getsize(part) == 0:
            with open(part, "wb") as f:
                f.truncate(total)

        # 分块列表
        pieces = []
        pos = have
        while pos < total:
            end = min(pos + _CHUNK - 1, total - 1)
            pieces.append((pos, end))
            pos = end + 1
        state["done"] = have

        errors = []
        counter_lock = threading.Lock()

        def dl_piece(start, end):
            _wait_if_paused(state)
            if state["cancelled"]:
                return
            req = urllib.request.Request(state["url"],
                                         headers={"Range": f"bytes={start}-{end}"})
            retry = 0
            while True:
                if state["cancelled"]:
                    return
                _wait_if_paused(state)
                if state["cancelled"]:
                    return
                try:
                    with urllib.request.urlopen(req, timeout=60) as r:
                        with open(part, "r+b") as out:
                            out.seek(start)
                            while True:
                                _wait_if_paused(state)
                                if state["cancelled"]:
                                    return
                                buf = r.read(1 << 20)
                                if not buf:
                                    break
                                out.write(buf)
                                with counter_lock:
                                    state["done"] += len(buf)
                    return
                except Exception:
                    retry += 1
                    if retry > 5:
                        errors.append(f"{start}-{end}")
                        return
                    time.sleep(1.5)

        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=_THREADS) as ex:
            list(ex.map(lambda se: dl_piece(*se), pieces))

        if state["cancelled"]:
            state["status"] = "cancelled"
            return
        if errors:
            state["status"] = "error"
            state["error"] = "部分分片下载失败，请重试"
            return

        actual = os.path.getsize(part)
        if actual != total:
            state["status"] = "error"
            state["error"] = f"大小不符 {actual}/{total}"
            return
        os.replace(part, state["dest"])
        state["status"] = "done"
    except Exception as e:
        if not state["cancelled"]:
            state["status"] = "error"
            state["error"] = str(e)


def delete_local_model(path):
    try:
        if os.path.exists(path):
            os.remove(path)
        for suffix in (".mmproj", ".part"):
            p = path.replace(".gguf", suffix)
            if os.path.exists(p):
                os.remove(p)
        return True
    except Exception:
        return False
