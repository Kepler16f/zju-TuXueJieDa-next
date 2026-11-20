#!/usr/bin/env python3
"""Configure HarmonyOS module.json5 for phone, tablet, and 2in1/PC devices.

Per Huawei HarmonyOS official specification (Stage model):
- "phone": mobile phones
- "tablet": tablets
- "2in1": 2-in-1 and PC desktop devices (PC & 2in1 share the "2in1" enum)
- Ability "supportWindowMode": ["fullscreen", "split", "floating"]
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys

TARGET_DEVICE_TYPES = ["phone", "tablet", "2in1"]
TARGET_WINDOW_MODES = ["fullscreen", "split", "floating"]


def strip_json5(text: str) -> str:
    """Strip JSON5 comments and trailing commas outside string literals."""
    out: list[str] = []
    i = 0
    n = len(text)
    in_str: str | None = None
    while i < n:
        ch = text[i]
        if in_str is not None:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == in_str:
                in_str = None
            i += 1
            continue
        if ch in ('"', "'"):
            in_str = ch
            out.append(ch)
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] not in ("\n", "\r"):
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    cleaned = "".join(out)
    return re.sub(r",(\s*[}\]])", r"\1", cleaned)


def load_json5(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    return json.loads(strip_json5(raw))


def save_json(path: str, data: dict) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def patch_entry_module(root: str = ".") -> None:
    module_path = os.path.join(root, "ohos", "entry", "src", "main", "module.json5")
    if not os.path.isfile(module_path):
        print(f"[warn] missing {module_path}")
        return

    data = load_json5(module_path)
    mod = data.setdefault("module", {})
    mod["deviceTypes"] = list(TARGET_DEVICE_TYPES)

    for ability in mod.get("abilities", []):
        if ability.get("name") == "EntryAbility":
            ability["supportWindowMode"] = list(TARGET_WINDOW_MODES)

    save_json(module_path, data)
    print(f"deviceTypes -> {mod['deviceTypes']} in {module_path}")

    bp_path = os.path.join(root, "ohos", "entry", "build-profile.json5")
    if os.path.isfile(bp_path):
        bp = load_json5(bp_path)
        changed = False
        for target in bp.get("targets", []):
            cfg = target.get("config", {})
            if "deviceType" in cfg:
                cfg["deviceType"] = list(TARGET_DEVICE_TYPES)
                changed = True
        if changed:
            save_json(bp_path, bp)
            print(f"build-profile deviceType -> {TARGET_DEVICE_TYPES} in {bp_path}")


def patch_plugin_hars(root: str = ".") -> None:
    patterns = [
        os.path.join(root, "ohos", ".symlinks", "plugins", "*", "ohos", "src", "main", "module.json5"),
        os.path.join(root, "ohos", ".symlinks", "plugins", "*", "src", "main", "module.json5"),
    ]
    seen: set[str] = set()
    for pat in patterns:
        for path in sorted(glob.glob(pat)):
            real = os.path.realpath(path)
            if real in seen:
                continue
            seen.add(real)
            try:
                data = load_json5(real)
            except Exception as exc:
                print(f"[warn] failed to parse {path}: {exc}")
                continue
            mod = data.get("module", {})
            existing = list(mod.get("deviceTypes", []))
            updated = list(existing)
            for dt in TARGET_DEVICE_TYPES:
                if dt not in updated:
                    updated.append(dt)
            if updated != existing:
                mod["deviceTypes"] = updated
                save_json(real, data)
                print(f"plugin HAR deviceTypes -> {updated} in {path}")


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    root = sys.argv[2] if len(sys.argv) > 2 else "."
    if mode in ("entry", "all"):
        patch_entry_module(root)
    if mode in ("plugins", "all"):
        patch_plugin_hars(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
