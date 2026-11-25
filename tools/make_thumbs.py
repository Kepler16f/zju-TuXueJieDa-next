#!/usr/bin/env python3
"""生成缩略图：画廊网格与步骤条改用缩略图，把单页流量降 3-4 倍。

输出：
  site/thumbs/<group>/<name>.webp   256px  宽（画廊网格 + 分步图解）
  site/mid/<group>/<name>.webp     800px  宽（题面 / 答案展示）
"""
import os
import time
import concurrent.futures
from pathlib import Path
from PIL import Image

SITE = Path(os.environ.get("SITE_ROOT", "/workspace/site"))
ASSETS = SITE / "assets/assets"
GROUPS = ["subjects", "answers", "steps"]
MAXSIZE = {"thumb": 256, "mid": 800}
QUALITY = {"thumb": 62, "mid": 70}


def one(job):
    src: Path = job["src"]
    out: Path = job["out"]
    size = job["size"]
    q = job["q"]
    rel = src.relative_to(ASSETS).with_suffix(".webp")
    dest = out / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        return ("cached", dest.stat().st_size)
    try:
        with Image.open(src) as im:
            im = im.convert("RGB")
            w, h = im.size
            if w > size:
                im = im.resize((size, max(1, round(h * size / w))), Image.LANCZOS)
            im.save(dest, "WEBP", quality=q, method=4)
        return ("ok", dest.stat().st_size)
    except Exception as e:
        return (f"FAIL {e}", 0)


def main():
    jobs = []
    for g in GROUPS:
        d = ASSETS / g
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp"):
                jobs.append({"src": f, "out": SITE / "thumbs", "size": MAXSIZE["thumb"], "q": QUALITY["thumb"]})
                if g in ("subjects", "answers"):
                    jobs.append({"src": f, "out": SITE / "mid", "size": MAXSIZE["mid"], "q": QUALITY["mid"]})
    print(f"待生成 {len(jobs)} 个缩略图 …")
    t0 = time.time()
    ok = fail = 0
    total = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for st, size in ex.map(one, jobs):
            if st in ("ok", "cached"):
                ok += 1
                total += size
            else:
                fail += 1
                print("  ", st)
    print(f"完成：成功 {ok}，失败 {fail}，用时 {time.time()-t0:.0f}s，体积 {total/1048576:.1f} MB")
    for d in ("thumbs", "mid"):
        p = SITE / d
        if p.exists():
            n = sum(1 for _ in p.rglob("*.webp"))
            sz = sum(f.stat().st_size for f in p.rglob("*.webp"))
            print(f"  {d}/ {n} 个文件, {sz/1048576:.1f} MB, 平均 {sz//max(n,1)/1024:.1f} KB")


if __name__ == "__main__":
    main()
