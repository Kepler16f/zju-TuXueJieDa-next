"""Offline asset extractor and curriculum builder for zju-TuXueJieDa-next.

Reverse-engineers the legacy Director 8.5 cast and score files from
`c:\\Program Files\\图学基础教程习题解答`, composites progressive solution steps
without legacy navigation chrome, resolves exact displayed page/question labels
and order, extracts problem statement and step XMED notes, and transcodes all
available AVI animations to H.264 MP4.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
from collections import deque
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageOps

SOURCE_ROOT = Path(r"c:\Program Files\图学基础教程习题解答")
PROJECT_ROOT = Path(__file__).resolve().parent.parent
ASSETS_ROOT = PROJECT_ROOT / "assets"
FFMPEG_BIN = Path(r"C:\dev\tools\ffmpeg\ffmpeg-master-latest-winarm64-gpl\bin\ffmpeg.exe")
SCRATCH_VERIFY = PROJECT_ROOT / "build" / "extract_verify"

STAGE_W = 540
STAGE_H = 450

CHAPTERS: list[dict[str, str]] = [
    {
        "id": "jcty",
        "title": "基础投影",
        "subtitle": "点、线、面、基本体及截交相贯（共 64 题）",
        "dirFile": "jcty.dir",
    },
    {
        "id": "zht",
        "title": "组合体与表达方法",
        "subtitle": "三视图、轴测图与剖视图（共 78 题）",
        "dirFile": "zht.dir",
    },
    {
        "id": "gct",
        "title": "工程图（标准件、零件与装配）",
        "subtitle": "常用件、公差标注与装配图（共 32 题）",
        "dirFile": "gct.dir",
    },
    {
        "id": "other",
        "title": "曲线曲面与专项投影",
        "subtitle": "计算机绘图曲线曲面及专项练习（共 3 题）",
        "dirFile": "other.dir",
    },
]

# Ground-truth 177 active problems mapped from settled VWSC sprite buttons and
# visually verified rendered button labels (`第XX页 No.Y题`).
# Tuple: (chapter_id, group_index, tihao, display_page, display_no)
VERIFIED_PROBLEMS: list[tuple[str, int, str, int, str]] = [
    # --- jcty (64 problems) ---
    ("jcty", 1, "13_1", 11, "1"),
    ("jcty", 1, "13_2", 11, "2"),
    ("jcty", 1, "14_3", 12, "3"),
    ("jcty", 1, "14_4", 12, "4"),
    ("jcty", 1, "15_5", 13, "5"),
    ("jcty", 1, "15_6", 13, "6"),
    ("jcty", 1, "16_7", 14, "7"),
    ("jcty", 1, "16_8", 14, "8"),
    ("jcty", 1, "17_9", 15, "9"),
    ("jcty", 1, "17_10", 15, "10"),
    ("jcty", 1, "18_11", 16, "11"),
    ("jcty", 1, "18_12", 16, "12"),
    ("jcty", 1, "19_13", 17, "13"),
    ("jcty", 1, "19_14", 17, "14"),
    ("jcty", 1, "20_15", 18, "15"),
    ("jcty", 1, "20_16", 18, "16"),
    ("jcty", 1, "21_17", 19, "17"),
    ("jcty", 1, "21_18", 19, "18"),
    ("jcty", 1, "22_19_1", 20, "19"),
    ("jcty", 1, "23_21", 20, "20"),
    ("jcty", 1, "24_22", 21, "21"),
    ("jcty", 1, "25_23", 22, "22"),
    ("jcty", 1, "22_23_1_n", 22, "23①"),
    ("jcty", 2, "22_23_2_n", 22, "23②"),
    ("jcty", 2, "26_24", 23, "24"),
    ("jcty", 2, "26_25", 23, "25"),
    ("jcty", 2, "27_26", 24, "26"),
    ("jcty", 2, "27_27", 24, "27"),
    ("jcty", 2, "28_28", 25, "28"),
    ("jcty", 2, "28_29", 25, "29"),
    ("jcty", 2, "29_30", 26, "30"),
    ("jcty", 2, "26_30_3_n", 26, "30③"),
    ("jcty", 2, "30_31", 27, "31"),
    ("jcty", 2, "27_32_n", 27, "32"),
    ("jcty", 2, "30_32", 28, "33"),
    ("jcty", 2, "31_33", 28, "34"),
    ("jcty", 2, "29_35_1_n", 29, "1"),
    ("jcty", 2, "29_35_2_n", 29, "2"),
    ("jcty", 2, "32_35_1", 30, "1"),
    ("jcty", 2, "32_35_2", 30, "2"),
    ("jcty", 2, "33_36", 31, "37"),
    ("jcty", 2, "33_37", 31, "38"),
    ("jcty", 2, "35_40", 32, "1"),
    ("jcty", 2, "35_41", 32, "2"),
    ("jcty", 2, "36_42", 33, "3"),
    ("jcty", 2, "36_43", 33, "4"),
    ("jcty", 3, "38_46_1", 34, "1"),
    ("jcty", 3, "38_46_2", 34, "2"),
    ("jcty", 3, "39_47_1", 35, "1"),
    ("jcty", 3, "39_47_2", 35, "2"),
    ("jcty", 3, "36_7_n", 36, "7"),
    ("jcty", 3, "40_49", 36, "8"),
    ("jcty", 3, "41_50", 37, "9"),
    ("jcty", 3, "41_51", 37, "10"),
    ("jcty", 3, "38_11_1_n", 38, "1"),
    ("jcty", 3, "38_11_2_n", 38, "2"),
    ("jcty", 3, "42_52", 39, "12"),
    ("jcty", 3, "43_55", 39, "13"),
    ("jcty", 3, "43_54", 40, "14"),
    ("jcty", 3, "44_56", 41, "15"),
    ("jcty", 3, "44_57", 41, "16"),
    ("jcty", 3, "45_59", 42, "17"),
    ("jcty", 3, "46_60_1", 43, "1"),
    ("jcty", 3, "46_60_2", 43, "2"),
    # --- zht (78 problems) ---
    ("zht", 1, "47_1", 44, "1"),
    ("zht", 1, "49_2_1", 45, "1"),
    ("zht", 1, "49_2_2", 45, "2"),
    ("zht", 1, "49_2_3", 45, "3"),
    ("zht", 1, "50_3_1", 46, "1"),
    ("zht", 1, "50_3_2", 46, "2"),
    ("zht", 1, "50_3_3", 46, "3"),
    ("zht", 1, "54_7", 47, "1"),
    ("zht", 1, "55_8", 48, "1"),
    ("zht", 1, "56_9", 50, "1"),
    ("zht", 1, "50_26n", 50, "2"),
    ("zht", 1, "57_10_2", 51, "1"),
    ("zht", 1, "57_10_3", 51, "2"),
    ("zht", 1, "52_1n", 52, "1"),
    ("zht", 1, "52_2n", 52, "2"),
    ("zht", 1, "52_3n", 52, "3"),
    ("zht", 1, "52_4n", 52, "4"),
    ("zht", 1, "58_10_4", 53, "1"),
    ("zht", 1, "58_10_5", 53, "2"),
    ("zht", 1, "59_10_6", 54, "1"),
    ("zht", 1, "59_10_7", 54, "2"),
    ("zht", 1, "60_10_8", 55, "1"),
    ("zht", 2, "60_10_9", 55, "2"),
    ("zht", 2, "61_10_10", 56, "1"),
    ("zht", 2, "61_10_11", 56, "2"),
    ("zht", 2, "62_10_12", 57, "1"),
    ("zht", 2, "62_10_13", 57, "2"),
    ("zht", 2, "63_10_14", 58, "1"),
    ("zht", 2, "63_10_15", 58, "2"),
    ("zht", 2, "51_4", 59, "1"),
    ("zht", 2, "52_5", 60, "1"),
    ("zht", 2, "88_3", 61, "1"),
    ("zht", 2, "88_4", 61, "2"),
    ("zht", 2, "64_11_1", 62, "1"),
    ("zht", 2, "64_11_2", 62, "2"),
    ("zht", 2, "64_11_3", 62, "3"),
    ("zht", 2, "64_11_4", 62, "4"),
    ("zht", 2, "64_11_5", 62, "5"),
    ("zht", 2, "64_11_6", 62, "6"),
    ("zht", 2, "66_13_1", 63, "1"),
    ("zht", 2, "66_13_2", 63, "2"),
    ("zht", 2, "65_12", 64, "1"),
    ("zht", 2, "67_14", 65, "1"),
    ("zht", 2, "68_15", 66, "1"),
    ("zht", 3, "81_1_1", 67, "1"),
    ("zht", 3, "81_1_2", 67, "2"),
    ("zht", 3, "82_1_3", 68, "1"),
    ("zht", 3, "82_1_4", 68, "2"),
    ("zht", 3, "84_2_1", 69, "1"),
    ("zht", 3, "84_2_2", 69, "2"),
    ("zht", 3, "85_3", 70, "1"),  # Reordered before 85_4 (No.2) for logical sequence
    ("zht", 3, "85_4", 70, "2"),
    ("zht", 3, "125_5", 71, "1"),
    ("zht", 3, "126_6", 72, "1"),
    ("zht", 3, "74n", 74, "1"),
    ("zht", 3, "75_10n", 75, "1"),
    ("zht", 3, "79_33", 75, "2"),
    ("zht", 3, "69_16", 76, "1"),
    ("zht", 3, "70_17", 77, "1"),
    ("zht", 3, "77_14n", 77, "2"),
    ("zht", 3, "78_1n", 78, "1"),
    ("zht", 3, "71_19_1", 78, "2"),
    ("zht", 3, "71_19_2", 79, "1"),
    ("zht", 3, "72_20_1", 80, "1"),
    ("zht", 3, "72_20_2", 80, "2"),
    ("zht", 3, "73_21", 81, "1"),
    ("zht", 4, "73_22", 81, "2"),
    ("zht", 4, "74_23", 82, "1"),
    ("zht", 4, "74_24", 82, "2"),
    ("zht", 4, "75_25", 83, "1"),
    ("zht", 4, "75_26", 83, "2"),
    ("zht", 4, "76_27", 84, "1"),
    ("zht", 4, "77_28", 85, "1"),
    ("zht", 4, "77_29", 85, "2"),
    ("zht", 4, "78_30", 86, "1"),
    ("zht", 4, "79_32", 86, "2"),
    ("zht", 4, "80_34_1", 87, "1"),
    ("zht", 4, "80_34_2", 87, "2"),
    # --- gct (32 problems) ---
    ("gct", 1, "89_1", 88, "1"),
    ("gct", 1, "90_2_1", 89, "1"),
    ("gct", 1, "90_2_2", 89, "2"),
    ("gct", 1, "90_2_3", 89, "3"),
    ("gct", 1, "91_3_1", 90, "1"),
    ("gct", 1, "91_3_2", 90, "2"),
    ("gct", 1, "92_4_1", 91, "1"),
    ("gct", 1, "92_4_2", 91, "2"),
    ("gct", 1, "92_4_3", 91, "3"),
    ("gct", 1, "92_4_4", 91, "4"),
    ("gct", 1, "93_5", 92, "1"),
    ("gct", 1, "94_6", 93, "1"),
    ("gct", 1, "95_7_1", 94, "1"),
    ("gct", 1, "95_7_2", 94, "2"),
    ("gct", 1, "95_8", 94, "3"),
    ("gct", 1, "95n", 95, "1"),
    ("gct", 1, "97_10", 96, "1"),
    ("gct", 1, "98_11", 97, "1"),
    ("gct", 1, "99_12", 98, "1"),
    ("gct", 1, "100_1n", 100, "1"),
    ("gct", 1, "101_13", 100, "2"),
    ("gct", 1, "102_14", 101, "1"),
    ("gct", 1, "103_15_1", 102, "1"),
    ("gct", 2, "103_15_2", 102, "2"),
    ("gct", 2, "103_15_3", 102, "3"),
    ("gct", 2, "103n", 103, "1"),
    ("gct", 2, "105_18", 105, "1"),
    ("gct", 2, "107_19", 108, "1"),
    ("gct", 2, "111_21", 111, "1"),
    ("gct", 2, "115_22_1", 115, "1"),
    ("gct", 2, "115_22_2", 115, "2"),
    ("gct", 2, "115_22_4", 116, "2"),
    # --- other (3 problems) ---
    ("other", 1, "121_1", 122, "1"),
    ("other", 1, "122_2", 123, "1"),
    ("other", 1, "127_8", 124, "1"),
]

# Tab labels for the 7 wired multi-view engineering problems (verified against rendered tab button glyphs).
TAB_LABEL_OVERRIDES: dict[str, dict[str, str]] = {
    "105_18": {
        "star": "题目 a",
        "4s1": "题目 b",
        "4s2": "答案 a",
        "4s3": "答案 b",
        "4a1": "答案 K",
    },
    "107_19": {
        "star": "题目 a",
        "4s1": "题目 b",
        "4s2": "答案",
    },
    "111_21": {
        "star": "题目 a",
        "4s1": "题目 b",
        "4s2": "题目 c",
        "4s3": "题目 d",
        "4a": "题目 e",
        "4a1": "题目 f",
        "4a2": "答案",
        "4a3": "答案·主视图",
        "4a4": "答案·左视图",
    },
    "115_22_1": {
        "star": "题目",
        "4s1": "题目·主视图",
        "4s2": "题目·俯视图",
        "4s3": "题目·左视图",
        "4a": "答案",
    },
    "115_22_2": {
        "star": "题目",
        "4s1": "题目·主视图",
        "4s2": "题目·左视图",
        "4s3": "题目·俯视图",
        "4a": "答案 a",
        "4a1": "答案 b_1",
        "4a2": "答案 b_1·主视图",
        "4a3": "答案 b_1·俯视图",
        "4a4": "答案 b_1·左视图",
        "4a5": "答案 b_2",
        "4a6": "答案 b_2·主视图",
        "4a7": "答案 b_2·左视图",
        "4a8": "答案 b_9",
        "4a9": "答案 c_4",
        "4aA": "答案 c_11",
        "4aB": "答案 d",
    },
    "115_22_4": {
        "star": "题目",
        "4s1": "题目·主视图",
        "4s2": "题目·左视图",
        "4s3": "题目·俯视图",
        "4a": "答案 a_1",
        "4a1": "答案 a_1·主视图",
        "4a2": "答案 a_1·左视图",
        "4a3": "答案 a_1·俯视图",
        "4a4": "答案 a_2",
        "4a5": "答案 b_3",
        "4a6": "答案 b_6",
        "4a7": "答案 c",
    },
}

CHROME_BUTTON_NAMES = {
    "01-1",
    "01-2",
    "01-3",
    "02-1",
    "02-2",
    "02-3",
    "a-k",
    "a",
}


def read_tag(b: bytes) -> str:
    return b[::-1].decode("latin1", errors="replace")


class DirFile:
    """Minimal Macromedia Director 8.5 RIFX/XFIR Cast & Score reader."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.data = path.read_bytes()
        len1 = struct.unpack("<I", self.data[16:20])[0]
        imap = self.data[20 : 20 + len1]
        _, mmap_off = struct.unpack("<II", imap[:8])
        mlen = struct.unpack("<I", self.data[mmap_off + 4 : mmap_off + 8])[0]
        mbody = self.data[mmap_off + 8 : mmap_off + 8 + mlen]
        hdr_size, entry_size, _, used_cnt = struct.unpack("<HHII", mbody[:12])
        self.chunks: dict[int, tuple[str, bytes]] = {}
        self.by_tag: dict[str, list[tuple[int, bytes]]] = {}
        for i in range(used_cnt):
            rec = mbody[hdr_size + i * entry_size : hdr_size + (i + 1) * entry_size]
            tag = read_tag(rec[0:4])
            sz, off = struct.unpack("<II", rec[4:12])
            if tag not in ("free", "junk"):
                body = self.data[off + 8 : off + 8 + sz]
                self.chunks[i] = (tag, body)
                self.by_tag.setdefault(tag, []).append((i, body))

    def parse_key(self) -> dict[int, list[tuple[str, int]]]:
        _, body = self.by_tag["KEY*"][0]
        _, _, _, used = struct.unpack("<HHII", body[:12])
        links: dict[int, list[tuple[str, int]]] = {}
        for i in range(used):
            ch, pa, tb = struct.unpack("<II4s", body[12 + i * 12 : 24 + i * 12])
            links.setdefault(pa, []).append((read_tag(tb), ch))
        return links

    @staticmethod
    def parse_cast(body: bytes) -> tuple[int, list[bytes], bytes]:
        mtype, info_len, spec_len = struct.unpack(">III", body[:12])
        info = body[12 : 12 + info_len]
        spec = body[12 + info_len : 12 + info_len + spec_len]
        items: list[bytes] = []
        if len(info) >= 22:
            hdr = struct.unpack(">IIIIIH", info[:22])
            tbl_cnt = hdr[5]
            if 22 + (tbl_cnt + 1) * 4 <= len(info):
                offs = struct.unpack(f">{tbl_cnt + 1}I", info[22 : 22 + (tbl_cnt + 1) * 4])
                data_start = 22 + (tbl_cnt + 1) * 4
                for j in range(tbl_cnt):
                    items.append(info[data_start + offs[j] : data_start + offs[j + 1]])
        return mtype, items, spec

    @staticmethod
    def decode_pstr(b: bytes) -> str:
        if not b:
            return ""
        if len(b) >= 2 and b[0] == len(b) - 1:
            return b[1:].decode("gbk", errors="replace")
        if b.endswith(b"\x00"):
            if len(b) >= 2 and b[0] == len(b) - 2:
                return b[1:-1].decode("gbk", errors="replace")
            return b[:-1].decode("gbk", errors="replace")
        return b.decode("gbk", errors="replace")

    def get_internal_members(self) -> dict[int, dict[str, Any]]:
        lk = self.parse_key()
        if 66560 not in lk:
            _, b = self.by_tag["CAS*"][0]
            slots = [struct.unpack(">I", b[i : i + 4])[0] for i in range(0, len(b), 4)]
            return self._load_slots(slots, lk)
        for tag, cid in lk.get(66560, []):
            if tag == "CAS*":
                b = self.chunks[cid][1]
                slots = [struct.unpack(">I", b[i : i + 4])[0] for i in range(0, len(b), 4)]
                return self._load_slots(slots, lk)
        return {}

    def _load_slots(
        self, slots: list[int], lk: dict[int, list[tuple[str, int]]]
    ) -> dict[int, dict[str, Any]]:
        res: dict[int, dict[str, Any]] = {}
        for m, cid in enumerate(slots, 1):
            if cid and cid in self.chunks:
                mt, items, spec = self.parse_cast(self.chunks[cid][1])
                res[m] = {
                    "type": mt,
                    "spec": spec,
                    "name": self.decode_pstr(items[1]) if len(items) > 1 else "",
                    "ext": self.decode_pstr(items[3]) if len(items) > 3 else "",
                    "script": items[0].decode("gbk", errors="replace") if items and items[0] else "",
                    "chunks": dict(lk.get(cid, [])),
                }
        return res

    def parse_vwlb(self) -> dict[int, str]:
        if "VWLB" not in self.by_tag:
            return {}
        _, body = self.by_tag["VWLB"][0]
        cnt = struct.unpack(">H", body[:2])[0]
        offs = [struct.unpack(">HH", body[2 + 4 * k : 6 + 4 * k]) for k in range(cnt + 1)]
        sstart = 2 + 4 * (cnt + 1)
        return {
            offs[k][0]: body[sstart + offs[k][1] : sstart + offs[k + 1][1]].decode(
                "gbk", errors="replace"
            )
            for k in range(cnt)
        }

    def parse_vwsc(self) -> tuple[list[dict[int, bytes]], dict[int, list[tuple[int, int]]]]:
        _, vwsc = self.by_tag["VWSC"][0]
        _, _, _, _, cnt2, _ = struct.unpack(">IIIIII", vwsc[:24])
        offs = struct.unpack(f">{cnt2}I", vwsc[24 : 24 + cnt2 * 4])
        blob = vwsc[24 + cnt2 * 4 :]
        e0 = blob[offs[0] : offs[1]]
        _, hdr_sz, frame_cnt, _, chan_sz, max_ch, _ = struct.unpack(">IIIHHHH", e0[:20])
        pos = hdr_sz
        buf = bytearray(max_ch * chan_sz)
        frames: list[dict[int, bytes]] = []
        while pos + 2 <= len(e0) and len(frames) < frame_cnt:
            flen = struct.unpack(">H", e0[pos : pos + 2])[0]
            if flen < 2:
                end = pos + 2
            else:
                end = pos + flen
                p = pos + 2
                while p + 4 <= end:
                    dlen, doff = struct.unpack(">HH", e0[p : p + 4])
                    p += 4
                    buf[doff : doff + dlen] = e0[p : p + dlen]
                    p += dlen
            frames.append(
                {
                    ch: bytes(buf[ch * chan_sz : (ch + 1) * chan_sz])
                    for ch in range(max_ch)
                    if any(buf[ch * chan_sz : (ch + 1) * chan_sz])
                }
            )
            pos = end
        e1 = blob[offs[1] : offs[2]]
        span_cnt = struct.unpack(">I", e1[:4])[0]
        span_ids = struct.unpack(f">{span_cnt}I", e1[4 : 4 + 4 * span_cnt])
        spans: dict[int, list[tuple[int, int]]] = {}
        for sid in span_ids:
            beh_b = blob[offs[sid + 1] : offs[sid + 2]]
            spans[sid] = [struct.unpack(">HHI", beh_b[k : k + 8])[:2] for k in range(0, len(beh_b), 8)]
        return frames, spans


