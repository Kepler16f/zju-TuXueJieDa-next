#!/usr/bin/env python3
"""dump hvigor 的 DecipherUtil（密码解密逻辑）与 SDK 中的加密相关工具。"""
from __future__ import annotations

import os
import sys

PLUGIN = (
    "/home/runner/ohos-sdk/command-line-tools/hvigor/hvigor-ohos-plugin"
)


def dump_file(path: str, label: str) -> None:
    print(f"=== {label} ===")
    if not os.path.isfile(path):
        print("(missing)")
        print()
        return
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    sys.stdout.write(text[:6000])
    print()
    print()


def main() -> None:
    # 1) 找 decipher util
    for root, _dirs, files in os.walk(PLUGIN):
        for f in files:
            if "decipher" in f.lower() or "encrypt" in f.lower():
                dump_file(os.path.join(root, f), os.path.relpath(os.path.join(root, f), PLUGIN))

    # 2) SDK 里是否有密码加密工具 / 加密标记
    print("=== grep encrypted-password marker (0000001B) in SDK ===")
    os.system("grep -rl '0000001B' /home/runner/ohos-sdk 2>/dev/null | head -10")
    print()
    print("=== grep for password encrypt tooling ===")
    os.system("grep -rln 'encryptPwd\\|encryptPassword\\|EncryptUtil' /home/runner/ohos-sdk 2>/dev/null | head -10")
    print()
    print("=== sign task: material / fd handling ===")
    os.system(
        "grep -rn 'signing material\\|material fd\\|addCalledJarFile\\|getSigningConfigInputFiles' "
        f"{PLUGIN}/src/tasks/sign 2>/dev/null | head -20"
    )


if __name__ == "__main__":
    main()
