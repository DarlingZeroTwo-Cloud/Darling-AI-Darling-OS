# -*- coding: utf-8 -*-
"""darling-ai-server SQLite 数据层。"""
import os
import sqlite3
import time
import hashlib
import secrets

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "darling_server.db")


def _conn():
    c = sqlite3.connect(DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys = ON")
    return c


def init_db():
    c = _conn()
    c.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            note TEXT DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS tokens (
            token TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS providers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            base_url TEXT NOT NULL,
            api_key TEXT NOT NULL,
            type TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS models (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            provider_id INTEGER NOT NULL,
            upstream_model TEXT NOT NULL,
            type TEXT NOT NULL,
            system_prompt TEXT DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(provider_id) REFERENCES providers(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS quota_windows (
            user_id INTEGER NOT NULL,
            window_start INTEGER NOT NULL,
            text_tokens INTEGER NOT NULL DEFAULT 0,
            images INTEGER NOT NULL DEFAULT 0,
            videos INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(user_id, window_start)
        );

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    )
    c.commit()
    c.close()


# ---------- 密码 ----------
def hash_password(password: str, salt: str = None) -> tuple:
    if salt is None:
        salt = secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 200_000)
    return h.hex(), salt


def verify_password(password: str, password_hash: str, salt: str) -> bool:
    h, _ = hash_password(password, salt)
    return h == password_hash


# ---------- 用户 ----------
def create_user(email: str, password: str) -> int:
    pw_hash, salt = hash_password(password)
    c = _conn()
    cur = c.execute(
        "INSERT INTO users(email, password_hash, salt, created_at) VALUES(?,?,?,?)",
        (email, pw_hash, salt, int(time.time())),
    )
    c.commit()
    uid = cur.lastrowid
    c.close()
    return uid


def get_user_by_email(email: str):
    c = _conn()
    r = c.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
    c.close()
    return dict(r) if r else None


def get_user(uid: int):
    c = _conn()
    r = c.execute("SELECT id,email,created_at,status,note FROM users WHERE id=?", (uid,)).fetchone()
    c.close()
    return dict(r) if r else None


def list_users():
    c = _conn()
    rows = c.execute("SELECT id,email,created_at,status,note FROM users ORDER BY id DESC").fetchall()
    c.close()
    return [dict(r) for r in rows]


def set_user_status(uid: int, status: str):
    c = _conn()
    c.execute("UPDATE users SET status=? WHERE id=?", (status, uid))
    c.commit()
    c.close()


def delete_user(uid: int):
    c = _conn()
    c.execute("DELETE FROM users WHERE id=?", (uid,))
    c.commit()
    c.close()


# ---------- Token ----------
def create_token(uid: int, ttl: int = 30 * 86400) -> str:
    tok = secrets.token_urlsafe(32)
    now = int(time.time())
    c = _conn()
    c.execute(
        "INSERT INTO tokens(token, user_id, created_at, expires_at) VALUES(?,?,?,?)",
        (tok, uid, now, now + ttl),
    )
    c.commit()
    c.close()
    return tok


def get_user_by_token(token: str):
    c = _conn()
    r = c.execute(
        "SELECT u.id, u.email, u.status, t.expires_at FROM tokens t JOIN users u ON u.id=t.user_id WHERE t.token=?",
        (token,),
    ).fetchone()
    c.close()
    if not r:
        return None
    if r["expires_at"] < int(time.time()):
        return None
    if r["status"] != "active":
        return None
    return dict(r)


def revoke_token(token: str):
    c = _conn()
    c.execute("DELETE FROM tokens WHERE token=?", (token,))
    c.commit()
    c.close()


# ---------- Providers ----------
def list_providers():
    c = _conn()
    rows = c.execute("SELECT * FROM providers ORDER BY id DESC").fetchall()
    c.close()
    return [dict(r) for r in rows]


def add_provider(name, base_url, api_key, ptype):
    c = _conn()
    cur = c.execute(
        "INSERT INTO providers(name, base_url, api_key, type, created_at) VALUES(?,?,?,?,?)",
        (name, base_url, api_key, ptype, int(time.time())),
    )
    c.commit()
    pid = cur.lastrowid
    c.close()
    return pid


def update_provider(pid, **kw):
    allowed = {"name", "base_url", "api_key", "type"}
    sets = [f"{k}=?" for k in kw if k in allowed]
    if not sets:
        return
    args = [kw[k] for k in kw if k in allowed] + [pid]
    c = _conn()
    c.execute(f"UPDATE providers SET {','.join(sets)} WHERE id=?", args)
    c.commit()
    c.close()


def delete_provider(pid):
    c = _conn()
    c.execute("DELETE FROM providers WHERE id=?", (pid,))
    c.commit()
    c.close()


def get_provider(pid):
    c = _conn()
    r = c.execute("SELECT * FROM providers WHERE id=?", (pid,)).fetchone()
    c.close()
    return dict(r) if r else None


# ---------- Models ----------
def list_models(enabled_only=False):
    c = _conn()
    if enabled_only:
        rows = c.execute("SELECT * FROM models WHERE enabled=1 ORDER BY sort_order, id").fetchall()
    else:
        rows = c.execute("SELECT * FROM models ORDER BY sort_order, id").fetchall()
    c.close()
    return [dict(r) for r in rows]


def add_model(name, description, provider_id, upstream_model, mtype, system_prompt="", sort_order=0):
    c = _conn()
    cur = c.execute(
        "INSERT INTO models(name, description, provider_id, upstream_model, type, system_prompt, sort_order, created_at) VALUES(?,?,?,?,?,?,?,?)",
        (name, description, provider_id, upstream_model, mtype, system_prompt, sort_order, int(time.time())),
    )
    c.commit()
    mid = cur.lastrowid
    c.close()
    return mid


def update_model(mid, **kw):
    allowed = {"name", "description", "provider_id", "upstream_model", "type", "system_prompt", "enabled", "sort_order"}
    sets = [f"{k}=?" for k in kw if k in allowed]
    if not sets:
        return
    args = [kw[k] for k in kw if k in allowed] + [mid]
    c = _conn()
    c.execute(f"UPDATE models SET {','.join(sets)} WHERE id=?", args)
    c.commit()
    c.close()


def delete_model(mid):
    c = _conn()
    c.execute("DELETE FROM models WHERE id=?", (mid,))
    c.commit()
    c.close()


def get_model(mid):
    c = _conn()
    r = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    c.close()
    return dict(r) if r else None


# ---------- 额度窗口（5 小时一个周期） ----------
WINDOW = 5 * 3600


def _current_window_start():
    now = int(time.time())
    return (now // WINDOW) * WINDOW


def get_quota(uid: int):
    """返回当前窗口的已用量 + 窗口起始。"""
    ws = _current_window_start()
    c = _conn()
    r = c.execute(
        "SELECT text_tokens, images, videos FROM quota_windows WHERE user_id=? AND window_start=?",
        (uid, ws),
    ).fetchone()
    c.close()
    used = dict(r) if r else {"text_tokens": 0, "images": 0, "videos": 0}
    return {
        "window_start": ws,
        "window_end": ws + WINDOW,
        "used": used,
    }


def consume_quota(uid: int, text_tokens: int = 0, images: int = 0, videos: int = 0) -> bool:
    """扣额度，余额足够返回 True，否则 False。"""
    from config import FREE_LIMITS
    ws = _current_window_start()
    c = _conn()
    r = c.execute(
        "SELECT text_tokens, images, videos FROM quota_windows WHERE user_id=? AND window_start=?",
        (uid, ws),
    ).fetchone()
    used = dict(r) if r else {"text_tokens": 0, "images": 0, "videos": 0}
    if used["text_tokens"] + text_tokens > FREE_LIMITS["text_tokens"]:
        c.close()
        return False
    if used["images"] + images > FREE_LIMITS["images"]:
        c.close()
        return False
    if used["videos"] + videos > FREE_LIMITS["videos"]:
        c.close()
        return False
    c.execute(
        """INSERT INTO quota_windows(user_id, window_start, text_tokens, images, videos)
           VALUES(?,?,?,?,?)
           ON CONFLICT(user_id, window_start) DO UPDATE SET
             text_tokens=text_tokens+?, images=images+?, videos=videos+?""",
        (uid, ws, text_tokens, images, videos, text_tokens, images, videos),
    )
    c.commit()
    c.close()
    return True


# ---------- 设置 ----------
def get_setting(key: str, default: str = ""):
    c = _conn()
    r = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    c.close()
    return r["value"] if r else default


def set_setting(key: str, value: str):
    c = _conn()
    c.execute(
        "INSERT INTO settings(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=?",
        (key, value, value),
    )
    c.commit()
    c.close()