def unpack_packbits(src: bytes, expected_len: int) -> bytes:
    """Decode Director PackBits stream up to expected_len bytes."""
    if len(src) == expected_len:
        return src
    out = bytearray()
    i = 0
    n = len(src)
    while i < n and len(out) < expected_len:
        c = src[i]
        i += 1
        if c < 128:
            cnt = c + 1
            out.extend(src[i : i + cnt])
            i += cnt
        elif c > 128:
            out.extend([src[i]] * (257 - c))
            i += 1
    if len(out) < expected_len:
        out.extend(b"\x00" * (expected_len - len(out)))
    return bytes(out[:expected_len])


def decode_bitd_rgba(spec: bytes, bitd: bytes, alfa: bytes | None = None) -> Image.Image:
    """Decode 16-bit RGB555 or 32-bit xRGB BITD chunk (+ optional ALFA) into RGBA PIL Image."""
    rb_raw, top, left, bottom, right = struct.unpack(">Hhhhh", spec[:10])
    row_bytes = rb_raw & 0x3FFF
    h, w = bottom - top, right - left
    depth = spec[23] if len(spec) >= 24 else 8
    raw = unpack_packbits(bitd, row_bytes * h)
    arr_raw = np.frombuffer(raw, dtype=np.uint8).reshape((h, row_bytes))

    if depth == 32:
        pw = row_bytes // 4
        r = arr_raw[:, pw : pw + w]
        g = arr_raw[:, 2 * pw : 2 * pw + w]
        b = arr_raw[:, 3 * pw : 3 * pw + w]
        rgb = np.stack([r, g, b], axis=-1)
    elif depth == 16:
        pw = row_bytes // 2
        hi = arr_raw[:, :w].astype(np.uint16)
        lo = arr_raw[:, pw : pw + w].astype(np.uint16)
        v = (hi << 8) | lo
        r5 = (v >> 10) & 0x1F
        g5 = (v >> 5) & 0x1F
        b5 = v & 0x1F
        r = ((r5 << 3) | (r5 >> 2)).astype(np.uint8)
        g = ((g5 << 3) | (g5 >> 2)).astype(np.uint8)
        b = ((b5 << 3) | (b5 >> 2)).astype(np.uint8)
        rgb = np.stack([r, g, b], axis=-1)
    else:
        raise ValueError(f"Unsupported BITD depth={depth}")

    if alfa is not None:
        a_raw = unpack_packbits(alfa, w * h)
        alpha = np.frombuffer(a_raw, dtype=np.uint8).reshape((h, w))
    else:
        alpha = np.full((h, w), 255, dtype=np.uint8)

    rgba = np.dstack([rgb, alpha])
    return Image.fromarray(rgba, mode="RGBA")


