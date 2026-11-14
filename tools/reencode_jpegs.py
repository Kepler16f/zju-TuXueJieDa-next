# -*- coding: utf-8 -*-
"""reencode_jpegs.py — 题面/答案扫描图 JPEG 重编码（q82 progressive，PSNR 门禁）。

用法：python tools/reencode_jpegs.py [--min-psnr 40] [--dry-run]
目录：assets/subjects, assets/answers
仅当重编码体积 < 原 90% 且 PSNR 达标时替换。
"""
from __future__ import annotations

import argparse
import glob
import io
import math
import os

import numpy as np
from PIL import Image

DIRS = ["assets/subjects", "assets/answers"]


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    diff = a.astype(np.float64) - b.astype(np.float64)
    mse = float(np.mean(diff * diff))
    return float("inf") if mse == 0 else 10 * math.log10(255 * 255 / mse)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-psnr", type=float, default=40.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    files = sorted(sum((glob.glob(f"{d}/*.jpg") for d in DIRS), []))

    changed = skipped = 0
    before = after = 0.0
    worst = (float("inf"), "")
    for path in files:
        size = os.path.getsize(path)
        before += size
        im = Image.open(path).convert("RGB")
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=82, optimize=True, progressive=True)
        blob = buf.getvalue()
        if len(blob) >= size * 0.9:
            after += size
            skipped += 1
            continue
        decoded = np.asarray(Image.open(io.BytesIO(blob)))
        orig = np.asarray(im)
        score = psnr(orig, decoded)
        if score < args.min_psnr:
            after += size
            skipped += 1
            continue
        if score < worst[0]:
            worst = (score, path)
        after += len(blob)
        changed += 1
        if not args.dry_run:
            with open(path, "wb") as fh:
                fh.write(blob)

    print(f"files: {len(files)}  rewritten: {changed}  skipped: {skipped}")
    print(f"size: {before/1048576:.1f} MB -> {after/1048576:.1f} MB "
          f"({(1 - after / max(before, 1)) * 100:.0f}% saved)")
    if changed:
        print(f"worst PSNR: {worst[0]:.1f} dB ({worst[1]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
