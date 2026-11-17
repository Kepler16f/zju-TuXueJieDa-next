#!/usr/bin/env python3
"""dump hvigor 的 build-option-path-info 实现（getSignConfigPath 等路径计算）。"""
from __future__ import annotations

import os
import sys

PLUGIN = (
    "/home/runner/ohos-sdk/command-line-tools/hvigor/hvigor-ohos-plugin"
)


def main() -> None:
    hits = []
    for root, _dirs, files in os.walk(PLUGIN):
        for f in files:
            if f.endswith((".js", ".ts")) and ("path" in f.lower() or "option" in f.lower()):
                p = os.path.join(root, f)
                try:
                    with open(p, encoding="utf-8", errors="replace") as fh:
                        text = fh.read()
                except OSError:
                    continue
                if "getSignConfigPath" in text or "signing" in text.lower():
                    hits.append((p, text))

    print(f"=== candidate files: {len(hits)} ===")
    for p, text in hits[:6]:
        print("---", os.path.relpath(p, PLUGIN), "---")
        idx = text.find("getSignConfigPath")
        if idx < 0:
            idx = text.lower().find("signing")
        lo = max(0, idx - 800)
        sys.stdout.write(text[lo:idx + 1800])
        print()
        print()


if __name__ == "__main__":
    main()