def decode_xmed_text(xb: bytes) -> str:
    """Extract UTF-8 string from Director XMED 0002 rich text chunk."""
    pos = xb.find(b"0002")
    if pos == -1:
        return ""
    sec_len = int(xb[pos + 4 : pos + 12], 16)
    sec = xb[pos + 20 : pos + 20 + sec_len]
    comma = sec.find(b",")
    if comma == -1:
        return ""
    hp = re.search(rb"([0-9A-Fa-f]+)$", sec[:comma])
    if not hp:
        return ""
    tlen = int(hp.group(1), 16)
    raw = sec[comma + 1 : comma + 1 + tlen]
    txt = raw.decode("gbk", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip() for line in txt.split("\n")]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


def apply_ink(sprite_img: Image.Image, ink: int) -> Image.Image:
    """Apply Director sprite ink onto an RGBA image before alpha compositing."""
    arr = np.array(sprite_img, dtype=np.uint8)
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    is_white = (r >= 252) & (g >= 252) & (b >= 252)

    if ink in (1, 36):  # Transparent / BgTransparent -> white pixels transparent
        arr[:, :, 3] = np.where(is_white, 0, a)
        return Image.fromarray(arr, mode="RGBA")

    if ink == 8:  # Matte -> flood-fill outer contiguous white from borders
        h, w = is_white.shape
        visited = np.zeros((h, w), dtype=bool)
        q: deque[tuple[int, int]] = deque()
        for x in range(w):
            if is_white[0, x]:
                visited[0, x] = True
                q.append((0, x))
            if h > 1 and is_white[h - 1, x]:
                visited[h - 1, x] = True
                q.append((h - 1, x))
        for y in range(1, h - 1):
            if is_white[y, 0]:
                visited[y, 0] = True
                q.append((y, 0))
            if w > 1 and is_white[y, w - 1]:
                visited[y, w - 1] = True
                q.append((y, w - 1))
        while q:
            cy, cx = q.popleft()
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_white[ny, nx]:
                    visited[ny, nx] = True
                    q.append((ny, nx))
        arr[:, :, 3] = np.where(visited, 0, a)
        return Image.fromarray(arr, mode="RGBA")

    if ink == 4:  # NotCopy (white cutout mask wedge in jieP46_60_2 -> make dark mask white, light transparent)
        is_dark = (r < 128) & (g < 128) & (b < 128)
        out = np.zeros_like(arr)
        out[is_dark] = [255, 255, 255, 255]
        return Image.fromarray(out, mode="RGBA")

    # Copy (0) or fallback
    return sprite_img


