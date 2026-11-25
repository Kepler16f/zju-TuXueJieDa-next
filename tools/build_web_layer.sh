#!/usr/bin/env bash
# ============================================================
# 构建「网页层」：在 flutter build web 之后运行，为产物补上
#   - 渲染器/字体去 gstatic 依赖（国内可正常打开）
#   - 资源库数据、缩略图、视频海报、字体镜像
#   - 首屏速览 quick.json
#
# 用法：bash tools/build_web_layer.sh [build/web]
# 依赖：python3 + Pillow（缩略图）、ffmpeg（视频海报）
# ============================================================
set -euo pipefail

BUILD_DIR="${1:-build/web}"
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
export SITE_ROOT="$(cd "$BUILD_DIR" && pwd)"

echo "▶ 网页层构建目录: $SITE_ROOT"

echo "▶ 1) 渲染器与字体回退本地化（去 gstatic 依赖）"
python3 - "$SITE_ROOT" <<'PYEOF'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]) / 'flutter_bootstrap.js'
s = p.read_text(encoding='utf-8')
if '"canvasKitBaseUrl": "canvaskit/"' in s:
    print("   已配置，跳过")
else:
    m = re.search(r'_flutter\.loader\.load\(\{\n(.*?)\n\}\);', s, re.S)
    if not m:
        raise SystemExit("!! 未找到 _flutter.loader.load，需人工处理")
    body = m.group(1)
    cfg = 'config: {\n    "canvasKitBaseUrl": "canvaskit/",\n    "fontFallbackBaseUrl": "fonts/"\n  },\n  '
    new_body = body.replace('serviceWorkerSettings:', cfg + 'serviceWorkerSettings:', 1) if 'serviceWorkerSettings' in body else cfg + body
    p.write_text(s[:m.start(1)] + new_body + s[m.end(1):], encoding='utf-8')
    print("   已注入 canvasKitBaseUrl / fontFallbackBaseUrl")
PYEOF

echo "▶ 2) 视频海报（ffmpeg 抽首帧）"
bash "$TOOLS_DIR/make_posters.sh" | tail -2

echo "▶ 3) 资源库数据 data.json"
python3 "$TOOLS_DIR/build_gallery_data.py"

echo "▶ 4) 缩略图（256px / 800px webp）"
python3 "$TOOLS_DIR/make_thumbs.py" | tail -3

echo "▶ 5) 字体镜像（Noto Sans SC / Roboto / Emoji）"
python3 "$TOOLS_DIR/mirror_fonts.py" | tail -2
# 引擎有两条取数路径：/fonts/... 与 /assets/fonts/...，两处都要放
mkdir -p "$SITE_ROOT/assets/fonts"
cp -r "$SITE_ROOT/fonts/." "$SITE_ROOT/assets/fonts/" 2>/dev/null || true

echo "▶ 6) 首屏速览 quick.json（约 1.2KB，避免首屏拉完整 data.json）"
python3 - "$SITE_ROOT" <<'PYEOF'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
d = json.loads((root / 'gallery/data.json').read_text(encoding='utf-8'))
items = []
for p in d['problems'][:16]:
    t = (p.get('subject') or {}).get('url') or ''
    m = re.search(r'assets/assets/([a-z]+)/', t)
    thumb = ('thumbs/%s/%s.webp' % (m.group(1), t.split('/')[-1].rsplit('.', 1)[0])) if m else ''
    items.append({"id": p['id'], "label": p.get('label') or p['id'], "thumb": thumb})
q = {"purpose": "极速首屏速览：16 条标签+缩略图路径，约 1.2KB", "items": items}
(root / 'gallery/quick.json').write_text(json.dumps(q, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print("   quick.json:", (root / 'gallery/quick.json').stat().st_size, "字节")
PYEOF

echo ""
echo "▶ 网页层构建完成"
find "$SITE_ROOT" -type f | wc -l | sed 's/^/   文件总数: /'
du -sh "$SITE_ROOT" | sed 's/^/   体积: /'
