# -*- coding: utf-8 -*-
"""optimize_png_assets.py — 压缩 assets 下的课程 PNG（就地覆盖，git 可回退）。

策略（逐文件择优，宁可不改也不损质量）：
  1. 近灰度图（通道扩散 < 8）→ L 模式灰度。
  2. 唯一色 ≤ 256 → 精确 P 模式调色板（视觉无损）。
  3. 其余 → 自适应 256 色量化；先试无抖动（线稿更干净），PSNR 不达标再试
     Floyd-Steinberg；仍不达标（PSNR < --min-psnr，默认 38dB）则放弃该文件。
  4. 新文件须 < 原大小 97% 才写入；写入统一 optimize=True, compress_level=9。

用法：
    python tools/optimize_png_assets.py [--min-psnr 38] [--dry-run]
覆盖目录：assets/steps, assets/answers, assets/subjects
"""
from __future__ import annotations

import argparse
import glob
import math
import os

import numpy as np
from PIL import Image

ASSET_DIRS = ["assets/steps", "assets/answers", "assets/subjects"]
MIN_BYTES = 10 * 1024  # 太小的文件不值得动


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    diff = a.astype(np.float64) - b.astype(np.float64)
    mse = float(np.mean(diff * diff))
    if mse == 0:
        return float("inf")
    return 10 * math.log10(255 * 255 / mse)


def best_encoding(path: str, min_psnr: float) -> tuple[bytes, float, str] | None:
    """返回 (png字节, PSNR, 方案名)；不达标的文件返回 None。"""
    im = Image.open(path)
    orig = np.asarray(im.convert("RGB"))

    candidates: list[tuple[str, Image.Image]] = []

    # 1) 近灰度 → L
    if im.mode in ("RGB", "RGBA", "P"):
        rgb = im.convert("RGB")
        arr = np.asarray(rgb, dtype=np.int16)
        spread = int((arr.max(axis=2) - arr.min(axis=2)).max())
        if spread < 8:
            candidates.append(("gray-L", rgb.convert("L")))

    # 2) 精确调色板（唯一色 ≤ 256）
    rgb = im.convert("RGB")
    colors = rgb.getcolors(maxcolors=257)
    if colors is not None and len(colors) <= 256:
        candidates.append(("palette-exact", rgb.quantize(colors=256)))

    # 3) 自适应量化（两种抖动都试）
    q_none = rgb.quantize(
        colors=256, method=Image.MEDIANCUT, dither=Image.Dither.NONE
    )
    candidates.append(("palette-dither-none", q_none))
    q_floyd = rgb.quantize(
        colors=256, method=Image.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG
    )
    candidates.append(("palette-dither-floyd", q_floyd))

    best: tuple[bytes, float, str] | None = None
    for name, img in candidates:
        data = img.convert("RGB") if name == "gray-L" else img
        out = os.path.join(os.environ["TEMP"], "_opt_probe.png")
        data.save(out, optimize=True, compress_level=9)
        with open(out, "rb") as fh:
            blob = fh.read()
        decoded = np.asarray(Image.open(out).convert("RGB"))
        score = psnr(orig, decoded)
        if score < min_psnr:
            continue
        if best is None or len(blob) < len(best[0]):
            best = (blob, score, name)
    return best


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-psnr", type=float, default=38.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    files: list[str] = []
    for d in ASSET_DIRS:
        files.extend(sorted(glob.glob(os.path.join(d, "*.png"))))

    changed = skipped_quality = skipped_size = 0
    before_total = after_total = 0
    worst_psnr = float("inf")
    worst_file = ""

    for i, path in enumerate(files, 1):
        size = os.path.getsize(path)
        before_total += size
        if size < MIN_BYTES:
            skipped_size += 1
            continue
        try:
            result = best_encoding(path, args.min_psnr)
        except Exception as e:  # noqa: BLE001
            print(f"WARN {path}: {e}")
            after_total += size
            continue
        after_total += size
        if result is None:
            skipped_quality += 1
            continue
        blob, score, scheme = result
        if len(blob) >= size * 0.97:
            skipped_size += 1
            continue
        after_total -= size  # 即将被替换
        after_total += len(blob)
        if score < worst_psnr:
            worst_psnr, worst_file = score, path
        changed += 1
        if not args.dry_run:
            with open(path, "wb") as fh:
                fh.write(blob)
        if changed % 100 == 0:
            print(f"  ... {changed} files rewritten ({i}/{len(files)})")

    print(f"files total   : {len(files)}")
    print(f"rewritten     : {changed}")
    print(f"skipped(quality): {skipped_quality}  skipped(size/unchanged): {skipped_size}")
    print(f"size          : {before_total/1048576:.2f} MB -> {after_total/1048576:.2f} MB "
          f"({(1 - after_total / max(before_total, 1)) * 100:.1f}% saved)")
    if changed:
        print(f"worst PSNR    : {worst_psnr:.1f} dB  ({worst_file})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
