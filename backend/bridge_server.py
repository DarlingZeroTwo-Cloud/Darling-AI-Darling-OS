# -*- coding: utf-8 -*-
"""darling-ai v1.0 桥接服务：本地 HTTP + SSE。

Flutter 前端通过本服务访问 Python 核心（ai_console.py）。
- REST：配置 / 会话 / 模型 / 插件管理
- SSE：流式对话（token / 工具 / 状态 / 确认 / 完成）
- POST /api/decision：按需访问模式下回应命令确认

端口：127.0.0.1:19730
"""
import json
import os
import queue
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import ai_console as core
import websearch

HOST, PORT = "127.0.0.1", 19730

JOBS = {}
JOBS_LOCK = threading.Lock()


# ==================== 流式对话（事件化） ====================
def stream_collect(tokens, extra_markers=None, on_visible=None):
    """与 core.stream_reply 相同的块解析逻辑，可见文本通过回调吐出。
    返回 (完整可见文本, 块列表)。"""
    CMD_OPEN, CMD_CLOSE = core.CMD_OPEN, core.CMD_CLOSE
    markers = [("CMD", CMD_OPEN, CMD_CLOSE, None, None)]
    if extra_markers:
        markers += [("P", opn, clo, pname, name)
                    for (pname, name, opn, clo, desc) in extra_markers]
    opens = [m[1] for m in markers]
    closes = [m[2] for m in markers]
    all_marks = opens + closes

    def is_prefix(s):
        return any(m.startswith(s) for m in all_marks)

    def find_earliest(s, needles):
        best = -1
        for n in needles:
            i = s.find(n)
            if i >= 0 and (best < 0 or i < best):
                best = i
        return best

    pending = ""
    cur_kind = None
    cur_open = None
    cur_close = None
    cur_pname = None
    cur_tname = None
    block_buf = ""
    blocks = []
    full = []

    def flush_visible(s):
        if s:
            if on_visible:
                on_visible(s)
            full.append(s)

    def emit_block():
        content = block_buf.strip()
        if not content:
            return
        if cur_kind == "CMD":
            blocks.append(content)
        else:
            blocks.append((cur_pname, cur_tname, content))

    for tok in tokens:
        pending += tok
        while pending:
            if cur_open is None:
                idx = find_earliest(pending, opens)
                if idx >= 0:
                    flush_visible(pending[:idx])
                    for m in markers:
                        if pending[idx:].startswith(m[1]):
                            cur_kind = m[0]
                            cur_open = m[1]
                            cur_close = m[2]
                            cur_pname = m[3]
                            cur_tname = m[4]
                            break
                    pending = pending[idx + len(cur_open):]
                    block_buf = ""
                    continue
                held = 0
                for k in range(1, max(len(m) for m in all_marks)):
                    if is_prefix(pending[-k:]):
                        held = k
                if held:
                    if len(pending) > held:
                        flush_visible(pending[:-held])
                    pending = pending[-held:]
                    break
                flush_visible(pending)
                pending = ""
            else:
                idx = pending.find(cur_close)
                if idx >= 0:
                    block_buf += pending[:idx]
                    pending = pending[idx + len(cur_close):]
                    emit_block()
                    cur_open = cur_close = cur_kind = None
                    cur_pname = cur_tname = None
                    continue
                held = 0
                for k in range(1, len(cur_close)):
                    if cur_close.startswith(pending[-k:]):
                        held = k
                if held:
                    if len(pending) > held:
                        block_buf += pending[:-held]
                    pending = pending[-held:]
                    break
                block_buf += pending
                pending = ""
    if cur_open is not None:
        block_buf += pending
        emit_block()
    elif pending:
        flush_visible(pending)
    return "".join(full), blocks


class Job:
    def __init__(self, cfg, model, text):
        self.id = uuid.uuid4().hex[:12]
        self.cfg = cfg
        self.model = model
        self.text = text
        self.q = queue.Queue()
        self.decision_evt = threading.Event()
        self.decision_allow = None
        self.finished = threading.Event()
        self.stop = threading.Event()
        self.web_results = []
        self.images = []


def _emit(job, type_, **kw):
    job.q.put({"type": type_, **kw})


