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


def json5_to_json(text: str) -> str:
    """Convert JSON5 (comments, single quotes, unquoted keys, trailing commas) to JSON."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        # Line comment
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] not in ("\n", "\r"):
                i += 1
            continue
        # Block comment
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        # Double-quoted string
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(text[i:j])
            i = j
            continue
        # Single-quoted string -> double-quoted JSON string
        if ch == "'":
            j = i + 1
            buf: list[str] = ['"']
            while j < n:
                c = text[j]
                if c == "\\" and j + 1 < n:
                    nxt = text[j + 1]
                    if nxt == "'":
                        buf.append("'")
                    elif nxt == '"':
                        buf.append('\\"')
                    else:
                        buf.append(c)
                        buf.append(nxt)
                    j += 2
                    continue
                if c == "'":
                    j += 1
                    break
                if c == '"':
                    buf.append('\\"')
                else:
                    buf.append(c)
                j += 1
            buf.append('"')
            out.append("".join(buf))
            i = j
            continue
        # Unquoted identifier: quote if it's an object key (followed by whitespace + ':')
        if ch.isalpha() or ch in ("_", "$"):
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] in ("_", "$", "-")):
                j += 1
            ident = text[i:j]
            k = j
            while k < n and text[k] in (" ", "\t", "\r", "\n"):
                k += 1
            if k < n and text[k] == ":" and ident not in ("true", "false", "null"):
                out.append(f'"{ident}"')
            else:
                out.append(ident)
            i = j
            continue
        out.append(ch)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def load_json5(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    return json.loads(json5_to_json(raw))


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
        with open(bp_path, encoding="utf-8") as f:
            raw_bp = f.read()
        if "deviceType" in raw_bp:
            bp = json.loads(json5_to_json(raw_bp))
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
