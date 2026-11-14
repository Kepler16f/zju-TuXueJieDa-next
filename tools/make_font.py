#!/usr/bin/env python3
"""Build in-app bundled subset fonts (family 'AppSansCJK') from Noto Sans CJK SC.

Pipeline:
 1. Collect charset:
      assets/data/curriculum.json (all text)  U  lib/**/*.dart (all source text)
      U  ASCII 0x20-0x7E  U  common CJK punctuation  U  fullwidth digits/letters
 2. Subset tools/font_src/NotoSansCJKsc-{Regular,Bold}.otf -> assets/fonts/AppSansCJK-*.otf
    via fontTools.subset (pyftsubset). If Regular > TARGET_MB, progressively tighten
    layout features / name table (charset is NEVER reduced).
 3. Write charset dump to tools/font_src/charset.txt, render build/font_preview.png
    with PIL, verify glyph coverage of preview lines against the output cmap,
    and print the internal family name of each output font.

Usage:  python tools/make_font.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "tools" / "font_src"
OUT_DIR = ROOT / "assets" / "fonts"
CURRICULUM = ROOT / "assets" / "data" / "curriculum.json"
LIB_DIR = ROOT / "lib"
BUILD_DIR = ROOT / "build"

TARGET_MB = 3.0

SOURCES = {
    "Regular": SRC_DIR / "NotoSansCJKsc-Regular.otf",
    "Bold": SRC_DIR / "NotoSansCJKsc-Bold.otf",
}
OUTPUTS = {
    "Regular": OUT_DIR / "AppSansCJK-Regular.otf",
    "Bold": OUT_DIR / "AppSansCJK-Bold.otf",
}

PREVIEW_LINES = [
    "图学基础教程习题解答 组合体和实体造型",
    "P43 No.12 便签设置 ①②③ ←→ 页码",
]

# ---- charset components (explicit unicode escapes, keep the file ASCII-safe) ----
ASCII_CHARS = [chr(c) for c in range(0x20, 0x7F)]

CJK_PUNCT = (
    "\uFF0C\u3002\u3001\uFF1B\uFF1A\uFF1F\uFF01"          # ，。、；：？！
    "\u201C\u201D\u2018\u2019"                            # “ ” ‘ ’
    "\uFF08\uFF09\u300A\u300B\u3010\u3011\u3014\u3015"    # （）《》【】〔〕
    "\u00B7\u2014\u2026\u2013"                            # · — … –
    "\u2103\u00D7\u00F7\u00B1\u00B0"                      # ℃ × ÷ ± °
    + "".join(chr(0x2460 + i) for i in range(12))         # ① ② ... ⑫
    + "\u2190\u2192\u2191\u2193\u2194\u21D2"              # ← → ↑ ↓ ↔ ⇒
)

FULLWIDTH = (
    [chr(c) for c in range(0xFF10, 0xFF1A)]               # ０-９
    + [chr(c) for c in range(0xFF21, 0xFF3B)]             # Ａ-Ｚ
    + [chr(c) for c in range(0xFF41, 0xFF5B)]             # ａ-ｚ
)


def collect_charset() -> tuple[set[str], dict]:
    """Gather the app charset from curriculum.json + lib sources + fixed sets."""
    stats = {"curriculum_chars": 0, "dart_files": 0, "dart_chars": 0}
    chars: set[str] = set()

    if CURRICULUM.exists():
        text = CURRICULUM.read_text(encoding="utf-8", errors="replace")
        chars |= set(text)
        stats["curriculum_chars"] = len(text)
    else:
        print(f"WARN: {CURRICULUM} not found, skipping it")

    if LIB_DIR.exists():
        for p in sorted(LIB_DIR.rglob("*.dart")):
            text = p.read_text(encoding="utf-8", errors="replace")
            chars |= set(text)
            stats["dart_files"] += 1
            stats["dart_chars"] += len(text)
    else:
        print(f"WARN: {LIB_DIR} not found, skipping it")

    chars |= set(ASCII_CHARS)
    chars |= set(CJK_PUNCT)
    chars |= set(FULLWIDTH)

    # Control characters / newlines are not glyphs; drop everything below 0x20.
    chars = {c for c in chars if ord(c) >= 0x20}
    return chars, stats


def subset_font(src: Path, out: Path, text: str, tight: bool, desub: bool) -> int:
    """Run one subset pass; return output size in bytes."""
    options = subset.Options()
    options.drop_tables += ["vhea", "vmtx", "VORG"]  # horizontal-only app UI
    options.notdef_outline = True                    # visible .notdef box
    options.name_languages = [0x0409]                # English-only names (default)

    if tight:
        options.layout_features = []                 # drop all GSUB/GPOS features
        options.name_IDs = [1, 2, 3, 4, 6]           # keep only essential names
    else:
        options.layout_features = subset.Options().layout_features  # default set
        options.name_IDs = [0, 1, 2, 3, 4, 5, 6]

    if desub:
        options.desubroutinize = True

    font = subset.load_font(str(src), options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    subset.save_font(font, str(out), options)
    size = out.stat().st_size
    font.close()
    return size


def build_weight(name: str, src: Path, out: Path, text: str) -> tuple[int, str]:
    """Subset one weight, tightening automatically until Regular fits TARGET_MB."""
    size = subset_font(src, out, text, tight=False, desub=False)
    mode = "default layout features + full name table"
    if size > TARGET_MB * 1024 * 1024:
        size = subset_font(src, out, text, tight=True, desub=False)
        mode = "layout-features=[] + minimal name table"
        if size > TARGET_MB * 1024 * 1024:
            size = subset_font(src, out, text, tight=True, desub=True)
            mode = "layout-features=[] + minimal name table + desubroutinize"
    return size, mode


def cmap_missing(out: Path, chars) -> list[str]:
    """Return chars (excluding whitespace) that the output font cannot map."""
    font = TTFont(str(out), lazy=True)
    cmap = font.getBestCmap()
    missing = sorted({c for c in chars if c not in (" ", "\u3000") and ord(c) not in cmap})
    font.close()
    return missing


def family_name(out: Path) -> str:
    font = TTFont(str(out), lazy=True)
    rec = font["name"].getDebugName(1)
    sub = font["name"].getDebugName(2)
    ps = font["name"].getDebugName(6)
    font.close()
    return f"{rec} / subfamily={sub!r} / postscript={ps!r}"


def render_preview(paths: list[Path]) -> list[str]:
    """Render build/font_preview.png with PIL; return per-line tofu diagnostics."""
    from PIL import Image, ImageDraw, ImageFont

    fonts = {}
    for p in paths:
        fonts[p] = ImageFont.truetype(str(p), size=44)

    img = Image.new("RGB", (1200, 320), "white")
    draw = ImageDraw.Draw(img)
    y = 24
    report = []
    regular = paths[0]
    bold = paths[1] if len(paths) > 1 else paths[0]
    for i, line in enumerate(PREVIEW_LINES):
        f = regular if i == 0 else bold
        draw.text((24, y), line, font=fonts[f], fill="black")
        # coverage check against the actually-used output font
        font = TTFont(str(f), lazy=True)
        cmap = font.getBestCmap()
        font.close()
        missing = [c for c in line if c != " " and ord(c) not in cmap]
        report.append(f"line{i + 1} ({f.name}): {'OK' if not missing else 'MISSING ' + repr(missing)}")
        y += 60
    # charset stress strip: all ①-⑫ arrows and fullwidth forms
    stress = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫ ←→↑↓↔ ⇒ ℃×÷±° ，。、；：？！ ０１２ＡＢａｂ"
    draw.text((24, y), stress, font=fonts[regular], fill="black")
    font = TTFont(str(regular), lazy=True)
    cmap = font.getBestCmap()
    font.close()
    missing = [c for c in stress if c != " " and ord(c) not in cmap]
    report.append(f"stress ({regular.name}): {'OK' if not missing else 'MISSING ' + repr(missing)}")
    img.save(str(BUILD_DIR / "font_preview.png"))
    return report


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    chars, stats = collect_charset()
    text = "".join(sorted(chars))
    (SRC_DIR / "charset.txt").write_text(text, encoding="utf-8")
    print(f"charset: {len(chars)} unique chars "
          f"(curriculum.json {stats['curriculum_chars']:,} chars from text, "
          f"{stats['dart_files']} dart files {stats['dart_chars']:,} chars)")

    weights = [w for w, s in SOURCES.items() if s.exists()]
    if not weights:
        print("ERROR: no source font found in tools/font_src/ "
              "(expected NotoSansCJKsc-Regular.otf / -Bold.otf)")
        return 1
    for w in weights:
        if not SOURCES[w].exists():
            print(f"WARN: {SOURCES[w].name} missing -> only building available weights")

    results = {}
    for w in weights:
        size, mode = build_weight(w, SOURCES[w], OUTPUTS[w], text)
        results[w] = (OUTPUTS[w], size, mode)
        print(f"{w}: {OUTPUTS[w].name} = {size / (1024 * 1024):.2f} MB ({size:,} bytes) [{mode}]")

    reg_size = results.get("Regular", (0, 0, 0))[1]
    if reg_size > TARGET_MB * 1024 * 1024:
        print(f"WARN: Regular still {reg_size / (1024 * 1024):.2f} MB > {TARGET_MB} MB after all tightening")

    # coverage + preview + name table report
    for w in weights:
        missing = cmap_missing(OUTPUTS[w], chars)
        if missing:
            print(f"{w}: charset coverage missing {len(missing)} chars: {missing[:50]!r}")
        else:
            print(f"{w}: charset coverage 100% ({len(chars)} chars mapped)")
        print(f"{w}: family name -> {family_name(OUTPUTS[w])}")

    try:
        for line in render_preview([results[w][0] for w in weights]):
            print("preview: " + line)
        print(f"preview PNG -> {BUILD_DIR / 'font_preview.png'}")
    except Exception as e:  # preview is diagnostic, never fatal
        print(f"WARN: preview rendering failed: {e}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
