#!/usr/bin/env bash
# 为每个 mp4 抽取一帧作为画廊缩略图（poster）
set -u
VID_DIR="${SITE_ROOT:-/workspace/site}/assets/assets/videos"
OUT_DIR="${SITE_ROOT:-/workspace/site}/gallery/posters"
mkdir -p "$OUT_DIR"
ok=0; fail=0
for f in "$VID_DIR"/*.mp4; do
  name=$(basename "$f" .mp4)
  out="$OUT_DIR/${name}.jpg"
  [ -s "$out" ] && { ok=$((ok+1)); continue; }
  if ffmpeg -loglevel error -y -i "$f" -vf "select=eq(n\,0)+eq(n\,12),scale=320:-1:flags=lanczos" -frames:v 1 -q:v 7 "$out" 2>/dev/null; then
    ok=$((ok+1))
  else
    # 回退：取 0.5 秒处
    ffmpeg -loglevel error -y -ss 0.5 -i "$f" -frames:v 1 -vf "scale=320:-1:flags=lanczos" -q:v 7 "$out" 2>/dev/null && ok=$((ok+1)) || { echo "FAIL $name"; fail=$((fail+1)); }
  fi
done
echo "posters ok=$ok fail=$fail"
ls "$OUT_DIR" | wc -l
du -sh "$OUT_DIR"