def is_legacy_chrome(
    mem: dict[str, Any],
    top: int,
    h: int,
    behs: list[str],
    is_tabbed_file: bool,
) -> bool:
    """Return True if sprite is legacy Director navigation UI chrome to strip."""
    nm = mem["name"].strip().lower()
    if nm in CHROME_BUTTON_NAMES or nm.startswith(("s_", "a_")):
        return True
    if any(b.strip() for b in behs):
        return True
    # Unnamed bottom bar plate behind prev/pause/next or tab bar (top=391, h=32..65)
    if nm == "" and top >= 388 and h <= 65:
        return True
    if is_tabbed_file and nm == "" and top >= 395 and h <= 70:
        return True
    return False


def extract_problem_pair(
    th: str,
    sub_members: dict[str, dict[str, Any]],
    sub_df: DirFile,
    disk_ans_map: dict[str, str],
) -> tuple[str, str]:
    """Extract subject & answer images into flat assets/subjects & assets/answers."""
    subj_dir = ASSETS_ROOT / "subjects"
    ans_dir = ASSETS_ROOT / "answers"
    subj_dir.mkdir(parents=True, exist_ok=True)
    ans_dir.mkdir(parents=True, exist_ok=True)

    def write_side(side_key: str, target_dir: Path, folder_rel: str) -> str:
        m = sub_members.get(side_key.lower())
        if m is not None:
            ch = m["chunks"]
            if "ediM" in ch:
                raw = sub_df.chunks[ch["ediM"]][1]
                out_name = f"{th}.jpg"
                (target_dir / out_name).write_bytes(raw)
                return f"assets/{folder_rel}/{out_name}"
            if "BITD" in ch:
                alfa = sub_df.chunks[ch["ALFA"]][1] if "ALFA" in ch else None
                im = decode_bitd_rgba(m["spec"], sub_df.chunks[ch["BITD"]][1], alfa)
                bg = Image.new("RGB", im.size, (255, 255, 255))
                bg.paste(im, mask=im.split()[3])
                out_name = f"{th}.png"
                bg.save(target_dir / out_name, optimize=True)
                return f"assets/{folder_rel}/{out_name}"
            if m["ext"]:
                ext_base = os.path.basename(m["ext"].replace("\\", "/")).lower()
                disk_file = disk_ans_map.get(ext_base)
                if disk_file:
                    src = SOURCE_ROOT / "AnsSubTu" / disk_file
                    ext_suffix = src.suffix.lower() or ".jpg"
                    out_name = f"{th}{ext_suffix}"
                    shutil.copy2(src, target_dir / out_name)
                    return f"assets/{folder_rel}/{out_name}"
        # Direct filename fallback
        for ext_cand in (f"{side_key}.jpg", f"{side_key}.png"):
            disk_file = disk_ans_map.get(ext_cand.lower())
            if disk_file:
                src = SOURCE_ROOT / "AnsSubTu" / disk_file
                out_name = f"{th}{src.suffix.lower()}"
                shutil.copy2(src, target_dir / out_name)
                return f"assets/{folder_rel}/{out_name}"
        raise FileNotFoundError(f"Missing {side_key} for {th}")

    subj = write_side(f"P{th}s", subj_dir, "subjects")
    ans = write_side(f"P{th}a", ans_dir, "answers")
    return subj, ans


