#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_icon.py — 把图标候选 PNG 应用为 Windows / Android 应用图标。

用法（项目根目录执行）:
    python tools/apply_icon.py <候选PNG路径>
例如:
    python tools/apply_icon.py build/icon_candidates/icon_A.png

行为:
  1. 生成 windows/runner/resources/app_icon.ico，
     内嵌多尺寸 16/24/32/48/64/128/256（由源图 LANCZOS 缩放）。
  2. 覆写 Android 启动图标 ic_launcher.png:
       mipmap-mdpi    48px
       mipmap-hdpi    72px
       mipmap-xhdpi   96px
       mipmap-xxhdpi  144px
       mipmap-xxxhdpi 192px
  3. 不触碰 iOS / macOS / web 资源。

保证:
  - 可重复运行（幂等，纯覆盖写入）。
  - 先校验后写入：任一目标目录缺失（Windows 资源目录或任一 mipmap 目录）
    时立即报错退出，不产生半套写入。
  - 非正方形源图按短边居中裁剪（打印 WARN）；短边小于 256px 报错拒绝。
  - 本脚本只生成/覆盖图标文件，不修改任何构建配置。
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICO_PATH = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
MIPMAP_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    src = Path(argv[1])
    if not src.is_file():
        print(f"ERROR: 候选图标不存在: {src}")
        return 2

    # ---- 校验阶段：全部通过后才写入 ----
    if not ICO_PATH.parent.is_dir():
        print(f"ERROR: Windows 资源目录不存在: {ICO_PATH.parent}")
        return 1
    missing = [d for d in MIPMAP_SIZES if not (ANDROID_RES / d).is_dir()]
    if missing:
        print("ERROR: 以下 Android mipmap 目录不存在（请确认项目包含 android 平台目录）:")
        for d in missing:
            print(f"  - {ANDROID_RES / d}")
        return 1

    try:
        img = Image.open(src)
        img.load()
    except Exception as e:  # noqa: BLE001
        print(f"ERROR: 无法读取图像 {src}: {e}")
        return 2

    if img.width != img.height:
        side = min(img.width, img.height)
        left = (img.width - side) // 2
        top = (img.height - side) // 2
        print(f"WARN: 源图非正方形 {img.size} -> 居中裁剪为 {side}x{side}")
        img = img.crop((left, top, left + side, top + side))
    if img.width < 256:
        print(f"ERROR: 源图仅 {img.width}x{img.height}，短边需 >= 256px 才能生成高质量 ICO")
        return 2
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    # ---- 写入阶段 ----
    base = img.resize((256, 256), Image.LANCZOS)
    base.save(str(ICO_PATH), format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"OK 写入 {ICO_PATH}（内嵌尺寸 {ICO_SIZES}）")

    for d, s in sorted(MIPMAP_SIZES.items()):
        out = ANDROID_RES / d / "ic_launcher.png"
        img.resize((s, s), Image.LANCZOS).save(str(out), format="PNG")
        print(f"OK 写入 {out}（{s}x{s}）")

    print("完成：未触碰 iOS/macOS/web 资源；可重复运行。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
