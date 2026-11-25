# 网页层（Web Layer）

本目录除 Flutter 原生 `index.html` / `manifest.json` / `icons` 外，还包含本项目
自定义的「网页层」产物，由 `tools/build_web_layer.sh` 生成：

| 路径 | 作用 |
|---|---|
| `index.html` | 含**极速首屏**（纯 HTML 速览层）、应用内资源库入口（移动端为右侧边缘竖排标签）、加载失败兜底卡片 |
| `gallery.html` + `gallery/` | 独立资源库浏览页（题卡视图 / 全部资源网格 / 中文全文检索） |
| `thumbs/` `mid/` | 1467 张 256px + 354 张 800px 的 webp 缩略图（画廊网格流量降约 12 倍） |
| `gallery/posters/` | 67 个视频首帧海报 |
| `fonts/` | Noto Sans SC / Roboto / Emoji 字体子集镜像（消除对 fonts.gstatic.com 的依赖） |
| `backup.json` | 运行时读取的备用入口地址（域名变更只改这里） |
| `_headers` | Cloudflare Pages 缓存规则 + COOP/COEP 跨源隔离 |
| `404.html` | 自定义 404，带备用入口 |

**为什么需要这些**：Flutter Web 构建默认从 `gstatic.com` 拉渲染器、从 `fonts.gstatic.com`
拉字体回退——两者在国内被墙，页面会永远卡在加载动画。构建脚本会把
`canvasKitBaseUrl` / `fontFallbackBaseUrl` 指向本目录。

重新生成（需要先 `flutter build web`）：

```bash
bash tools/build_web_layer.sh build/web
```
