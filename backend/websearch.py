# -*- coding: utf-8 -*-
"""联网搜索：默认 DuckDuckGo（免费无需 key），可选 Tavily（设置中配 key）。

返回统一结构：
    {"results": [{"title", "url", "snippet"}], "engine": "..."}
"""
import json
import re
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")


def _http(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def search_duckduckgo(query, max_results=5):
    q = urllib.parse.quote(query)
    html = _http(f"https://html.duckduckgo.com/html/?q={q}")
    # 解析 result 块：<a class="result__a" href="...">title</a>
    # 和 <a class="result__snippet" ...>snippet</a>
    items = []
    # 先按 result 整体切分
    blocks = re.split(r'<div class="result results_links', html)
    for blk in blocks[1:]:
        if len(items) >= max_results:
            break
        m_title = re.search(r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>', blk, re.S)
        m_snip = re.search(r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>', blk, re.S)
        if not m_title:
            continue
        href = m_title.group(1)
        # duckduckgo 重定向链接
        if href.startswith("//"):
            href = "https:" + href
        mm = re.search(r'uddg=([^&]+)', href)
        if mm:
            href = urllib.parse.unquote(mm.group(1))
        title = re.sub(r"<[^>]+>", "", m_title.group(2)).strip()
        snippet = re.sub(r"<[^>]+>", "", m_snip.group(1)).strip() if m_snip else ""
        items.append({"title": title, "url": href, "snippet": snippet})
    return items


def search_tavily(query, api_key, max_results=5):
    body = json.dumps({
        "api_key": api_key,
        "query": query,
        "max_results": max_results,
        "search_depth": "basic",
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.tavily.com/search",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
    items = []
    for res in data.get("results", [])[:max_results]:
        items.append({
            "title": res.get("title", ""),
            "url": res.get("url", ""),
            "snippet": res.get("content", ""),
        })
    return items


def search(query, settings=None, max_results=5):
    settings = settings or {}
    engine = settings.get("websearch_engine", "duckduckgo")
    if engine == "tavily":
        key = (settings.get("tavily_api_key") or "").strip()
        if key:
            try:
                return search_tavily(query, key, max_results), "tavily"
            except Exception:
                pass
    try:
        return search_duckduckgo(query, max_results), "duckduckgo"
    except Exception:
        return [], "duckduckgo"


def detect_container():
    """自动检测容器环境：Windows -> WSL 发行版；Linux -> Docker。

    - WSL 输出可能是 UTF-16LE（新 wsl.exe）或 ANSI/UTF-8（WSL 1 旧版），
      这里统一解析；并过滤 docker-desktop 等虚拟发行版。
    """
    import shutil
    import subprocess
    out = {
        "wsl_installed": False,
        "distros": [],
        "docker_installed": False,
        "docker_running": False,
        "platform": "windows" if shutil.os.name == "nt" else "linux",
    }
    if shutil.os.name == "nt":
        if shutil.which("wsl"):
            out["wsl_installed"] = True
            try:
                r = subprocess.run(["wsl", "--list", "--quiet"],
                                   capture_output=True, timeout=15)
                raw = r.stdout
                # WSL1 旧版输出 UTF-16LE（常带 BOM）；新版可能带 UTF-8 BOM 或纯 UTF-8。
                # 按 BOM 探测优先，避免把纯 UTF-8 误判成 UTF-16 产生乱码
                text = None
                if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
                    text = raw.decode("utf-16", "replace")
                elif raw.startswith(b"\xef\xbb\xbf"):
                    text = raw.decode("utf-8-sig", "replace")
                else:
                    try:
                        text = raw.decode("utf-8")
                    except UnicodeDecodeError:
                        # 无 BOM 的 UTF-16LE（部分 WSL1 版本）
                        try:
                            text = raw.decode("utf-16-le", "replace")
                        except Exception:
                            text = raw.decode("utf-8", "replace")
                if text is None:
                    text = raw.decode("utf-8", "replace")
                seen = set()
                for line in text.splitlines():
                    line = line.strip().replace("\x00", "").lstrip("\ufeff")
                    low = line.lower()
                    if not line or low.startswith("windows") or low.startswith("docker"):
                        continue
                    if low in ("wsl", "wsl2", "wsl1"):
                        continue
                    if line not in seen:
                        seen.add(line)
                        out["distros"].append(line)
            except Exception:
                pass
    else:
        docker = shutil.which("docker")
        if docker:
            out["docker_installed"] = True
            try:
                r = subprocess.run(["docker", "info"],
                                   capture_output=True, timeout=10)
                out["docker_running"] = r.returncode == 0
            except Exception:
                pass
    return out
