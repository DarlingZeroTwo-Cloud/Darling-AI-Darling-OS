# -*- coding: utf-8 -*-
"""darling-ai-server GUI 管理面板（tkinter，零依赖）。"""
import json
import threading
import tkinter as tk
from tkinter import ttk, messagebox

import db
import config
import server


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("darling-ai-server 管理面板")
        self.geometry("1024x680")
        self.srv_handle = None
        self._build_ui()
        self.refresh_all()

    # ---------- UI ----------
    def _build_ui(self):
        # 顶部状态条
        top = ttk.Frame(self, padding=(10, 6))
        top.pack(fill=tk.X)
        self.lbl_status = ttk.Label(top, text="● 服务未启动", foreground="#c0392b", font=("", 11, "bold"))
        self.lbl_status.pack(side=tk.LEFT)
        self.btn_start = ttk.Button(top, text="启动服务", command=self.on_toggle)
        self.btn_start.pack(side=tk.RIGHT)
        ttk.Label(top, text=f"端口：{config.PORT}（IPv4+IPv6）  ").pack(side=tk.RIGHT)

        # 主区域：左侧导航 + 右侧内容
        main = ttk.Frame(self, padding=6)
        main.pack(fill=tk.BOTH, expand=True)

        nav = ttk.Frame(main, width=140)
        nav.pack(side=tk.LEFT, fill=tk.Y)
        self.pages = {}
        for key, label in [
            ("dash", "仪表盘"),
            ("users", "用户管理"),
            ("providers", "上游提供商"),
            ("models", "对外模型"),
            ("settings", "额度设置"),
        ]:
            btn = ttk.Button(nav, text=label, width=14,
                             command=lambda k=key: self.show(k))
            btn.pack(pady=2, fill=tk.X)
            self.pages[key] = btn

        self.content = ttk.Frame(main, padding=8)
        self.content.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.build_dash()
        self.build_users()
        self.build_providers()
        self.build_models()
        self.build_settings()
        self.show("dash")
        # 启动 GUI 时自动开 HTTP 服务
        self.after(200, self.on_start)

    def show(self, key):
        for k, f in self.pages_frames.items():
            f.pack_forget()
        self.pages_frames[key].pack(fill=tk.BOTH, expand=True)
        self.refresh_page(key)

    # ---------- 仪表盘 ----------
    def build_dash(self):
        f = ttk.Frame(self.content)
        self.pages_frames = getattr(self, "pages_frames", {})
        self.pages_frames["dash"] = f
        self.dash_labels = {}
        for i, (k, label) in enumerate([
            ("users", "注册用户"),
            ("providers", "上游提供商"),
            ("models", "对外模型"),
        ]):
            ttk.Label(f, text=label, font=("", 12)).grid(row=i, column=0, padx=10, pady=10, sticky="w")
            v = ttk.Label(f, text="0", font=("", 20, "bold"), foreground="#16a085")
            v.grid(row=i, column=1, padx=20, pady=10, sticky="w")
            self.dash_labels[k] = v
        ttk.Label(f, text="提示：先在「上游提供商」添加模型商，再到「对外模型」包装成 darling 品牌。",
                  foreground="#7f8c8d").grid(row=99, column=0, columnspan=2, pady=30, sticky="w")

    # ---------- 用户 ----------
    def build_users(self):
        f = ttk.Frame(self.content)
        self.pages_frames["users"] = f
        cols = ("id", "email", "created_at", "status")
        self.tree_users = ttk.Treeview(f, columns=cols, show="headings", height=20)
        for c, t in zip(cols, ("ID", "邮箱", "注册时间", "状态")):
            self.tree_users.heading(c, text=t)
            self.tree_users.column(c, width=120 if c != "email" else 240)
        self.tree_users.pack(fill=tk.BOTH, expand=True)
        bar = ttk.Frame(f)
        bar.pack(fill=tk.X, pady=4)
        ttk.Button(bar, text="禁用/启用", command=self.toggle_user).pack(side=tk.LEFT, padx=2)
        ttk.Button(bar, text="删除", command=self.del_user).pack(side=tk.LEFT, padx=2)

    def toggle_user(self):
        sel = self.tree_users.selection()
        if not sel:
            return
        uid = int(self.tree_users.item(sel[0])["values"][0])
        u = db.get_user(uid)
        new = "active" if u["status"] != "active" else "disabled"
        db.set_user_status(uid, new)
        self.refresh_users()

    def del_user(self):
        sel = self.tree_users.selection()
        if not sel:
            return
        if not messagebox.askyesno("确认", "删除该用户？"):
            return
        uid = int(self.tree_users.item(sel[0])["values"][0])
        db.delete_user(uid)
        self.refresh_users()

    # ---------- 提供商 ----------
    def build_providers(self):
        f = ttk.Frame(self.content)
        self.pages_frames["providers"] = f
        form = ttk.LabelFrame(f, text="新增 / 编辑提供商", padding=8)
        form.pack(fill=tk.X)
        self.p_name = self._entry(form, "名称", 0)
        self.p_url = self._entry(form, "Base URL", 1)
        self.p_key = self._entry(form, "API Key", 2)
        self.p_type = ttk.Combobox(form, values=["text", "image", "video"], state="readonly", width=20)
        self.p_type.set("text")
        self.p_type.grid(row=3, column=1, sticky="w", pady=2)
        ttk.Label(form, text="类型").grid(row=3, column=0, sticky="e", pady=2)
        btns = ttk.Frame(form); btns.grid(row=4, column=0, columnspan=2, pady=6)
        ttk.Button(btns, text="保存", command=self.save_provider).pack(side=tk.LEFT, padx=4)
        ttk.Button(btns, text="测试连接 / 拉模型", command=self.test_provider).pack(side=tk.LEFT, padx=4)

        cols = ("id", "name", "base_url", "type")
        self.tree_prov = ttk.Treeview(f, columns=cols, show="headings", height=12)
        for c, t in zip(cols, ("ID", "名称", "Base URL", "类型")):
            self.tree_prov.heading(c, text=t)
            self.tree_prov.column(c, width=100 if c != "base_url" else 360)
        self.tree_prov.pack(fill=tk.BOTH, expand=True, pady=4)
        bar = ttk.Frame(f); bar.pack(fill=tk.X)
        ttk.Button(bar, text="删除选中", command=self.del_provider).pack(side=tk.LEFT)

    def _entry(self, parent, label, row):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="e", pady=2, padx=4)
        e = ttk.Entry(parent, width=40)
        e.grid(row=row, column=1, sticky="w", pady=2)
        return e

    def save_provider(self):
        name = self.p_name.get().strip()
        url = self.p_url.get().strip()
        key = self.p_key.get().strip()
        ptype = self.p_type.get()
        if not name or not url:
            messagebox.showwarning("缺字段", "名称和 Base URL 必填")
            return
        db.add_provider(name, url, key, ptype)
        self.p_name.delete(0, tk.END); self.p_url.delete(0, tk.END); self.p_key.delete(0, tk.END)
        self.refresh_providers()

    def del_provider(self):
        sel = self.tree_prov.selection()
        if not sel:
            return
        pid = int(self.tree_prov.item(sel[0])["values"][0])
        db.delete_provider(pid)
        self.refresh_providers()

    def test_provider(self):
        """测试当前表单里的 base_url + key，拉 /models。"""
        url = self.p_url.get().strip().rstrip("/")
        key = self.p_key.get().strip()
        if not url:
            messagebox.showwarning("缺字段", "先填 Base URL")
            return
        import urllib.request, json as _json
        try:
            req = urllib.request.Request(
                url + "/models",
                headers={"Authorization": f"Bearer {key}"},
            )
            with urllib.request.urlopen(req, timeout=15) as r:
                data = _json.loads(r.read().decode())
            ids = [m.get("id", "?") for m in data.get("data", [])]
            messagebox.showinfo("连接成功", f"检测到 {len(ids)} 个模型：\n" + "\n".join(ids[:20]))
        except Exception as e:
            messagebox.showerror("连接失败", str(e)[:300])

    def fetch_upstream_models(self, pid: int):
        """从指定提供商拉 /models，返回 id 列表。"""
        p = db.get_provider(pid)
        if not p:
            return []
        import urllib.request, json as _json
        try:
            req = urllib.request.Request(
                p["base_url"].rstrip("/") + "/models",
                headers={"Authorization": f"Bearer {p['api_key']}"},
            )
            with urllib.request.urlopen(req, timeout=15) as r:
                data = _json.loads(r.read().decode())
            return [m.get("id", "?") for m in data.get("data", [])]
        except Exception as e:
            messagebox.showerror("拉取失败", str(e)[:300])
            return []

    # ---------- 对外模型 ----------
    def build_models(self):
        f = ttk.Frame(self.content)
        self.pages_frames["models"] = f
        form = ttk.LabelFrame(f, text="新增对外模型（包装上游 → darling 品牌）", padding=8)
        form.pack(fill=tk.X)
        self.m_name = self._entry(form, "对外名称", 0)
        self.m_desc = self._entry(form, "描述", 1)
        # 上游模型名：改成 Combobox，选提供商后自动拉列表
        ttk.Label(form, text="上游模型名").grid(row=2, column=0, sticky="e", pady=2, padx=4)
        self.m_upstream = ttk.Combobox(form, width=38)
        self.m_upstream.grid(row=2, column=1, sticky="w", pady=2)
        self.m_provider = ttk.Combobox(form, state="readonly", width=30)
        self.m_provider.grid(row=3, column=1, sticky="w", pady=2)
        self.m_provider.bind("<<ComboboxSelected>>", self._on_prov_changed)
        ttk.Label(form, text="上游提供商").grid(row=3, column=0, sticky="e", pady=2, padx=4)
        self.m_type = ttk.Combobox(form, values=["text", "image", "video", "hybrid"], state="readonly", width=20)
        self.m_type.set("text")
        self.m_type.grid(row=4, column=1, sticky="w", pady=2)
        ttk.Label(form, text="类型").grid(row=4, column=0, sticky="e", pady=2, padx=4)
        ttk.Label(form, text="系统提示词").grid(row=5, column=0, sticky="ne", pady=2, padx=4)
        self.m_prompt = tk.Text(form, width=50, height=3)
        self.m_prompt.grid(row=5, column=1, sticky="w", pady=2)
        ttk.Button(form, text="保存", command=self.save_model).grid(row=6, column=0, columnspan=2, pady=6)

        cols = ("id", "name", "type", "upstream_model")
        self.tree_models = ttk.Treeview(f, columns=cols, show="headings", height=10)
        for c, t in zip(cols, ("ID", "对外名称", "类型", "上游模型")):
            self.tree_models.heading(c, text=t)
            self.tree_models.column(c, width=100 if c != "name" else 200)
        self.tree_models.pack(fill=tk.BOTH, expand=True, pady=4)
        bar = ttk.Frame(f); bar.pack(fill=tk.X)
        ttk.Button(bar, text="删除选中", command=self.del_model).pack(side=tk.LEFT)

    def _on_prov_changed(self, _evt=None):
        """对外模型表单选了提供商 → 自动拉上游模型列表。"""
        label = self.m_provider.get()
        if "|" not in label:
            return
        pid = int(label.split("|")[0])
        ids = self.fetch_upstream_models(pid)
        self.m_upstream["values"] = ids
        if ids:
            self.m_upstream.set(ids[0])

    def save_model(self):
        name = self.m_name.get().strip()
        desc = self.m_desc.get().strip()
        up = self.m_upstream.get().strip()
        provider_label = self.m_provider.get()
        ptype = self.m_type.get()
        prompt = self.m_prompt.get("1.0", tk.END).strip()
        if not name or not up or not provider_label:
            messagebox.showwarning("缺字段", "对外名称 / 上游模型名 / 提供商 必填")
            return
        pid = int(provider_label.split("|")[0])
        db.add_model(name, desc, pid, up, ptype, prompt)
        self.m_name.delete(0, tk.END); self.m_desc.delete(0, tk.END); self.m_upstream.delete(0, tk.END)
        self.m_prompt.delete("1.0", tk.END)
        self.refresh_models()

    def del_model(self):
        sel = self.tree_models.selection()
        if not sel:
            return
        mid = int(self.tree_models.item(sel[0])["values"][0])
        db.delete_model(mid)
        self.refresh_models()

    # ---------- 额度设置 ----------
    def build_settings(self):
        f = ttk.Frame(self.content)
        self.pages_frames["settings"] = f
        ttk.Label(f, text="每 5 小时免费额度", font=("", 12, "bold")).grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        self.s_tokens = self._entry(f, "文本 token 上限", 1)
        self.s_tokens.delete(0, tk.END); self.s_tokens.insert(0, str(config.FREE_LIMITS["text_tokens"]))
        self.s_images = self._entry(f, "图片张数", 2)
        self.s_images.delete(0, tk.END); self.s_images.insert(0, str(config.FREE_LIMITS["images"]))
        self.s_videos = self._entry(f, "视频个数", 3)
        self.s_videos.delete(0, tk.END); self.s_videos.insert(0, str(config.FREE_LIMITS["videos"]))
        ttk.Button(f, text="保存额度", command=self.save_limits).grid(row=4, column=0, columnspan=2, pady=10, sticky="w")

    def save_limits(self):
        try:
            config.FREE_LIMITS["text_tokens"] = int(self.s_tokens.get())
            config.FREE_LIMITS["images"] = int(self.s_images.get())
            config.FREE_LIMITS["videos"] = int(self.s_videos.get())
            db.set_setting("free_limits", json.dumps(config.FREE_LIMITS))
            messagebox.showinfo("已保存", "额度已更新（重启后生效）")
        except Exception as e:
            messagebox.showerror("错误", str(e))

    # ---------- 刷新 ----------
    def refresh_all(self):
        for k in self.pages_frames:
            self.refresh_page(k)

    def refresh_page(self, key):
        if key == "dash":
            self.dash_labels["users"].config(text=str(len(db.list_users())))
            self.dash_labels["providers"].config(text=str(len(db.list_providers())))
            self.dash_labels["models"].config(text=str(len(db.list_models())))
        elif key == "users":
            self.refresh_users()
        elif key == "providers":
            self.refresh_providers()
        elif key == "models":
            self.refresh_models()

    def refresh_users(self):
        for i in self.tree_users.get_children():
            self.tree_users.delete(i)
        for u in db.list_users():
            self.tree_users.insert("", tk.END, values=(
                u["id"], u["email"],
                time.strftime("%Y-%m-%d %H:%M", time.localtime(u["created_at"])),
                u["status"],
            ))

    def refresh_providers(self):
        for i in self.tree_prov.get_children():
            self.tree_prov.delete(i)
        for p in db.list_providers():
            self.tree_prov.insert("", tk.END, values=(p["id"], p["name"], p["base_url"], p["type"]))
        # 提供商变了 → 对外模型表单里的提供商下拉也要刷新
        self.refresh_models()

    def refresh_models(self):
        for i in self.tree_models.get_children():
            self.tree_models.delete(i)
        for m in db.list_models():
            self.tree_models.insert("", tk.END, values=(
                m["id"], m["name"], m["type"], m["upstream_model"]))
        # 刷新提供商下拉
        provs = db.list_providers()
        self.m_provider["values"] = [f"{p['id']}|{p['name']}" for p in provs]
        if provs:
            self.m_provider.set(f"{provs[0]['id']}|{provs[0]['name']}")

    # ---------- 服务启停 ----------
    def on_start(self):
        if self.srv_handle:
            messagebox.showinfo("已启动", "服务已在运行")
            return
        try:
            self.srv_handle = server.start_server()
            self.lbl_status.config(text=f"● 服务运行中（:{config.PORT}）", foreground="#27ae60")
            self.btn_start.config(text="停止服务")
        except Exception as e:
            messagebox.showerror("启动失败", str(e))

    def on_toggle(self):
        if self.srv_handle:
            try:
                self.srv_handle.shutdown()
                self.srv_handle.server_close()
            except Exception:
                pass
            self.srv_handle = None
            self.lbl_status.config(text="● 服务未启动", foreground="#c0392b")
            self.btn_start.config(text="启动服务", state=tk.NORMAL)
        else:
            self.on_start()


import time  # noqa: E402

if __name__ == "__main__":
    import traceback
    try:
        db.init_db()
        print("[darling-server] 数据库就绪，正在打开管理面板…")
        app = App()
        app.mainloop()
    except Exception:
        err = traceback.format_exc()
        print(err)
        with open("error.log", "w", encoding="utf-8") as f:
            f.write(err)
        try:
            input("按回车键关闭…")
        except Exception:
            pass
