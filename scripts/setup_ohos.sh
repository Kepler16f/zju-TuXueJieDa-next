#!/usr/bin/env bash
# setup_ohos.sh — 鸿蒙构建初始化（在鸿蒙 Flutter fork 的 flutter 下运行）：
#   1. flutter create --platforms ohos . 生成宿主工程（若不存在）
#   2. 定制 bundleName / 应用名 / 图标（圆规）
#   3. 写 pubspec_overrides.yaml，把插件切到 OpenHarmony SIG 的 ohos 适配
#      （fork 为 oh-3.47.9-dev，与主线 Dart 3.13.7 一致，插件版本原生满足约束）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION_LABEL="图学习题解答"
BUNDLE_ID="com.kepler16f.tuxuejieda"

if [ ! -d ohos ]; then
  flutter create --platforms ohos --project-name tuxuejieda_next .
fi

# bundleName 指向本项目域名
sed -i -E "s/\"bundleName\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"bundleName\": \"$BUNDLE_ID\"/" ohos/AppScope/app.json5

# 应用名（AppScope string 资源里的 app_name）
python3 - <<'PY'
import json, io, os
p = "ohos/AppScope/resources/base/element/string.json"
with io.open(p, encoding="utf-8") as f:
    data = json.load(f)
for item in data.get("string", []):
    if item.get("name") == "app_name":
        item["value"] = "图学习题解答"
with io.open(p, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print("app label -> 图学习题解答")
PY

# 图标：替换分层图标的前景图为圆规
ICON="$PWD/tools/app_icon_master.png"
MEDIA_DIR="ohos/AppScope/resources/base/media"
if [ -f "$ICON" ] && [ -d "$MEDIA_DIR" ] && python3 -c "import PIL" 2>/dev/null; then
  python3 - "$ICON" "$MEDIA_DIR" <<'PY'
import sys, os
from PIL import Image
icon, media = sys.argv[1], sys.argv[2]
im = Image.open(icon).convert("RGBA")
for fn in os.listdir(media):
    if fn.endswith(".png"):
        Image.open(os.path.join(media, fn)).close()
        im.resize((512, 512), Image.LANCZOS).save(os.path.join(media, fn))
        print("icon ->", fn)
PY
fi

# 插件切换到 SIG ohos 适配（pub get 之后其它平台构建不受影响：本文件不提交）
cat > pubspec_overrides.yaml <<'OVR'
# 由 scripts/setup_ohos.sh 生成，仅鸿蒙构建使用（CI 内生成、不提交）。
dependency_overrides:
  video_player:
    git:
      url: "https://gitee.com/openharmony-sig/flutter_packages.git"
      path: "packages/video_player/video_player"
  shared_preferences:
    git:
      url: "https://gitee.com/openharmony-sig/flutter_packages.git"
      path: "packages/shared_preferences/shared_preferences"
  path_provider:
    git:
      url: "https://gitee.com/openharmony-sig/flutter_packages.git"
      path: "packages/path_provider/path_provider"
  url_launcher:
    git:
      url: "https://gitee.com/openharmony-sig/flutter_packages.git"
      path: "packages/url_launcher/url_launcher"
  package_info_plus:
    git:
      url: "https://gitee.com/openharmony-sig/flutter_plus_plugins.git"
      path: "packages/package_info_plus/package_info_plus"
OVR
echo "pubspec_overrides.yaml written"
