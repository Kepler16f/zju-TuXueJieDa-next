#!/usr/bin/env python3
"""给 pack.info 注入 hapList 字段（AppGallery 解析 .app 时靠它定位包内 HAP）。

hvigor/hap-sign-tool 生成的 pack.info 没有 hapList，AGC 会报 996 解析失败。
用法：python3 scripts/patch_pack_info.py <pack.info 路径> [hap 文件名 ...]
"""
from __future__ import annotations

import json
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    hap_list = sys.argv[2:] or ["entry-default.hap"]
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data["hapList"] = hap_list
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"hapList -> {hap_list}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
