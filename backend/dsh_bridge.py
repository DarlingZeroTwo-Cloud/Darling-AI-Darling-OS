# -*- coding: utf-8 -*-
"""DeepSeek Harness 本地内核管理（v5.0）。

负责启动/停止/健康检查本地 dsh 服务（Node.js 运行时 + @deepseek-ai/dsh），
并向 Flutter 客户端暴露启动后的一键控制台地址（系统浏览器打开，带 token）。

运行时目录约定（打包后）：
  <应用根>/runtime/node/...    （Node.js 运行时，Windows 为 node.exe）
  <应用根>/runtime/dsh/...     （npm install @deepseek-ai/dsh 后的依赖树）
  DSH_HOME 用户数据默认：~/.config/darling-ai/dsh-home（Windows: %APPDATA%/DarlingAI/dsh-home）
"""
import os
import re
import socket
import subprocess
import threading

DSH_PORT = 3080


class DshBridge:
    def __init__(self):
        self.proc = None
        self.token = None
        self.home_dir = None
        self.lock = threading.Lock()

    # ---------- 路径解析 ----------
    def _find_runtime(self):
        root = os.environ.get("DARLING_RUNTIME_DIR", "")
        if root and os.path.isdir(root):
            return root
        here = os.path.dirname(os.path.abspath(__file__))
        for cand in (
            os.path.join(here, "..", "runtime"),
            os.path.join(here, "..", "v5-runtime"),
        ):
            p = os.path.abspath(cand)
            if os.path.isdir(p):
                return p
        return None

    def _node_path(self, runtime):
        if os.name == "nt":
            p = os.path.join(runtime, "node", "node.exe")
        else:
            p = os.path.join(runtime, "node", "bin", "node")
        return p if os.path.isfile(p) else None

    def _dsh_entry(self, runtime):
        p = os.path.join(runtime, "dsh", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js")
        return p if os.path.isfile(p) else None

    # ---------- 状态 ----------
    def _port_ok(self):
        try:
            s = socket.create_connection(("127.0.0.1", DSH_PORT), timeout=2)
            s.close()
            return True
        except OSError:
            return False

    def status(self):
        alive = self.proc is not None and self.proc.poll() is None
        running = alive and self._port_ok()
        url = ""
        if self.token:
            url = f"http://127.0.0.1:{DSH_PORT}/?token={self.token}"
        return {"running": running, "port": DSH_PORT, "token": self.token or "", "url": url}

    # ---------- 启动 ----------
    def start(self):
        with self.lock:
            st = self.status()
            if st["running"]:
                return {"ok": True, **st}
            runtime = self._find_runtime()
            if not runtime:
                return {"ok": False, "error": "未找到 Harness 运行时（runtime/ 目录缺失）"}
            node = self._node_path(runtime)
            entry = self._dsh_entry(runtime)
            if not node or not entry:
                return {"ok": False, "error": "Harness 运行时缺少 node 或 dsh 组件"}
            home = self.home_dir
            if not home:
                if os.name == "nt":
                    home = os.path.join(
                        os.environ.get("APPDATA", os.path.expanduser("~")), "DarlingAI", "dsh-home"
                    )
                else:
                    home = os.path.join(os.path.expanduser("~"), ".config", "darling-ai", "dsh-home")
            os.makedirs(home, exist_ok=True)
            env = dict(os.environ)
            env["DSH_HOME"] = home
            self.proc = subprocess.Popen(
                [node, entry, "web", "--port", str(DSH_PORT), "--no-open"],
                cwd=os.path.dirname(entry) or runtime,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            self.token = None

            def _reader():
                try:
                    for line in self.proc.stdout:
                        m = re.search(r"token=([A-Za-z0-9_\-]+)", line)
                        if m and not self.token:
                            self.token = m.group(1)
                except Exception:
                    pass

            threading.Thread(target=_reader, daemon=True).start()
            for _ in range(60):
                time_sleep(1)
                if self._port_ok():
                    break
            if not self._port_ok():
                return {"ok": False, "error": "Harness 启动超时（请查看应用日志）"}
            # 端口就绪后再等 token（控制台地址需要它）
            for _ in range(20):
                if self.token:
                    break
                time_sleep(0.5)
            return {"ok": True, **self.status()}

    # ---------- 停止 ----------
    def stop(self):
        with self.lock:
            if self.proc is not None and self.proc.poll() is None:
                try:
                    self.proc.terminate()
                    self.proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    try:
                        self.proc.kill()
                    except Exception:
                        pass
            self.proc = None
            self.token = None
            return {"ok": True, "running": False}


def time_sleep(sec):
    import time
    time.sleep(sec)


dsh_bridge = DshBridge()


# 模块级转发（供 bridge_server 直接 import 后调用，避免与实例名混淆）
def status():
    return dsh_bridge.status()


def start():
    return dsh_bridge.start()


def stop():
    return dsh_bridge.stop()