def extract_jieti_steps(
    th: str,
    txt_map: dict[str, str],
) -> tuple[str, list[dict[str, Any]]]:
    """Composite and extract jieti/*.dir step or tab images + XMED notes."""
    jf = SOURCE_ROOT / "jieti" / f"jieP{th}.dir"
    df = DirFile(jf)
    members = df.get_internal_members()
    labels = df.parse_vwlb()
    frames, spans = df.parse_vwsc()

    is_tabbed = th in TAB_LABEL_OVERRIDES
    tab_overrides = TAB_LABEL_OVERRIDES.get(th, {})

    # Collect wait frames + labeled frames
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

    # Decode member bitmaps cache per .dir file
    bmp_cache: dict[int, Image.Image] = {}
    ink_cache: dict[tuple[int, int, tuple[int, int], int], Image.Image] = {}
    xmed_cache: dict[int, str] = {}

    steps_raw: list[dict[str, Any]] = []
    for fidx in key_frames:
        lbl = labels.get(fidx, "")
        if is_tabbed and lbl not in tab_overrides:
            continue
        fr = frames[fidx - 1]
        canvas = Image.new("RGBA", (STAGE_W, STAGE_H), (255, 255, 255, 255))
        step_notes: list[str] = []

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

            if mem["type"] == 15 and "XMED" in mem["chunks"]:
                if cmem not in xmed_cache:
                    xmed_cache[cmem] = decode_xmed_text(df.chunks[mem["chunks"]["XMED"]][1])
                nt = xmed_cache[cmem]
                if nt and nt not in step_notes:
                    step_notes.append(nt)
                continue

            if mem["type"] != 1 or "BITD" not in mem["chunks"]:
                continue

            py, px, h, w = struct.unpack(">hhhh", rec[12:20])
            regY, regX = struct.unpack(">hh", mem["spec"][18:22])
            ink = rec[1] & 0x3F
            sid = struct.unpack(">H", rec[10:12])[0]
            behs = [members.get(bm, {}).get("script", "") for _, bm in spans.get(sid, [])]

            left = px - regX
            top = py - regY
            if is_legacy_chrome(mem, top, h, behs, is_tabbed):
                continue

            if cmem not in bmp_cache:
                alfa = df.chunks[mem["chunks"]["ALFA"]][1] if "ALFA" in mem["chunks"] else None
                bmp_cache[cmem] = decode_bitd_rgba(
                    mem["spec"], df.chunks[mem["chunks"]["BITD"]][1], alfa
                )
            base_sp = bmp_cache[cmem]
            target_sz = (w, h) if (w > 0 and h > 0) else base_sp.size
            rot_centideg = struct.unpack(">i", rec[28:32])[0] if len(rec) >= 32 else 0
            rot_key = rot_centideg if (ink == 4 and abs(rot_centideg) in (9000, 18000, 27000)) else 0
            cache_k = (cmem, ink, target_sz, rot_key)
            if cache_k not in ink_cache:
                sp_img = base_sp
                if target_sz != sp_img.size:
                    sp_img = sp_img.resize(target_sz, Image.Resampling.BILINEAR)
                if rot_key:
                    sp_img = sp_img.rotate(-rot_key / 100.0, expand=False)
                ink_cache[cache_k] = apply_ink(sp_img, ink)
            if rot_key:
                left = px - target_sz[0] // 2
                top = py - target_sz[1] // 2
            canvas.alpha_composite(ink_cache[cache_k], dest=(left, top))

        rgb_img = canvas.convert("RGB")
        # Normalize near-white edges if needed, compute pixel hash for dedup
        px_hash = hashlib.md5(rgb_img.tobytes()).hexdigest()
        note_str = "\n".join(step_notes).strip()

        # Keep first frame, or whenever visual image changes OR new XMED note OR named tab label
        if steps_raw:
            prev = steps_raw[-1]
            if not is_tabbed and px_hash == prev["hash"] and note_str == prev["note"]:
                continue

        steps_raw.append(
            {
                "frame": fidx,
                "label": lbl,
                "image": rgb_img,
                "note": note_str,
                "hash": px_hash,
            }
        )

    steps_dir = ASSETS_ROOT / "steps"
    steps_dir.mkdir(parents=True, exist_ok=True)
    steps_meta: list[dict[str, Any]] = []
    for idx, st in enumerate(steps_raw):
        fname = f"{th}_{idx + 1:02d}.png"
        st["image"].save(steps_dir / fname, optimize=True)
        if is_tabbed:
            title = tab_overrides.get(st["label"], st["label"] or f"视图 {idx + 1}")
        elif len(steps_raw) <= 2:
            title = "原题题面" if idx == 0 else "完整答案"
        elif idx == 0:
            title = "原题题面"
        elif idx == len(steps_raw) - 1:
            title = "最终答案"
        else:
            title = f"第 {idx} 步"
        steps_meta.append(
            {
                "index": idx + 1,
                "title": title,
                "image": f"assets/steps/{fname}",
                "note": st["note"],
            }
        )

    mode = "tabbed" if is_tabbed else ("two_state" if len(steps_meta) <= 2 else "stepped")
    return mode, steps_meta


