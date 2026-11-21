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
OHOS_APP_VERSION="${OHOS_APP_VERSION:-0.0.0}"
OHOS_DEVELOPER="${OHOS_DEVELOPER:-胡天泽}"
OHOS_BUILD_NUMBER="${OHOS_BUILD_NUMBER:-1}"

# 版本号同步进 pubspec（flutter create 生成 app.json5 的 versionName / versionCode 取自它）
sed -i -E "s/^version: .*/version: ${OHOS_APP_VERSION}+${OHOS_BUILD_NUMBER}/" pubspec.yaml

if [ ! -d ohos ]; then
  flutter create --platforms ohos --project-name tuxuejieda_next .
fi

# bundleName 指向本项目域名
sed -i -E "s/\"bundleName\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"bundleName\": \"$BUNDLE_ID\"/" ohos/AppScope/app.json5
# 开发者（vendor）：鸿蒙端显示「胡天泽」
sed -i -E "s/\"vendor\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"vendor\": \"$OHOS_DEVELOPER\"/" ohos/AppScope/app.json5
# 版本号与构建号（用户在 Release / 系统应用信息里看到的 versionName / versionCode）
sed -i -E "s/\"versionName\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"versionName\": \"$OHOS_APP_VERSION\"/" ohos/AppScope/app.json5
sed -i -E "s/\"versionCode\"[[:space:]]*:[[:space:]]*[0-9]+/\"versionCode\": $OHOS_BUILD_NUMBER/" ohos/AppScope/app.json5

# 横屏适配：ability 方向声明改为 auto_rotation（跟随系统旋转），
# 运行期由 Flutter SystemChrome.setPreferredOrientations 按用户开关细分。
python3 - <<'PY'
import io
import os
import re

p = "ohos/entry/src/main/module.json5"
if os.path.isfile(p):
    text = io.open(p, encoding="utf-8").read()
    if '"orientation"' in text:
        text = re.sub(
            r'"orientation"\s*:\s*"[^"]*"',
            '"orientation": "auto_rotation"',
            text,
        )
        io.open(p, "w", encoding="utf-8", newline="\n").write(text)
        print("module.json5 orientation -> auto_rotation")
    else:
        print("module.json5 has no orientation field (defaults to unspecified)")
PY

# 应用名：launcher 显示名来自 entry 模块各语言目录下 string.json 中的 EntryAbility_label
#（OpenHarmony/HarmonyOS 模板同时生成 base / zh_CN / en_US 三套资源，中文系统优先读取 zh_CN；
# 仅改 base 会导致中文桌面仍然显示 Tuxuejieda_next。）
python3 - <<'PY'
import glob
import io
import json
import os
import re

TARGET_LABEL = "图学习题解答"
PATCH_KEYS = {"EntryAbility_label", "app_name", "ability_label"}

# 1. 检查 module.json5 与 app.json5 的 label 引用（若写了字面量 tuxuejieda* 或自定义 $string key 一并纳管）
for cfg_path, fallback_ref in [
    ("ohos/AppScope/app.json5", "$string:app_name"),
    ("ohos/entry/src/main/module.json5", "$string:EntryAbility_label"),
]:
    if not os.path.isfile(cfg_path):
        continue
    text = io.open(cfg_path, encoding="utf-8").read()
    changed = False
    for m in re.finditer(r'"label"\s*:\s*"([^"]+)"', text):
        val = m.group(1)
        if val.startswith("$string:"):
            PATCH_KEYS.add(val.split(":", 1)[1])
        elif val.lower().startswith("tuxuejieda"):
            text = text.replace(f'"{val}"', f'"{fallback_ref}"')
            changed = True
    if changed:
        io.open(cfg_path, "w", encoding="utf-8", newline="\n").write(text)
        print(f"patched json5 label ref -> {cfg_path}")

# 2. 统一更新 base / zh_CN / en_US 及其它所有区域目录下的 string.json
string_files = sorted(
    glob.glob("ohos/AppScope/resources/**/element/string.json", recursive=True)
    + glob.glob("ohos/entry/src/main/resources/**/element/string.json", recursive=True)
)
for p in string_files:
    with io.open(p, encoding="utf-8") as f:
        data = json.load(f)
    items = data.get("string", [])
    seen_entry_label = False
    for item in items:
        nm = item.get("name", "")
        val = str(item.get("value", ""))
        if nm == "EntryAbility_label":
            seen_entry_label = True
        if nm in PATCH_KEYS or val.lower().startswith("tuxuejieda"):
            item["value"] = TARGET_LABEL
    if not seen_entry_label and "entry/src/main/resources" in p.replace("\\", "/"):
        items.append({"name": "EntryAbility_label", "value": TARGET_LABEL})
    data["string"] = items
    with io.open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"label -> {TARGET_LABEL} in {p}")
PY

# 华为官方全端设备声明（手机 phone、平板 tablet、PC/二合一 2in1）及多窗口模式
python3 scripts/patch_ohos_devices.py entry .

# 图标：AGC 审核要求「单层图」为 1024x1024、方角、无透明像素。
# 使用 tools/app_icon_square_1024.png（RGB 无 alpha、方角铺满的品牌渐变底）
# 以 1024x1024 覆盖 AppScope/app_icon.png 与 entry 各语言 media/icon.png。
ICON="$PWD/tools/app_icon_square_1024.png"
if [ -f "$ICON" ] && python3 -c "import PIL" 2>/dev/null; then
  python3 - "$ICON" <<'PY'
import glob
import os
import sys

from PIL import Image

icon = sys.argv[1]
square = Image.open(icon).convert("RGB")
targets = sorted(
    glob.glob("ohos/entry/src/main/resources/*/media/icon.png")
    + glob.glob("ohos/AppScope/resources/*/media/app_icon.png")
)
for path in targets:
    square.save(path, format="PNG")
    print(f"icon -> {path} (1024x1024 RGB, square, no alpha)")
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