def _mirror_all(cfg, hist):
    """把一份历史镜像到所有模型的 histories（core 按模型读，全共享）。"""
    hist = list(hist)
    for m in cfg.data["models"]:
        cfg.data["histories"][m["id"]] = hist


def _chat_once_stream(job, messages, settings, provider):
    """流式调一次 API：token 事件 + 返回 (可见文本, 块列表)。"""
    try:
        retries = max(0, int(settings.get("api_retries", 1)))
    except Exception:
        retries = 1
    markers = core.plugin_markers_for_request()
    # 每轮请求前都做上下文压缩：工具/搜索循环后消息会暴涨，防止超限中断
    try:
        threshold = int(settings.get("context_compress_threshold", 60000))
    except Exception:
        threshold = 60000
    req_messages = core.compress_messages(messages, max_tokens=threshold)
    compressed_once = req_messages is not messages
    for attempt in range(1 + retries):
        for stream in (True, False):
            try:
                tokens = core.chat_request(
                    provider, job.model["name"], req_messages, settings, stream=stream)
                return stream_collect(tokens, extra_markers=markers,
                                      on_visible=lambda s: _emit(job, "token", text=s))
            except Exception as e:
                err = str(e)
                # 上下文超长：压缩后重试一次
                if (not compressed_once and any(k in err.lower() for k in (
                        "context length", "maximum context", "token", "too long",
                        "prompt is too", "400"))):
                    _emit(job, "state", text="上下文较长，已自动压缩后继续…")
                    req_messages = core.compress_messages(messages, max_tokens=threshold)
                    compressed_once = True
                    continue
                _emit(job, "error", text=core._friendly_error(e))
                if attempt < retries:
                    time.sleep(1)
    return None, None


