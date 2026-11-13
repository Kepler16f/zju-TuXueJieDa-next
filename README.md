# 图学基础教程习题解答 · Next (`zju-TuXueJieDa-next`)

基于 Flutter 重构的跨平台《图学基础教程习题解答》现代客户端，完整保留浙江大学工程及计算机图学教研室原版 **177 道激活习题** 的真实页码与题号顺序、原题/答案对照、分步作图详解、多视图切换及全量 **67 个** 配套三维/投影演示动画。

## 核心特性

- **精确还原真实页码与题号**：通过逆向解析原版 Director Score（`VWSC`）与 `Cast` 调用关系，修正了文件名与真实显示页码/题号不一致的问题，严格迁移主程序 4 大模块当前可点选的全部 **177 题**（基础投影 64、组合体与表达方法 78、工程图 32、曲线曲面与专项投影 3）。
- **高质量离线图形与文字资产**：
  - 自动剥离旧版 `jieti/*.dir` 中的 Director 翻页/标签栏控件，合成纯净的 `540×450` 分步/多视图图像；
  - 优先采用 `SubAnsTu.cst` 内置更新版原图/答案（含 `p52_1n~4n` 等无外部 `.jpg` 的 `BITD` 位图），并抽取出 177 题 `text.cst` 文字题干与作图步骤 `XMED` 注释；
  - 将 `avi.cst` 及未挂载的 `P111_21.avi` 共 **67 个** Cinepak / MS Video 1 `.avi` 动画统一转码为 H.264 MP4。
- **高效交互与跨平台适配**：
  - 高清白底图纸工作台，支持滚轮/双指缩放、双击复位、按住或空格键一键“原题 ↔ 答案”叠图对比；
  - 键盘快捷键支持（`←`/`→` 切换步骤，`PageUp`/`PageDown` 切换上下题，`Space` 对比）；
  - Windows / Android / Linux 内置 GitHub Releases 检查更新、带进度下载与安装拉起功能。

## 目录结构

- `lib/`: Flutter UI、状态仓储与跨平台更新服务
- `assets/data/curriculum.json`: 177 题结构化课程与页码映射索引
- `assets/subjects/`, `assets/answers/`, `assets/steps/`, `assets/videos/`: 抽离与转码后的现代多媒体资产
- `tools/extract_assets.py`: Director 资产逆向抽取与视频转码脚本
- `tools/build_package.ps1`: 版本同步与安装包构建归档脚本
