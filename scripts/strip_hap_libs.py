# -*- coding: utf-8 -*-
"""strip_hap_libs.py — 对 HAP 内的 .so 执行 objcopy --strip-unneeded 后重打包。

用法：python3 scripts/strip_hap_libs.py <hap路径> [so相对路径 ...]
  缺省处理 libs/arm64-v8a/libflutter.so（SIG dev 引擎带调试符号，未剥离）。
说明：
  - HAP 为未签名产物，重打包不影响后续 DevEco 签名。
  - objcopy 不可用或剥离失败时，保留原 so 并继续（宁大勿坏）。
  - 重打包保持条目顺序，使用 deflate 压缩（HAP 允许）。
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

DEFAULT_TARGETS = ["libs/arm64-v8a/libflutter.so"]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    hap = Path(sys.argv[1])
    targets = sys.argv[2:] or DEFAULT_TARGETS

    if shutil.which("objcopy") is None:
        print("strip_hap_libs: objcopy 不可用，跳过剥离")
        return 0

    src = zipfile.ZipFile(hap)
    entries = [(i, src.read(i.filename)) for i in src.infolist() if not i.is_dir()]
    src.close()

    saved = 0
    out = tempfile.mktemp(suffix=".hap")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
        for info, data in entries:
            name = info.filename
            if name in targets and name.endswith(".so"):
                with tempfile.TemporaryDirectory() as td:
                    so_in = Path(td) / "in.so"
                    so_out = Path(td) / "out.so"
                    so_in.write_bytes(data)
                    r = subprocess.run(
                        ["objcopy", "--strip-unneeded", str(so_in), str(so_out)],
                        capture_output=True,
                    )
                    if r.returncode == 0 and so_out.stat().st_size < len(data):
                        saved += len(data) - so_out.stat().st_size
                        print(f"  stripped {name}: {len(data)/1048576:.1f}MB -> "
                              f"{so_out.stat().st_size/1048576:.1f}MB")
                        data = so_out.read_bytes()
                    else:
                        print(f"  strip 失败，保留原 {name}")
            dst.writestr(name, data)

    shutil.move(out, hap)
    print(f"strip_hap_libs: 节省 {saved/1048576:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
