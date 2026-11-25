#!/usr/bin/env python3
"""从 Flutter Web 构建产物生成资源浏览页所需的数据索引。

输入：site/assets/assets/data/curriculum.json + site/assets/assets/**
输出：site/gallery/data.json
"""
import json
import os
from pathlib import Path

from PIL import Image

ROOT = Path(os.environ.get("SITE_ROOT", "/workspace/site"))
CUR = ROOT / "assets/assets/data/curriculum.json"
OUT = ROOT / "gallery/data.json"
POSTERS = ROOT / "gallery/posters"

EXT_KIND = {
    ".jpg": "image", ".jpeg": "image", ".png": "image", ".webp": "image",
    ".gif": "image", ".svg": "image",
    ".mp4": "video", ".webm": "video",
    ".pdf": "doc", ".json": "doc", ".otf": "font", ".ttf": "font",
}

_size_cache = {}


def file_info(abs_path: Path, url: str):
    """返回 {url, ext, kind, size, w, h}，w/h 取图像真实尺寸（失败则为 null）。"""
    ext = abs_path.suffix.lower()
    try:
        size = abs_path.stat().st_size
    except OSError:
        size = 0
    w = h = None
    if ext in (".jpg", ".jpeg", ".png", ".webp"):
        if abs_path not in _size_cache:
            try:
                with Image.open(abs_path) as im:
                    _size_cache[abs_path] = im.size
            except Exception:
                _size_cache[abs_path] = (None, None)
        w, h = _size_cache[abs_path]
    return {
        "url": url,
        "name": abs_path.name,
        "ext": ext.lstrip("."),
        "kind": EXT_KIND.get(ext, "file"),
        "size": size,
        "w": w,
        "h": h,
    }


def resolve(asset_key: str):
    """curriculum.json 里的 'assets/xxx' → 磁盘 'assets/assets/xxx'。"""
    rel = asset_key[len("assets/"):] if asset_key.startswith("assets/") else asset_key
    return ROOT / "assets/assets" / rel


def main():
    data = json.loads(CUR.read_text(encoding="utf-8"))
    chapters = data["chapters"]
    problems = []

    for p in data["problems"]:
        item = {
            "id": p["id"],
            "chapterId": p["chapterId"],
            "label": p.get("displayLabel") or f"第 {p.get('page')} 页第 {p.get('no')} 题",
            "statement": p.get("statement", ""),
            "page": p.get("page"),
            "no": p.get("no"),
            "mode": p.get("jietiMode", ""),
            "subject": None,
            "answer": None,
            "steps": [],
            "video": None,
        }
        if p.get("subjectImage"):
            ap = resolve(p["subjectImage"])
            if ap.exists():
                item["subject"] = file_info(ap, "assets/assets/" + p["subjectImage"][len("assets/"):])
        if p.get("answerImage"):
            ap = resolve(p["answerImage"])
            if ap.exists():
                item["answer"] = file_info(ap, "assets/assets/" + p["answerImage"][len("assets/"):])
        for s in p.get("steps") or []:
            ap = resolve(s["image"])
            if ap.exists():
                info = file_info(ap, "assets/assets/" + s["image"][len("assets/"):])
                info["index"] = s.get("index")
                info["title"] = s.get("title") or ""
                info["note"] = s.get("note") or ""
                item["steps"].append(info)
        # 汇总检索文本：题号 + 题面 + 各步骤标题与备注（资源视图按中文关键词搜得到）
        search_bits = [p.get("displayLabel") or "", p.get("statement") or "", p.get("id") or ""]
        for s in p.get("steps") or []:
            search_bits.append(s.get("title") or "")
            search_bits.append(s.get("note") or "")
        item["searchText"] = " ".join(x for x in search_bits if x)
        if p.get("video"):
            v = p["video"]
            ap = resolve(v["asset"])
            if ap.exists():
                info = file_info(ap, "assets/assets/" + v["asset"][len("assets/"):])
                poster = POSTERS / (ap.stem + ".jpg")
                info["poster"] = "gallery/posters/" + poster.name if poster.exists() else None
                info["sourceAvi"] = v.get("sourceAvi")
                item["video"] = info
        problems.append(item)

    # 平铺资源清单（全部素材文件），并标注每张素材归属哪道题
    by_problem = {}
    for p in problems:
        for key in ("subject", "answer"):
            if p.get(key):
                by_problem[p[key]["name"]] = p["id"]
        for s in p["steps"]:
            by_problem[s["name"]] = p["id"]
        if p.get("video"):
            by_problem[p["video"]["name"]] = p["id"]

    resources = []
    assets_root = ROOT / "assets/assets"
    for dirpath, _dirs, files in os.walk(assets_root):
        for fn in files:
            ap = Path(dirpath) / fn
            rel = ap.relative_to(ROOT).as_posix()
            group = ap.parent.name
            info = file_info(ap, rel)
            info["group"] = group
            info["problemId"] = by_problem.get(fn)
            resources.append(info)
    resources.sort(key=lambda r: (r["group"], r["name"]))

    counts = {}
    for r in resources:
        counts[r["kind"]] = counts.get(r["kind"], 0) + 1

    version = {}
    vp = ROOT / "version.json"
    if vp.exists():
        version = json.loads(vp.read_text(encoding="utf-8"))

    out = {
        "meta": {
            "title": "图学基础教程习题解答 · 资源库",
            "subtitle": "浙江大学《图学基础教程》177 道习题的题面、答案、分步图解与动画演示素材",
            "appVersion": version.get("version", ""),
            "problemCount": len(problems),
            "videoCount": sum(1 for p in problems if p.get("video")),
            "resourceCount": len(resources),
            "counts": counts,
            "totalBytes": sum(r["size"] for r in resources),
        },
        "chapters": [
            {
                "id": c["id"],
                "title": c["title"],
                "subtitle": c.get("subtitle", ""),
                "count": sum(1 for p in problems if p["chapterId"] == c["id"]),
            }
            for c in chapters
        ],
        "problems": problems,
        "resources": resources,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("written", OUT, OUT.stat().st_size, "bytes")
    print("problems:", len(problems), "resources:", len(resources), counts)


if __name__ == "__main__":
    main()
