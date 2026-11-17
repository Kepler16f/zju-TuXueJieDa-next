#!/usr/bin/env python3
"""dump hvigor 签名任务源码里与 material/profile 路径解析相关的片段。"""
from __future__ import annotations

import os
import re
import sys

PLUGIN = (
    "/home/runner/ohos-sdk/command-line-tools/hvigor/hvigor-ohos-plugin"
)
SIGN_DIR = os.path.join(PLUGIN, "src/tasks/sign")


def main() -> None:
    print("=== files under src/tasks/sign ===")
    for root, _dirs, files in os.walk(SIGN_DIR):
        for f in sorted(files):
            print(" ", os.path.relpath(os.path.join(root, f), PLUGIN))

    print()
    print("=== lines mentioning material/profile/certpath (with context) ===")
    pat = re.compile(r"material|profile|certpath|storefile|keyalias", re.I)
    for root, _dirs, files in os.walk(SIGN_DIR):
        for f in sorted(files):
            if not f.endswith((".js", ".ts", ".d.ts")):
                continue
            p = os.path.join(root, f)
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    lines = fh.readlines()
            except OSError:
                continue
            printed = set()
            for i, line in enumerate(lines):
                if not pat.search(line):
                    continue
                lo = max(0, i - 5)
                hi = min(len(lines), i + 6)
                key = (lo, hi)
                if key in printed:
                    continue
                printed.add(key)
                print(f"--- {os.path.relpath(p, PLUGIN)}:{i + 1} ---")
                for j in range(lo, hi):
                    sys.stdout.write(f"  {j + 1}: {lines[j]}")
                print()


if __name__ == "__main__":
    main()
