# -*- coding: utf-8 -*-
"""convert_scans_webp.py — 题面/答案扫描图 jpg → WebP q80（PSNR 门禁 + 路径改写）。

用法：python tools/convert_scans_webp.py [--min-psnr 40] [--dry-run]
行为：
  1. assets/subjects、assets/answers 下 *.jpg → 同名 .webp（q80, method=6）。
  2. 仅当体积 < 原 90% 且 PSNR >= 门禁时替换，原 jpg 删除。
  3. curriculum.json 的 subjectImage/answerImage 后缀同步改写。
幂等：无 jpg 时直接结束。
"""
from __future__ import annotations

import argparse
import glob
import io
import json
import math
import os

import numpy as np
from PIL import Image


def psnr(a, b) -> float:
    diff = a.astype(np.float64) - b.astype(np.float64)
    mse = float(np.mean(diff * diff))
    return float("inf") if mse == 0 else 10 * math.log10(255 * 255 / mse)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-psnr", type=float, default=40.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    jpgs = sorted(glob.glob("assets/subjects/*.jpg") + glob.glob("assets/answers/*.jpg"))
    changed = skipped = 0
    before = after = 0.0
    worst = (float("inf"), "")

    for path in jpgs:
        size = os.path.getsize(path)
        before += size
        im = Image.open(path).convert("RGB")
        buf = io.BytesIO()
        im.save(buf, format="WEBP", quality=80, method=6)
        blob = buf.getvalue()
        decoded = np.asarray(Image.open(io.BytesIO(blob)))
        score = psnr(np.asarray(im), decoded)
        if len(blob) >= size * 0.9 or score < args.min_psnr:
            after += size
            skipped += 1
            continue
        after += len(blob)
        changed += 1
        if score < worst[0]:
            worst = (score, path)
        if not args.dry_run:
            webp = path[:-4] + ".webp"
            with open(webp, "wb") as fh:
                fh.write(blob)
            os.remove(path)

    if not args.dry_run and changed:
        cur_path = "assets/data/curriculum.json"
        with open(cur_path, encoding="utf-8") as f:
            data = json.load(f)
        patched = 0
        for prob in data["problems"]:
            for key in ("subjectImage", "answerImage"):
                img = prob.get(key, "")
                if img.endswith(".jpg"):
                    prob[key] = img[:-4] + ".webp"
                    patched += 1
        with open(cur_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=2))
        print(f"curriculum paths patched: {patched}")

    print(f"files: {len(jpgs)}  converted: {changed}  skipped: {skipped}")
    print(f"size: {before/1048576:.1f} MB -> {after/1048576:.1f} MB "
          f"({(1 - after / max(before, 1)) * 100:.0f}% saved)")
    if changed:
        print(f"worst PSNR: {worst[0]:.1f} dB ({worst[1]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
