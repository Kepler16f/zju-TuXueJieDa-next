#!/usr/bin/env python3
"""打印 Flutter-ohos 模板原生的宿主工程规格（供 CI 自检）。

用法：python3 scripts/dump_ohos_spec.py [项目根]
在 flutter create --platforms ohos 之后、setup_ohos.sh 之前运行。
"""
import glob
import json
import os
import struct
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."


def show_json5(path: str, limit: int = 40) -> None:
    print(f"=== {path} ===")
    if not os.path.isfile(path):
        print("(missing)")
        return
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f):
            if i >= limit:
                print("...")
                break
            print(line.rstrip())
    print()


show_json5(os.path.join(root, "ohos/AppScope/app.json5"))
show_json5(os.path.join(root, "ohos/entry/src/main/module.json5"))

print("=== media icons (original sizes) ===")
dirs = sorted(
    glob.glob(os.path.join(root, "ohos/entry/src/main/resources/*/media"))
    + glob.glob(os.path.join(root, "ohos/AppScope/resources/*/media"))
)
for d in dirs:
    if not os.path.isdir(d):
        continue
    for fn in sorted(os.listdir(d)):
        if not fn.lower().endswith(".png"):
            continue
        p = os.path.join(d, fn)
        with open(p, "rb") as f:
            head = f.read(32)
        try:
            w, h = struct.unpack(">II", head[16:24])
        except Exception:
            w = h = -1
        print(f"{p}: {w}x{h} ({os.path.getsize(p)}B)")
