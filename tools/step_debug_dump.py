"""Dump per-frame channel records and per-sprite layers for one jieti problem.

Usage: python -I tools/step_debug_dump.py <th> [frame_no]
Writes to build/step_debug/<th>/: records.txt, fNN_base.png, fNN_ovK_<mem>.png, fNN_comp.png
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_assets as ea  # noqa: E402

from PIL import Image, ImageDraw  # noqa: E402

OUT_ROOT = Path(r"C:\dev\tuxuejieda_next\build\step_debug")


def collect_key_frames(df: ea.DirFile, members, labels, frames, spans):
    key_frames: list[int] = []
    seen_f: set[int] = set()
    for fidx, fr in enumerate(frames, 1):
        c0 = fr.get(0)
        is_wait = False
        if c0:
            for s_off in (c0[6:8], c0[10:12]):
                sid = struct.unpack(">H", s_off)[0]
                for _, bm in spans.get(sid, []):
                    scr = members.get(bm, {}).get("script", "")
                    if "go to the frame" in scr:
                        is_wait = True
                        break
                if is_wait:
                    break
        if (is_wait or fidx in labels) and fidx not in seen_f:
            seen_f.add(fidx)
            key_frames.append(fidx)
    return key_frames


def main() -> None:
    th = sys.argv[1] if len(sys.argv) > 1 else "35_41"
    only_frame = int(sys.argv[2]) if len(sys.argv) > 2 else None

    jf = ea.SOURCE_ROOT / "jieti" / f"jieP{th}.dir"
    df = ea.DirFile(jf)
    members = df.get_internal_members()
    labels = df.parse_vwlb()
    frames, spans = df.parse_vwsc()
    key_frames = collect_key_frames(df, members, labels, frames, spans)
    print(f"{jf}: frames={len(frames)} key={key_frames} labels={labels}")

    out = OUT_ROOT / th
    out.mkdir(parents=True, exist_ok=True)

    lines: list[str] = []
    bmp_cache: dict[int, Image.Image] = {}

    for fidx in key_frames:
        if only_frame is not None and fidx != only_frame:
            continue
        fr = frames[fidx - 1]
        lines.append(f"=== frame {fidx} label={labels.get(fidx, '')!r} channels={sorted(fr.keys())}")
        canvas = Image.new("RGBA", (ea.STAGE_W, ea.STAGE_H), (255, 255, 255, 255))
        overlay_idx = 0
        for ch in sorted(fr.keys()):
            if ch < 6:
                continue
            rec = fr[ch]
            if rec[0] == 0:
                continue
            clib, cmem = struct.unpack(">HH", rec[4:8])
            if clib != 1 or cmem == 0:
                continue
            mem = members.get(cmem)
            if not mem:
                continue
            hexs = rec.hex(" ")
            py, px, h, w = struct.unpack(">hhhh", rec[12:20])
            regY, regX = struct.unpack(">hh", mem["spec"][18:22])
            ink = rec[1] & 0x3F
            sid = struct.unpack(">H", rec[10:12])[0]
            rot = struct.unpack(">i", rec[28:32])[0] if len(rec) >= 32 else 0
            line = (
                f"ch={ch:3d} type={mem['type']} ink={ink:2d} sid={sid} mem#{cmem}"
                f" name={mem['name']!r} score(py,px,h,w)=({py},{px},{h},{w})"
                f" reg(y,x)=({regY},{regX}) rot={rot}"
                f" spec={mem['spec'].hex(' ')}"
                f" rec={hexs}"
            )
            if mem["type"] == 15 and "XMED" in mem["chunks"]:
                lines.append(line + "  [XMED note]")
                continue
            if mem["type"] != 1 or "BITD" not in mem["chunks"]:
                lines.append(line + "  [skip: not bitmap]")
                continue
            if cmem not in bmp_cache:
                alfa = df.chunks[mem["chunks"]["ALFA"]][1] if "ALFA" in mem["chunks"] else None
                bmp_cache[cmem] = ea.decode_bitd_rgba(
                    mem["spec"], df.chunks[mem["chunks"]["BITD"]][1], alfa
                )
            base_sp = bmp_cache[cmem]
            line += f" natSize={base_sp.size}"
            lines.append(line)

            left = px - regX
            top = py - regY
            target_sz = (w, h) if (w > 0 and h > 0) else base_sp.size
            sp_img = base_sp
            if target_sz != sp_img.size:
                sp_img = sp_img.resize(target_sz, Image.Resampling.BILINEAR)
            inked = ea.apply_ink(sp_img, ink)

            # individual overlay tile: stage-sized, sprite pasted, red border around sprite rect
            tile = Image.new("RGBA", (ea.STAGE_W, ea.STAGE_H), (235, 235, 235, 255))
            tile.alpha_composite(inked, dest=(left, top))
            d = ImageDraw.Draw(tile)
            d.rectangle([left, top, left + target_sz[0] - 1, top + target_sz[1] - 1], outline=(255, 0, 0, 255))
            # also mark alternative rect interpretation (treat as top,left,bottom,right, no reg)
            bl, bt, br, bb = px, py, px + w, py + h  # placeholder
            tile.convert("RGB").save(out / f"f{fidx:02d}_ov{overlay_idx:02d}_ch{ch}_m{cmem}.png")
            overlay_idx += 1

            canvas.alpha_composite(inked, dest=(left, top))
        rgb_img = canvas.convert("RGB")
        rgb_img.save(out / f"f{fidx:02d}_comp.png")

    (out / "records.txt").write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {len(lines)} record lines to {out / 'records.txt'}")


if __name__ == "__main__":
    main()
