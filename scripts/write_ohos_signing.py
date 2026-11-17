#!/usr/bin/env python3
"""把发布签名配置写入 ohos/build-profile.json5（hvigor 原生签名）。

用法：
    python3 scripts/write_ohos_signing.py \
        --store signing/ohos_release.p12 \
        --cert signing/chain.cer \
        --profile signing/app.p7b \
        --alias tuxuejieda \
        --password "$KS_PASS"

模板默认 signingConfigs 为空数组（产物即 unsigned），这里新增一个与
product.signingConfig 同名（default）的配置，hvigor 便会在 build hap/app
时用发布证书 + 发布 Profile 正规签名，不再需要手工 zip 打包。
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re


def strip_json5(text: str) -> str:
    """去掉注释与尾逗号，便于解析。"""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile-json", default="ohos/build-profile.json5")
    ap.add_argument("--store", required=True)
    ap.add_argument("--cert", required=True)
    ap.add_argument("--profile", required=True)
    ap.add_argument("--alias", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--compatible", default="5.0.5(17)")
    args = ap.parse_args()

    with io.open(args.profile_json, encoding="utf-8") as f:
        data = json.loads(strip_json5(f.read()))

    app = data.setdefault("app", {})
    app["signingConfigs"] = [
        {
            "name": "default",
            "type": "default",
            "material": {
                "storeFile": os.path.abspath(args.store),
                "storePassword": args.password,
                "keyAlias": args.alias,
                "keyPassword": args.password,
                "signAlg": "SHA256withECDSA",
                "storeType": "p12",
                "profile": {
                    "cert": os.path.abspath(args.cert),
                    "store": os.path.abspath(args.profile),
                    "name": "release",
                    "signAlg": "SHA256withECDSA",
                    "compatibleVersion": args.compatible,
                    "profileType": "release",
                },
            },
        }
    ]
    for product in app.get("products", []):
        product["signingConfig"] = "default"

    with io.open(args.profile_json, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2))
        f.write("\n")
    print(f"signingConfig 'default' written to {args.profile_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
