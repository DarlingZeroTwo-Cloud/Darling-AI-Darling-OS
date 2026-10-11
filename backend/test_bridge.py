# -*- coding: utf-8 -*-
"""桥接服务端到端测试：ping → config → chat → SSE 流 → decision。"""
import json
import os
import sys
import threading
import time
import urllib.request
import urllib.error

os.environ["AI_CONSOLE_CONFIG"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "it_config.json")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ai_console as core
import bridge_server as b

# 准备测试配置（fake provider 指向本地假 API）
core.ensure_default_plugins()
cfg = core.Config()
cfg.data["providers"] = [{"id": "fake", "name": "Fake", "base_url": "http://127.0.0.1:8765/v1", "api_key": "", "full_endpoint": False}]
cfg.data["models"] = [{"id": "m1", "provider_id": "fake", "name": "fake-model-1", "display": "Fake - fake-model-1"}]
cfg.data["conversations"] = [{"id": "c1", "title": "测试会话", "hist": [], "model_id": "m1"}]
cfg.data["active_conv"] = "c1"
cfg.data["settings"]["access_mode"] = "on_demand"
cfg.data["settings"]["use_proxy"] = False
cfg.save()

results = []


def http_json(path, method="GET", body=None):
    url = f"http://127.0.0.1:19730{path}"
    req = urllib.request.Request(url, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(body).encode("utf-8")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def sse_read(job_id):
    url = f"http://127.0.0.1:19730/api/stream?job={job_id}"
    req = urllib.request.Request(url)
    events = []
    with urllib.request.urlopen(req, timeout=60) as r:
        buf = ""
        while True:
            line = r.readline()
            if not line:
                break
            s = line.decode("utf-8").strip()
            if s.startswith("data: "):
                events.append(json.loads(s[6:]))
            if s == "data: [DONE]":
                break
    return events


server = b.ThreadingHTTPServer((b.HOST, b.PORT), b.Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
time.sleep(0.3)

try:
    # 1. ping
    r = http_json("/api/ping")
    results.append(("ping", r.get("ok") is True))

    # 2. config
    r = http_json("/api/config")
    results.append(("config has models", len(r.get("models", [])) == 1))

    # 3. chat + SSE（假 API 首轮回 [[SEARCH]] 今日新闻[[/SEARCH]]，触发插件第二轮）
    r = http_json("/api/chat", "POST", {"model_id": "m1", "text": "查一下今天的新闻"})
    job = r.get("job")
    results.append(("chat started", bool(job)))
    events = sse_read(job)
    types = [e["type"] for e in events]
    print("event types:", types)
    results.append(("has state", "state" in types))
    results.append(("has token", "token" in types))
    results.append(("has tool", "tool" in types))
    results.append(("has done", "done" in types))

    # 4. 对话后活动会话历史已同步（含用户消息 + 工具结果 + 回复）
    cfg2 = core.Config()
    conv = next(c for c in cfg2.data["conversations"] if c["id"] == "c1")
    hists = conv.get("hist", [])
    results.append(("conversation hist synced", len(hists) >= 3))
    results.append(("title preserved", conv.get("title") == "测试会话"))

    # 5. 配置保存
    r = http_json("/api/config", "POST", {"settings": {"max_tokens": 999}})
    cfg3 = core.Config()
    results.append(("config save", cfg3.data["settings"].get("max_tokens") == 999))

    # 6. 插件列表
    r = http_json("/api/plugins")
    results.append(("plugins listed", len(r) >= 2))

    # 7. 插件导入（content 方式）
    r = http_json("/api/plugin/import", "POST", {"content": json.dumps({
        "id": "test-plugin", "name": "测试插件", "version": "1.0.0",
        "description": "test", "author": "t",
        "tools": [{"name": "echo", "handler": "fetch_page", "description": "e",
                   "example": "e", "pattern": "测试用", "close": "[[/END]]"}]})})
    results.append(("plugin import", r.get("ok") is True))

    # 8. 插件删除
    r = http_json("/api/plugin/delete", "POST", {"id": "test-plugin"})
    results.append(("plugin delete", r.get("ok") is True))

    # 9. decision（无真实 ask 触发，但 API 应正常响应）
    r = http_json("/api/decision", "POST", {"job": job, "allow": True})
    results.append(("decision ok", r.get("ok") is True))

    # 10. 新建会话：镜像空历史，active 切换
    r = http_json("/api/convo/new", "POST", {"model_id": "m1"})
    cid = r.get("conv_id")
    results.append(("convo new", bool(cid)))
    cfg4 = core.Config()
    results.append(("convo new active", cfg4.data.get("active_conv") == cid))
    results.append(("convo new mirrored empty", len(cfg4.data["histories"].get("m1", [])) == 0))

    # 11. 载入旧会话：历史恢复 + 镜像
    r = http_json("/api/convo/load", "POST", {"conv_id": "c1"})
    results.append(("convo load", len(r.get("hist", [])) >= 3 and r.get("model_id") == "m1"))
    cfg5 = core.Config()
    results.append(("convo load mirrored", len(cfg5.data["histories"].get("m1", [])) >= 3))

    # 12. 删除会话
    r = http_json("/api/convo/delete", "POST", {"conv_id": cid})
    cfg6 = core.Config()
    results.append(("convo delete", r.get("ok") is True and all(c["id"] != cid for c in cfg6.data["conversations"])))

finally:
    server.shutdown()

allok = all(r[1] for r in results)
for name, ok in results:
    print(("PASS" if ok else "FAIL"), name)
print("RESULT:", "ALL PASS" if allok else "FAIL")
