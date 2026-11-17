#!/usr/bin/env python3
"""打印 hvigor 签名配置 schema（signingConfigs 段）与签名命令构建器源码。

用于排查 hvigor 的签名物料路径约定（如 profile / certpath 如何解析）。
"""
from __future__ import annotations

import json
import os
import sys

PLUGIN = (
    "/home/runner/ohos-sdk/command-line-tools/hvigor/hvigor-ohos-plugin"
)


def dump_schema() -> None:
    path = os.path.join(
        PLUGIN, "res/schemas/ohos-project-build-profile-schema.json"
    )
    if not os.path.isfile(path):
        print(f"(schema missing: {path})")
        return
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    def walk(node, path=""):
        if isinstance(node, dict):
            if "signingConfigs" in node:
                print("PATH:", path)
                print(json.dumps(node["signingConfigs"], ensure_ascii=False, indent=2)[:4000])
            for k, v in node.items():
                walk(v, f"{path}/{k}")
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{path}[{i}]")

    walk(data)


def dump_sources() -> None:
    base = os.path.join(PLUGIN, "src/tasks/sign")
    for rel in (
        "command-builder-impl/common-sign-command-builder.js",
        "command-builder-impl/hap-sign-command-builder.js",
        "sign-util.d.ts",
    ):
        p = os.path.join(base, rel)
        print(f"=== {rel} ===")
        if not os.path.isfile(p):
            print("(missing)")
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        for i, line in enumerate(lines, 1):
            low = line.lower()
            if any(k in low for k in ("certpath", "profile", "material", "storefile", "keyalias")):
                lo = max(1, i - 4)
                print(f"--- around line {i} ---")
                for j in range(lo - 1, min(len(lines), i + 4)):
                    sys.stdout.write(f"{j + 1}: {lines[j]}")
                print()


if __name__ == "__main__":
    dump_schema()
    print()
    dump_sources()
