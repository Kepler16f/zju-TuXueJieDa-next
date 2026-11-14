# -*- coding: utf-8 -*-
"""convert_steps_webp.py — 步骤图 PNG → WebP q80（就地替换 + 改写 curriculum.json）。

用法：python tools/convert_steps_webp.py
行为：
  1. assets/steps/*.png → 同名 .webp（quality=80, method=6），转换成功后删除 PNG。
  2. curriculum.json 中 steps[].image 的 .png 后缀批量改为 .webp。
幂等：无 PNG 时直接结束。
"""
from __future__ import annotations

import glob
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    os.chdir(ROOT)
    pngs = sorted(glob.glob("assets/steps/*.png"))
    if not pngs:
        print("no step PNGs left; nothing to do")
        return 0

    before = after = 0
    for i, path in enumerate(pngs, 1):
        webp = path[:-4] + ".webp"
        im = Image.open(path).convert("RGB")
        im.save(webp, quality=80, method=6)
        before += os.path.getsize(path)
        after += os.path.getsize(webp)
        os.remove(path)
        if i % 200 == 0:
            print(f"  ... {i}/{len(pngs)}")

    cur_path = "assets/data/curriculum.json"
    with open(cur_path, encoding="utf-8") as f:
        data = json.load(f)
    patched = 0
    for p in data["problems"]:
        for s in p["steps"]:
            img = s.get("image", "")
            if img.startswith("assets/steps/") and img.endswith(".png"):
                s["image"] = img[:-4] + ".webp"
                patched += 1
    with open(cur_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2))

    print(f"converted {len(pngs)} files: {before/1048576:.1f} MB -> {after/1048576:.1f} MB "
          f"({(1 - after / max(before, 1)) * 100:.0f}% saved); curriculum paths patched: {patched}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
