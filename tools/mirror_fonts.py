#!/usr/bin/env python3
"""把 Flutter 引擎的字体回退文件镜像到本地 fonts/，消除对 fonts.gstatic.com 的依赖。"""
import os
import re
import concurrent.futures
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("SITE_ROOT", "/workspace/site"))
FAMILIES = ("notosanssc/", "notocoloremoji/", "notosanssymbols2/", "roboto/")
BASE = "https://fonts.gstatic.com/s/"

s = (ROOT / "main.dart.js").read_text(encoding="utf-8", errors="replace")
pairs = re.findall(r'\.c\("([^"]+)"\s*,\s*"([^"]+)"\)', s)
paths = sorted({p for _, p in pairs if p.startswith(FAMILIES)})
# Roboto 是单独拼接的（引擎里是 base + "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"）
paths.append("roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2")
paths = sorted(set(paths))
print("待下载:", len(paths), "个字体文件")

def fetch(rel):
    dest = ROOT / "fonts" / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        return (rel, dest.stat().st_size, "cached")
    try:
        req = urllib.request.Request(BASE + rel, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=40) as r:
            data = r.read()
        dest.write_bytes(data)
        return (rel, len(data), "ok")
    except Exception as e:
        return (rel, 0, f"FAIL {e}")

ok = fail = total = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
    for rel, size, st in ex.map(fetch, paths):
        if st in ("ok", "cached"):
            ok += 1
            total += size
        else:
            fail += 1
            print("  ", rel, st)
print(f"完成：成功 {ok}，失败 {fail}，总体积 {total/1048576:.2f} MB")