def transcode_videos(video_tasks: list[tuple[str, Path, Path]]) -> dict[str, dict[str, Any]]:
    """Transcode legacy AVI animations to H.264 MP4 using ffmpeg."""
    if not FFMPEG_BIN.exists():
        raise FileNotFoundError(f"ffmpeg not found at {FFMPEG_BIN}")
    results: dict[str, dict[str, Any]] = {}

    def convert_one(th: str, src: Path, dst: Path) -> tuple[str, dict[str, Any]]:
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists() or dst.stat().st_size == 0:
            if dst.exists():
                dst.unlink()
            cmd = [
                str(FFMPEG_BIN),
                "-y",
                "-i",
                str(src),
                "-vf",
                "pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:black",
                "-c:v",
                "libx264",
                "-profile:v",
                "main",
                "-level",
                "3.1",
                "-pix_fmt",
                "yuv420p",
                "-crf",
                "20",
                "-preset",
                "medium",
                "-movflags",
                "+faststart",
                "-an",
                str(dst),
                "-loglevel",
                "error",
            ]
            subprocess.run(cmd, check=True)
        return th, {
            "asset": f"assets/videos/{dst.name}",
            "sourceAvi": src.name,
            "sizeBytes": dst.stat().st_size,
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for th, meta in pool.map(lambda t: convert_one(*t), video_tasks):
            results[th] = meta
    return results


def main() -> None:
    for sub in ("data", "problems", "subjects", "answers", "steps"):
        target = ASSETS_ROOT / sub
        if target.exists():
            shutil.rmtree(target)
        if sub != "problems":
            target.mkdir(parents=True, exist_ok=True)
    (ASSETS_ROOT / "videos").mkdir(parents=True, exist_ok=True)

    # Load shared casts
    sub_df = DirFile(SOURCE_ROOT / "SubAnsTu.cst")
    sub_members = {v["name"].lower(): v for v in sub_df.get_internal_members().values() if v["name"]}

    txt_df = DirFile(SOURCE_ROOT / "text.cst")
    txt_map: dict[str, str] = {}
    for v in txt_df.get_internal_members().values():
        if v["name"] and "XMED" in v["chunks"]:
            txt_map[v["name"].lower()] = decode_xmed_text(txt_df.chunks[v["chunks"]["XMED"]][1])

    avi_df = DirFile(SOURCE_ROOT / "avi.cst")
    avi_map: dict[str, Path] = {}
    disk_avi = {f.lower(): f for f in os.listdir(SOURCE_ROOT / "avi")}
    for v in avi_df.get_internal_members().values():
        if v["name"] and v["ext"]:
            base = os.path.basename(v["ext"].replace("\\", "/")).lower()
            if base in disk_avi:
                avi_map[v["name"].lower()] = SOURCE_ROOT / "avi" / disk_avi[base]
    # Add unregistered on-disk animation for 111_21
    if "p111_21.avi" in disk_avi:
        avi_map.setdefault("ap111_21", SOURCE_ROOT / "avi" / disk_avi["p111_21.avi"])

    disk_ans_map = {f.lower(): f for f in os.listdir(SOURCE_ROOT / "AnsSubTu")}

    assert len(VERIFIED_PROBLEMS) == 177, f"Expected 177 problems, got {len(VERIFIED_PROBLEMS)}"
    assert len({p[2] for p in VERIFIED_PROBLEMS}) == 177, "Duplicate tihao detected"

    problems_json: list[dict[str, Any]] = []
    video_tasks: list[tuple[str, Path, Path]] = []

    chap_counters: dict[str, int] = {}
    for chap_id, grp, th, page, no_str in VERIFIED_PROBLEMS:
        chap_counters[chap_id] = chap_counters.get(chap_id, 0) + 1
        subj_asset, ans_asset = extract_problem_pair(th, sub_members, sub_df, disk_ans_map)
        mode, steps_meta = extract_jieti_steps(th, txt_map)
        stmt = txt_map.get(f"tp{th}".lower(), "")

        avi_path = avi_map.get(f"ap{th}".lower())
        if avi_path is not None:
            video_tasks.append((th, avi_path, ASSETS_ROOT / "videos" / f"{th}.mp4"))

        problems_json.append(
            {
                "id": th,
                "chapterId": chap_id,
                "groupIndex": grp,
                "orderInChapter": chap_counters[chap_id],
                "page": page,
                "no": no_str,
                "displayLabel": f"第 {page} 页 No.{no_str} 题",
                "statement": stmt,
                "subjectImage": subj_asset,
                "answerImage": ans_asset,
                "jietiMode": mode,
                "steps": steps_meta,
                "video": None,
            }
        )

    print(f"Transcoding {len(video_tasks)} videos via ffmpeg...")
    video_meta = transcode_videos(video_tasks)
    for p in problems_json:
        if p["id"] in video_meta:
            p["video"] = video_meta[p["id"]]

    curriculum = {
        "schemaVersion": 1,
        "problemCount": len(problems_json),
        "videoCount": len(video_meta),
        "chapters": CHAPTERS,
        "problems": problems_json,
    }
    (ASSETS_ROOT / "data" / "curriculum.json").write_text(
        json.dumps(curriculum, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    # Generate spot-check sheet for tricky jieti + BITD cases
    SCRATCH_VERIFY.mkdir(parents=True, exist_ok=True)
    spot_ids = ["13_1", "46_60_2", "52_1n", "64_11_3", "85_3", "89_1", "100_1n", "111_21"]
    tiles: list[tuple[str, Image.Image]] = []
    for pid in spot_ids:
        p = next(x for x in problems_json if x["id"] == pid)
        s_im = Image.open(PROJECT_ROOT / p["subjectImage"]).convert("RGB")
        st_im = Image.open(PROJECT_ROOT / p["steps"][min(len(p["steps"]) - 1, max(0, len(p["steps"]) // 2))]["image"]).convert("RGB")
        a_im = Image.open(PROJECT_ROOT / p["answerImage"]).convert("RGB")
        tiles.append((f"{pid} subj", s_im))
        tiles.append((f"{pid} mid({len(p['steps'])}st)", st_im))
        tiles.append((f"{pid} ans", a_im))

    tw, th_px = 270, 225
    sheet = Image.new("RGB", (3 * tw + 40, len(spot_ids) * (th_px + 28) + 20), (242, 244, 248))
    draw = ImageDraw.Draw(sheet)
    for r_idx in range(len(spot_ids)):
        for c_idx in range(3):
            lbl, im = tiles[r_idx * 3 + c_idx]
            x0 = 10 + c_idx * (tw + 10)
            y0 = 10 + r_idx * (th_px + 28)
            sheet.paste(im.resize((tw, th_px)), (x0, y0 + 18))
            draw.text((x0 + 4, y0 + 2), lbl, fill=(20, 20, 20))
    spot_path = SCRATCH_VERIFY / "spot_check.png"
    sheet.save(spot_path)

    total_bytes = sum(f.stat().st_size for f in ASSETS_ROOT.rglob("*") if f.is_file())
    print(f"Done! 177 problems, {len(video_meta)} videos. Assets size: {total_bytes / (1024*1024):.2f} MB")
    print(f"Spot-check saved to: {spot_path}")


if __name__ == "__main__":
    main()