def stream_agent(job):
    """事件化版本的 ChatWorker.run。"""
    cfg, model, user_text = job.cfg, job.model, job.text
    settings = cfg.data["settings"]
    provider = cfg.provider(model.get("provider_id"))
    if not provider:
        _emit(job, "error", text="模型对应的供应商不存在，请重新添加。")
        _emit(job, "done", text="", ok=False)
        job.finished.set()
        return
    workspace = settings.get("workspace") or "."
    mode = settings.get("access_mode", "on_demand")

    messages = core.build_messages(cfg, model["id"])
    history = messages[1:]
    # 联网搜索结果注入
    if job.web_results:
        lines = []
        for i, r in enumerate(job.web_results[:8], 1):
            title = r.get("title", "")
            url = r.get("url", "")
            snip = r.get("snippet", "")
            lines.append(f"[{i}] {title} ({url})\n{snip}")
        web_ctx = ("以下是从互联网搜索到的相关信息，请优先参考它们回答用户的问题。\n\n"
                   + "\n\n".join(lines))
        messages.append({"role": "user", "content": web_ctx})
        history.append(messages[-1])
        _emit(job, "tool", title="联网搜索", content=f"已注入 {len(job.web_results)} 条搜索结果作为参考", ok=True)
    history.append({"role": "user", "content": user_text, "ts": time.time()})
    # 多模态图片：把最后一条用户消息改造成 content 数组
    if job.images:
        content = [{"type": "text", "text": user_text}]
        for img in job.images[:6]:
            content.append({"type": "image_url",
                            "image_url": {"url": img}})
        history[-1]["content"] = content
        _emit(job, "tool", title="图片输入",
              content=f"已附加 {len(job.images[:6])} 张图片给视觉模型", ok=True)
    messages.append(history[-1])

    steps = 0
    last_text = ""
    ok_flag = True
    try:
        while steps < core.MAX_AGENT_STEPS:
            if job.stop.is_set():
                _emit(job, "state", text="已停止")
                break
            steps += 1
            _emit(job, "state", text="正在思考…" if steps > 1 else "正在连接服务器…")
            reply, blocks = _chat_once_stream(job, messages, settings, provider)
            if reply is None:
                ok_flag = False
                break
            last_text = reply
            messages.append({"role": "assistant", "content": reply, "ts": time.time()})
            history.append(messages[-1])
            if not blocks:
                break
            ran_any = False
            for blk in blocks:
                if isinstance(blk, str):
                    cmd = blk
                    _emit(job, "tool", title="执行命令", content=cmd, ok=True)
                    should_run = True
                    if mode == "on_demand":
                        job.decision_evt.clear()
                        job.decision_allow = None
                        _emit(job, "ask", cmd=cmd)
                        job.decision_evt.wait(timeout=180)
                        if job.decision_allow is None:
                            messages.append({"role": "user", "content":
                                             f"用户没有回应命令确认：{cmd}，请改用其他方式。"})
                            history.append(messages[-1])
                            continue
                        should_run = job.decision_allow
                    if not should_run:
                        messages.append({"role": "user", "content":
                                         f"用户取消了命令执行：{cmd}，请改用其他方式或询问用户。"})
                        history.append(messages[-1])
                        _emit(job, "tool", title="执行命令", content="用户拒绝执行，已跳过", ok=False)
                        continue
                    try:
                        ok, out = core.run_command(cmd, workspace)
                    except Exception as e:
                        ok, out = False, f"(命令执行异常: {e})"
                    _emit(job, "tool", title="执行命令", content=out or "(无输出)", ok=ok)
                    result_note = f"[命令执行结果]\n命令: {cmd}\n状态: {'成功' if ok else '失败'}\n输出:\n{out}"
                    messages.append({"role": "user", "content": result_note})
                    history.append(messages[-1])
                    ran_any = True
                else:
                    pname, tname, content = blk
                    # 内置联网搜索已启用时：跳过插件联网搜索（search/deep_search），
                    # 避免重复搜索 + 上下文翻倍导致对话中断；fetch 保留（不同能力）
                    if job.web_results and pname == "联网搜索" and tname in ("search", "deep_search"):
                        messages.append({"role": "user", "content":
                                         "[提示] 本次对话已使用内置联网搜索提供了搜索结果，请直接基于已有搜索结果回答，无需重复联网搜索。"})
                        history.append(messages[-1])
                        _emit(job, "tool", title="插件 · 联网搜索",
                              content="内置联网搜索已启用，跳过插件重复搜索，直接使用已有结果", ok=True)
                        ran_any = True
                        continue
                    handler_fn = None
                    for p in core.load_plugins():
                        if p["name"] == pname:
                            for t in p.get("tools", []):
                                if t.get("name") == tname:
                                    handler_fn = core.PLUGIN_HANDLERS.get(t.get("handler"))
                                    break
                            break
                    if handler_fn is None:
                        messages.append({"role": "user", "content":
                                         f"[插件调用失败] 插件 {pname} 的工具 {tname} 不存在或已卸载，请勿再调用。"})
                        history.append(messages[-1])
                        _emit(job, "tool", title=f"插件 · {pname}/{tname}",
                              content="插件不存在或已卸载，已跳过", ok=False)
                        continue
                    try:
                        ok, out = handler_fn(content, workspace)
                    except Exception as e:
                        ok, out = False, f"(插件执行异常: {e})"
                    _emit(job, "tool", title=f"插件 · {pname}/{tname}", content=out, ok=ok)
                    result_note = (f"[插件执行结果]\n插件: {pname}\n工具: {tname}\n"
                                   f"状态: {'成功' if ok else '失败'}\n结果:\n{out}")
                    messages.append({"role": "user", "content": result_note})
                    history.append(messages[-1])
                    ran_any = True
            if not ran_any:
                break
        cfg.data["histories"][model["id"]] = history[-core.HISTORY_LIMIT:]
        cfg.save()
        # 镜像到所有模型：任何模型切换过来都有完整会话记忆
        _mirror_all(cfg, history[-core.HISTORY_LIMIT:])
        cfg.save()
        # 同步活动会话（前端无需手动回写）
        aid = cfg.data.get("active_conv")
        for c in cfg.data.setdefault("conversations", []):
            if c["id"] == aid:
                c["hist"] = history[-core.HISTORY_LIMIT:]
                c["model_id"] = model["id"]
                if c.get("title", "新对话") == "新对话":
                    for msg in history:
                        if msg.get("role") == "user":
                            raw = msg.get("content", "")
                            if isinstance(raw, list):
                                raw = next((p.get("text", "") for p in raw if isinstance(p, dict) and p.get("type") == "text"), "")
                            c["title"] = str(raw)[:20]
                            # 首条消息全文（截断 300 字）供侧边栏搜索
                            c["first"] = str(raw)[:300]
                            break
                cfg.save()
                break
    except Exception as e:
        ok_flag = False
        _emit(job, "error", text=f"对话发生错误: {e}")
        try:
            cfg.data["histories"][model["id"]] = history[-core.HISTORY_LIMIT:]
            cfg.save()
        except Exception:
            pass
    _emit(job, "done", text=last_text, ok=ok_flag)
    job.finished.set()


