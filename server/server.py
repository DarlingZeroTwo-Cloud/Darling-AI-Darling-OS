# -*- coding: utf-8 -*-
"""darling-ai-server HTTP API。

同时监听 IPv4 (0.0.0.0:611) 与 IPv6 ([::]:611)。
所有用户接口走 Bearer token 鉴权。
管理接口只监听 127.0.0.1（GUI 本机用）。
"""
import json
import time
import threading
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import db
import config


# ---------------- 上游转发 ----------------
def upstream_text_chat(provider, upstream_model, system_prompt, messages):
    """OpenAI 兼容 chat/completions 转发。返回 (status, headers_iter, body_text)。
    简化版：非流式，直接返回完整响应。"""
    url = provider["base_url"].rstrip("/") + "/chat/completions"
    payload = {
        "model": upstream_model,
        "messages": ([
            {"role": "system", "content": system_prompt}
        ] if system_prompt else []) + messages,
        "stream": False,
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {provider['api_key']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.loads(r.read().decode())
            content = data["choices"][0]["message"]["content"]
            usage = data.get("usage", {})
            return {"ok": True, "content": content, "usage": usage}
    except urllib.error.HTTPError as e:
        try:
            err = e.read().decode()
        except Exception:
            err = str(e)
        return {"ok": False, "error": f"上游 {e.code}: {err[:300]}"}
    except Exception as e:
        return {"ok": False, "error": str(e)[:300]}


def upstream_image(provider, upstream_model, prompt, size="1024x1024"):
    url = provider["base_url"].rstrip("/") + "/images/generations"
    payload = {"model": upstream_model, "prompt": prompt, "n": 1, "size": size}
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {provider['api_key']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            data = json.loads(r.read().decode())
            return {"ok": True, "data": data.get("data", [])}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"上游 {e.code}: {e.read().decode()[:300]}"}
    except Exception as e:
        return {"ok": False, "error": str(e)[:300]}


# ---------------- HTTP Handler ----------------
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a, **kw):
        pass

    def _send(self, code, obj, extra_headers=None):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", config.CORS_ORIGIN)
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        try:
            return json.loads(raw)
        except Exception:
            return {}

    def _auth_user(self):
        h = self.headers.get("Authorization", "")
        if not h.startswith("Bearer "):
            return None
        return db.get_user_by_token(h[7:].strip())

    def do_OPTIONS(self):
        self._send(204, {})

    # ---------------- 路由分发 ----------------
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/me":
            u = self._auth_user()
            if not u:
                return self._send(401, {"error": "未登录"})
            q = db.get_quota(u["id"])
            return self._send(200, {
                "id": u["id"], "email": u["email"],
                "quota": {
                    "window_start": q["window_start"],
                    "window_end": q["window_end"],
                    "used": q["used"],
                    "limit": config.FREE_LIMITS,
                },
            })
        if path == "/api/models":
            u = self._auth_user()
            if not u:
                return self._send(401, {"error": "未登录"})
            models = db.list_models(enabled_only=True)
            out = []
            for m in models:
                out.append({
                    "id": f"darling-{m['id']}",
                    "name": m["name"],
                    "description": m["description"],
                    "type": m["type"],
                })
            return self._send(200, {"models": out})
        if path == "/api/health":
            return self._send(200, {"ok": True, "ts": int(time.time())})
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._read_json()

        if path == "/api/register":
            email = (body.get("email") or "").strip().lower()
            pw = body.get("password") or ""
            if "@" not in email or len(pw) < 6:
                return self._send(400, {"error": "邮箱格式不对或密码少于 6 位"})
            if db.get_user_by_email(email):
                return self._send(409, {"error": "邮箱已注册"})
            uid = db.create_user(email, pw)
            tok = db.create_token(uid, config.TOKEN_TTL)
            return self._send(200, {"token": tok, "email": email})

        if path == "/api/login":
            email = (body.get("email") or "").strip().lower()
            pw = body.get("password") or ""
            u = db.get_user_by_email(email)
            if not u:
                return self._send(401, {"error": "邮箱或密码错误"})
            if not db.verify_password(pw, u["password_hash"], u["salt"]):
                return self._send(401, {"error": "邮箱或密码错误"})
            if u["status"] != "active":
                return self._send(403, {"error": "账号被禁用"})
            tok = db.create_token(u["id"], config.TOKEN_TTL)
            return self._send(200, {"token": tok, "email": email})

        if path == "/api/logout":
            h = self.headers.get("Authorization", "")
            if h.startswith("Bearer "):
                db.revoke_token(h[7:].strip())
            return self._send(200, {"ok": True})

        if path == "/api/chat":
            u = self._auth_user()
            if not u:
                return self._send(401, {"error": "未登录"})
            model_id_raw = body.get("model_id") or ""
            # 客户端传 "darling-3" 形式
            try:
                mid = int(model_id_raw.replace("darling-", ""))
            except Exception:
                return self._send(400, {"error": "模型 ID 错误"})
            m = db.get_model(mid)
            if not m or not m["enabled"]:
                return self._send(404, {"error": "模型不存在"})
            if m["type"] not in ("text", "hybrid"):
                return self._send(400, {"error": "该模型不是文本类型"})
            provider = db.get_provider(m["provider_id"])
            if not provider:
                return self._send(500, {"error": "上游未配置"})
            messages = body.get("messages") or []
            result = upstream_text_chat(provider, m["upstream_model"], m["system_prompt"], messages)
            if not result.get("ok"):
                return self._send(502, {"error": result.get("error", "上游失败")})
            used_tokens = result.get("usage", {}).get("total_tokens", 100)
            if not db.consume_quota(u["id"], text_tokens=used_tokens):
                return self._send(429, {"error": "5 小时文本额度已用完"})
            return self._send(200, {
                "content": result["content"],
                "usage": result.get("usage", {}),
            })

        if path == "/api/images/generations":
            u = self._auth_user()
            if not u:
                return self._send(401, {"error": "未登录"})
            model_id_raw = body.get("model_id") or ""
            try:
                mid = int(model_id_raw.replace("darling-", ""))
            except Exception:
                return self._send(400, {"error": "模型 ID 错误"})
            m = db.get_model(mid)
            if not m or not m["enabled"]:
                return self._send(404, {"error": "模型不存在"})
            if m["type"] not in ("image", "hybrid"):
                return self._send(400, {"error": "该模型不是图片类型"})
            if not db.consume_quota(u["id"], images=1):
                return self._send(429, {"error": "5 小时图片额度已用完"})
            provider = db.get_provider(m["provider_id"])
            result = upstream_image(provider, m["upstream_model"], body.get("prompt", ""))
            if not result.get("ok"):
                # 失败退还额度
                db.consume_quota(u["id"], images=-1)
                return self._send(502, {"error": result.get("error")})
            return self._send(200, {"data": result["data"]})

        return self._send(404, {"error": "not found"})


# ---------------- 启动 ----------------
def start_server():
    db.init_db()
    srv_v4 = ThreadingHTTPServer((config.HOST_V4, config.PORT), Handler)
    t4 = threading.Thread(target=srv_v4.serve_forever, daemon=True)
    t4.start()
    print(f"[darling-server] IPv4 listening on {config.HOST_V4}:{config.PORT}")
    if getattr(config, "ENABLE_V6", False):
        try:
            srv_v6 = ThreadingHTTPServer((config.HOST_V6, config.PORT), Handler)
            t6 = threading.Thread(target=srv_v6.serve_forever, daemon=True)
            t6.start()
            print(f"[darling-server] IPv6 listening on [{config.HOST_V6}]:{config.PORT}")
        except Exception as e:
            print(f"[darling-server] IPv6 bind failed (继续仅 IPv4): {e}")
    else:
        print("[darling-server] IPv6 未启用（config.ENABLE_V6=False）")
    return srv_v4


if __name__ == "__main__":
    start_server()
    print("[darling-server] running. Ctrl+C to stop.")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
