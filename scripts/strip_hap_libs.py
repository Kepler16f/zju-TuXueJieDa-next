# -*- coding: utf-8 -*-
"""strip_hap_libs.py — 对 HAP 内的 .so 执行 objcopy --strip-unneeded 后重打包。

特别说明（华为 AGC 规则强制要求）：
  - OpenHarmony / HarmonyOS NEXT 要求所有 *.abc（如 ets/modules.abc）必须未压缩存储
    （compress_type=0 / ZIP_STORED），供运行时 mmap 直接映射，否则 AGC 上传检测报：
    「abc文件压缩检测: 检测abc文件是否被压缩 不通过 请确保您的abc文件没有经过压缩」。
  - 本脚本严格保持原条目压缩属性，并强制 *.abc 为 ZIP_STORED 且 4 字节对齐。
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

    has_objcopy = shutil.which("objcopy") is not None
    if not has_objcopy:
        print("strip_hap_libs: objcopy 不可用，跳过 .so 剥离，但仍将检查并保证 .abc 未压缩")

    src = zipfile.ZipFile(hap)
    entries = [(i, src.read(i.filename)) for i in src.infolist() if not i.is_dir()]
    src.close()

    saved = 0
    out = tempfile.mktemp(suffix=".hap")
    with zipfile.ZipFile(out, "w") as dst:
        for info, data in entries:
            name = info.filename
            if has_objcopy and name in targets and name.endswith(".so"):
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

            new_info = zipfile.ZipInfo(name, date_time=info.date_time)
            new_info.comment = info.comment
            new_info.extra = info.extra
            new_info.external_attr = info.external_attr

            # 华为 AGC 强制规则：*.abc 绝对不能压缩
            if name.endswith(".abc"):
                new_info.compress_type = zipfile.ZIP_STORED
            else:
                new_info.compress_type = info.compress_type

            # 对 STORED 未压缩条目保持 4 字节对齐（供 mmap 寻址）
            if new_info.compress_type == zipfile.ZIP_STORED:
                header_len = 30 + len(new_info.filename.encode("utf-8")) + len(new_info.extra)
                current_pos = dst.fp.tell()
                data_pos = current_pos + header_len
                pad = (4 - (data_pos % 4)) % 4
                if pad > 0:
                    new_info.extra = new_info.extra + b"\x00" * pad

            dst.writestr(new_info, data)

    shutil.move(out, hap)
    if saved > 0:
        print(f"strip_hap_libs: 节省 {saved/1048576:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