# ==================== HTTP 服务 ====================
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n) if n else b""
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def _auth_ok(self):
        """可选 API key 鉴权（仅当用户在设置里设了 key 时生效）。"""
        key = self._cfg().data["settings"].get("api_key", "") or ""
        if not key:
            return True
        return self.headers.get("X-API-Key", "") == key

    def _cfg(self):
        return core.Config()

    # ---- GET ----
    def do_GET(self):
        p = urlparse(self.path)
        if p.path not in ("/api/ping", "/api/stream") and not self._auth_ok():
            self._json(401, {"error": "unauthorized"})
            return
        if p.path == "/api/ping":
            self._json(200, {"ok": True, "version": "1.1.0"})
            return
        if p.path == "/api/shutdown":
            # 前端关闭时调用：退出进程
            self._json(200, {"ok": True})
            def _later():
                import time, os
                time.sleep(0.3)
                os._exit(0)
            threading.Thread(target=_later, daemon=True).start()
            return
        if p.path == "/api/config":
            self._json(200, self._cfg().data)
            return
        if p.path == "/api/websearch":
            qs = parse_qs(p.query)
            q = qs.get("q", [""])[0]
            if not q.strip():
                self._json(200, {"results": [], "engine": "none"})
                return
            results, engine = websearch.search(q, self._cfg().data.get("settings"))
            self._json(200, {"results": results, "engine": engine})
            return
        if p.path == "/api/container/detect":
            self._json(200, websearch.detect_container())
            return
        if p.path == "/api/plugins":
            self._json(200, {"plugins": core.load_plugins()})
            return
        if p.path == "/api/stream":
            qs = parse_qs(p.query)
            job_id = qs.get("job", [""])[0]
            with JOBS_LOCK:
                job = JOBS.get(job_id)
            if not job:
                self._json(404, {"error": "job not found"})
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                while not (job.finished.is_set() and job.q.empty()):
                    try:
                        ev = job.q.get(timeout=0.5)
                    except queue.Empty:
                        continue
                    line = json.dumps(ev, ensure_ascii=False)
                    self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                    self.wfile.flush()
                # 正常结束：发送 [DONE]，前端据此判定完成，不再重连
                try:
                    self.wfile.write(b"data: [DONE]\n\n")
                    self.wfile.flush()
                except Exception:
                    pass
            except Exception:
                # 传输中断（客户端断线）：job 保留，允许前端短时重连续读
                pass
            finally:
                # 延迟 30 秒删除 job：正常结束/断线重连场景都兜底清理，避免内存泄漏
                def _delayed_pop():
                    import time
                    time.sleep(30)
                    with JOBS_LOCK:
                        JOBS.pop(job.id, None)
                threading.Thread(target=_delayed_pop, daemon=True).start()
            return
        self._json(404, {"error": "not found"})

    # ---- POST ----
    def do_POST(self):
        p = urlparse(self.path)
        if not self._auth_ok():
            self._json(401, {"error": "unauthorized"})
            return
        data = self._body()
        if p.path == "/api/config":
            cfg = self._cfg()
            for k in ("providers", "models"):
                if isinstance(data.get(k), list):
                    cfg.data[k] = data[k]
            if isinstance(data.get("settings"), dict):
                cfg.data["settings"].update(data["settings"])
            for k in ("conversations", "active_conv", "histories"):
                if k in data:
                    cfg.data[k] = data[k]
            cfg.save()
            self._json(200, {"ok": True})
            return
        if p.path == "/api/provider/delete":
            cfg = self._cfg()
            pid = data.get("provider_id")
            cfg.data["providers"] = [p for p in cfg.data.get("providers", []) if p.get("id") != pid]
            cfg.data["models"] = [m for m in cfg.data.get("models", []) if m.get("provider_id") != pid]
            cfg.save()
            self._json(200, {"ok": True})
            return
        if p.path == "/api/convo/new":
            cfg = self._cfg()
            mid = data.get("model_id")
            convs = cfg.data.setdefault("conversations", [])
            cid = uuid.uuid4().hex[:8]
            convs.insert(0, {"id": cid, "title": "新对话", "created": time.time(),
                             "hist": [], "model_id": mid})
            cfg.data["active_conv"] = cid
            _mirror_all(cfg, [])
            cfg.save()
            self._json(200, {"conv_id": cid})
            return
        if p.path == "/api/convo/load":
            cfg = self._cfg()
            conv_id = data.get("conv_id")
            convs = cfg.data.setdefault("conversations", [])
            for c in convs:
                if c["id"] == conv_id:
                    cfg.data["active_conv"] = conv_id
                    _mirror_all(cfg, c.get("hist", []))
                    cfg.save()
                    self._json(200, {"model_id": c.get("model_id"), "hist": c.get("hist", [])})
                    return
            self._json(404, {"error": "conversation not found"})
            return
        if p.path == "/api/convo/clear":
            cfg = self._cfg()
            conv_id = data.get("conv_id")
            if not conv_id:
                self._json(200, {"ok": False, "error": "缺少 conv_id"})
                return
            for c in cfg.data.setdefault("conversations", []):
                if c["id"] == conv_id:
                    c["hist"] = []
                    if cfg.data.get("active_conv") == conv_id:
                        _mirror_all(cfg, [])
                    cfg.save()
                    self._json(200, {"ok": True})
                    return
            self._json(200, {"ok": False, "error": "conversation not found"})
            return
        if p.path == "/api/convo/model":
            cfg = self._cfg()
            conv_id = data.get("conv_id")
            mid = data.get("model_id")
            if not conv_id or not mid:
                self._json(200, {"ok": False, "error": "缺少参数"})
                return
            for c in cfg.data.setdefault("conversations", []):
                if c["id"] == conv_id:
                    c["model_id"] = mid
                    cfg.save()
                    self._json(200, {"ok": True})
                    return
            self._json(200, {"ok": False, "error": "conversation not found"})
            return
        if p.path == "/api/convo/rename":
            cfg = self._cfg()
            conv_id = data.get("conv_id")
            title = (data.get("title") or "").strip()[:60]
            if not conv_id or not title:
                self._json(200, {"ok": False, "error": "缺少 conv_id 或 title"})
                return
            for c in cfg.data.setdefault("conversations", []):
                if c["id"] == conv_id:
                    c["title"] = title
                    cfg.save()
                    self._json(200, {"ok": True})
                    return
            self._json(200, {"ok": False, "error": "conversation not found"})
            return
        if p.path == "/api/convo/delete":
            cfg = self._cfg()
            conv_id = data.get("conv_id")
            convs = cfg.data.setdefault("conversations", [])
            cfg.data["conversations"] = [c for c in convs if c["id"] != conv_id]
            if cfg.data.get("active_conv") == conv_id:
                cfg.data["active_conv"] = None
                _mirror_all(cfg, [])
            cfg.save()
            self._json(200, {"ok": True})
            return
        if p.path == "/api/chat":
            cfg = self._cfg()
            model = cfg.model(data.get("model_id", ""))
            if not model:
                self._json(400, {"error": "model not found"})
                return
            job = Job(cfg, model, data.get("text", ""))
            wrs = data.get("web_results")
            if isinstance(wrs, list):
                job.web_results = wrs
            imgs = data.get("images")
            if isinstance(imgs, list):
                job.images = imgs
            with JOBS_LOCK:
                JOBS[job.id] = job
            threading.Thread(target=stream_agent, args=(job,), daemon=True).start()
            self._json(200, {"job": job.id})
            return
        if p.path == "/api/chat/stop":
            job_id = data.get("job")
            with JOBS_LOCK:
                job = JOBS.get(job_id)
            if job:
                job.stop.set()
                _emit(job, "state", text="正在停止…")
            self._json(200, {"ok": True})
            return
        if p.path == "/api/decision":
            job_id = data.get("job")
            with JOBS_LOCK:
                job = JOBS.get(job_id)
            if job:
                job.decision_allow = bool(data.get("allow"))
                job.decision_evt.set()
            self._json(200, {"ok": True})
            return
        if p.path == "/api/provider/fetch":
            cfg = self._cfg()
            prov = cfg.provider(data.get("provider_id", ""))
            if not prov:
                self._json(400, {"error": "provider not found"})
                return
            try:
                timeout = max(10, int(cfg.data["settings"].get("connect_timeout", 15)) + 15)
                models = core.fetch_models(prov, timeout=timeout)
                self._json(200, {"models": models})
            except Exception as e:
                self._json(200, {"models": [], "error": core._friendly_error(e)})
            return
        if p.path == "/api/plugin/import":
            cfg = self._cfg()
            path = data.get("path")
            content = data.get("content")
            try:
                if content:
                    parsed = json.loads(content)
                    ok_v, err_v = core.validate_plugin(parsed)
                    if not ok_v:
                        self._json(200, {"ok": False, "error": err_v})
                        return
                    fname = parsed.get("id", uuid.uuid4().hex[:8]) + ".json"
                    with open(os.path.join(core.plugins_dir(), fname), "w", encoding="utf-8") as f:
                        json.dump(parsed, f, ensure_ascii=False, indent=2)
                elif path:
                    if not os.path.exists(path):
                        self._json(200, {"ok": False, "error": "文件不存在"})
                        return
                    with open(path, "r", encoding="utf-8") as f:
                        parsed = json.load(f)
                    ok_v, err_v = core.validate_plugin(parsed)
                    if not ok_v:
                        self._json(200, {"ok": False, "error": err_v})
                        return
                    fname = parsed.get("id", uuid.uuid4().hex[:8]) + ".json"
                    import shutil
                    shutil.copy(path, os.path.join(core.plugins_dir(), fname))
                else:
                    self._json(200, {"ok": False, "error": "缺少 path 或 content"})
                    return
                self._json(200, {"ok": True})
            except Exception as e:
                self._json(200, {"ok": False, "error": f"导入失败: {e}"})
            return
        if p.path == "/api/plugin/delete":
            pid = data.get("id")
            target = None
            for pname in ("id", "name"):
                v = data.get(pname)
                if v:
                    target = v
                    break
            if not target:
                self._json(200, {"ok": False, "error": "缺少插件 id"})
                return
            removed = False
            for fn in os.listdir(core.plugins_dir()):
                if not fn.endswith(".json"):
                    continue
                fp = os.path.join(core.plugins_dir(), fn)
                try:
                    with open(fp, "r", encoding="utf-8") as f:
                        pl = json.load(f)
                except Exception:
                    continue
                if pl.get("id") == target or pl.get("name") == target:
                    os.remove(fp)
                    removed = True
            self._json(200, {"ok": removed})
            return
        if p.path == "/api/plugin/toggle":
            cfg = self._cfg()
            name = data.get("name")
            tool = data.get("tool")
            enabled = bool(data.get("enabled"))
            dis = set(cfg.data["settings"].get("disabled_tools", []))
            key = f"{name}::{tool}"
            if enabled:
                dis.discard(key)
            else:
                dis.add(key)
            cfg.data["settings"]["disabled_tools"] = sorted(dis)
            cfg.save()
            self._json(200, {"ok": True})
            return
        self._json(404, {"error": "not found"})


def main():
    core.ensure_default_plugins()
    cfg = core.Config()
    host = cfg.data["settings"].get("bind_host", "127.0.0.1") or "127.0.0.1"

    try:
        server = ThreadingHTTPServer((host, PORT), Handler)
    except OSError as e:
        print(f"port {PORT} unavailable: {e}")
        return
    print(f"darling-ai bridge listening on http://{host}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
