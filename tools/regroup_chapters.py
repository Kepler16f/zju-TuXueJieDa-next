#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""按显示页码重组 assets/data/curriculum.json 的章节（schemaVersion 1 -> 2）。

仅依赖 Python 标准库，幂等可重复运行：`python -I tools/regroup_chapters.py`
执行任意多次，输出文件字节级一致（章节分配只取决于每题 page 与 problems
数组原始顺序，脚本从不重排 problems 数组本身）。

章节映射规则（按每题 page 字段划分，区间为闭区间、依次衔接）：

    tyjc 投影基础              11 <= page <= 31
    zhst 组合体和实体造型      32 <= page <= 66
    gctb 工程图表达基础        67 <= page <= 87
    ghyd 工程图的绘制与阅读    88 <= page <= 121
    sjgx 工程数据常用图形      122 <= page <= 124
    yiny 阴影                  page >= 125

注意：当前数据最大 page=124，阴影章（yiny）为 0 题；用户已确认"空章节不单独
显示"，因此 chapters 数组不写入 yiny。若未来出现 page >= 125 的题目，本脚本
会自动重建 yiny 章并写入 chapters 数组末尾（见 rebuild_chapters）。

lossless 保证：只改写每题的 chapterId、orderInChapter 两个字段与顶层
schemaVersion；problems 数组顺序、groupIndex 及其余字段一律不动；对象键顺序
保持原样（原地赋值已有键）。输出沿用现有文件的序列化风格：UTF-8、
ensure_ascii=False、indent 2、CRLF 行尾、EOF 不附加换行（JSON 字符串值内的
换行一律被 json 转义为 \\n 两个字符，因此对全文做 \\n -> \\r\\n 替换只影响
结构换行），从而保证字节级幂等。

异常数据策略：page < 11 或落入区间缝隙的题目，向 stderr 打印警告并归入
tyjc（数据不丢弃），同时在 stdout 报告中列出数量。
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_FILE = ROOT / "assets" / "data" / "curriculum.json"

# 页码区间表：顺序即 chapters 数组的输出顺序，(id, 标题, 下界, 上界) 均为闭区间。
PAGE_RANGES = [
    ("tyjc", "投影基础", 11, 31),
    ("zhst", "组合体和实体造型", 32, 66),
    ("gctb", "工程图表达基础", 67, 87),
    ("ghyd", "工程图的绘制与阅读", 88, 121),
    ("sjgx", "工程数据常用图形", 122, 124),
]
YINY_ID = "yiny"
YINY_TITLE = "阴影"
YINY_MIN_PAGE = 125

# 当前数据集（177 题）的自校验期望值；若未来题目集发生变化（例如出现
# page >= 125 的题、新增 yiny 章），需同步更新这里的常量。
EXPECTED_TOTAL = 177
EXPECTED_VIDEO = 67
EXPECTED_COUNTS = {"tyjc": 42, "zhst": 66, "gctb": 34, "ghyd": 32, "sjgx": 3}


def chapter_for_page(page: int) -> tuple[str, bool]:
    """返回 (chapterId, 是否落入正式映射区间)。

    page >= 125 归 yiny；page < 11 或缝隙（理论上不存在，区间已连续，防御
    未来区间被改动）归 tyjc，后者由调用方负责警告。
    """
    for chapter_id, _title, lo, hi in PAGE_RANGES:
        if lo <= page <= hi:
            return chapter_id, True
    if page >= YINY_MIN_PAGE:
        return YINY_ID, True
    return PAGE_RANGES[0][0], False


def rebuild_chapters(grouped: dict[str, list[tuple[int, int]]]) -> list[dict]:
    """按 PAGE_RANGES 顺序重建 chapters 数组，仅包含非空章节。

    subtitle 格式 '页码 X–Y · 共 N 题'，X–Y 取该章题目的实际最小/最大页码。
    空章节跳过（用户确认：空章节不单独显示）；yiny 仅在非空时追加到末尾。
    dirFile 留空：新章节按页码范围划分，不再一一对应原 Director 工程文件。
    """
    chapters: list[dict] = []
    entries = list(PAGE_RANGES) + [(YINY_ID, YINY_TITLE, YINY_MIN_PAGE, None)]
    for chapter_id, title, _lo, _hi in entries:
        members = grouped.get(chapter_id, [])
        if not members:
            continue  # 空章节不写入 chapters（yiny 当前为 0 题即属此情况）
        pages = [page for page, _index in members]
        subtitle = f"页码 {min(pages)}–{max(pages)} · 共 {len(members)} 题"
        chapters.append(
            {
                "id": chapter_id,
                "title": title,
                "subtitle": subtitle,
                "dirFile": "",
            }
        )
    return chapters


def verify(data: dict, original_counts: Counter, stray: list[tuple[str, int]]) -> int:
    """重读磁盘上的产物并自校验；返回错误数（0 为通过）。"""
    errors: list[str] = []
    reloaded = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    problems = reloaded["problems"]

    total = len(problems)
    video = sum(1 for p in problems if p.get("video"))
    counts = Counter(p["chapterId"] for p in problems)
    chapter_ids = [c["id"] for c in reloaded["chapters"]]
    chapter_id_set = set(chapter_ids)

    if reloaded.get("schemaVersion") != 2:
        errors.append(f"schemaVersion={reloaded.get('schemaVersion')}，应为 2")
    if total != EXPECTED_TOTAL:
        errors.append(f"题目总数 {total} != 期望 {EXPECTED_TOTAL}")
    if reloaded.get("problemCount") != total:
        errors.append(f"problemCount 字段 {reloaded.get('problemCount')} != 实际 {total}")
    if video != EXPECTED_VIDEO:
        errors.append(f"视频题数 {video} != 期望 {EXPECTED_VIDEO}")
    if reloaded.get("videoCount") != video:
        errors.append(f"videoCount 字段 {reloaded.get('videoCount')} != 实际 {video}")

    # 每题 chapterId 必须命中 chapters 数组中的某个章节
    for p in problems:
        if p["chapterId"] not in chapter_id_set:
            errors.append(f"题目 {p['id']} 的 chapterId={p['chapterId']} 不在 chapters 中")

    # chapters 只含非空章，且顺序符合 PAGE_RANGES（yiny 追加在末尾）
    expected_order = [cid for cid, _t, _lo, _hi in PAGE_RANGES if counts.get(cid)]
    if counts.get(YINY_ID):
        expected_order.append(YINY_ID)
    if chapter_ids != expected_order:
        errors.append(f"chapters 顺序 {chapter_ids} != 期望 {expected_order}")

    # 每章 subtitle 与实际页码范围/计数一致
    for c in reloaded["chapters"]:
        members = [p for p in problems if p["chapterId"] == c["id"]]
        pages = [p["page"] for p in members]
        expected_subtitle = f"页码 {min(pages)}–{max(pages)} · 共 {len(members)} 题"
        if c["subtitle"] != expected_subtitle:
            errors.append(f"章节 {c['id']} subtitle '{c['subtitle']}' != '{expected_subtitle}'")

    # orderInChapter：每章内为 0..n-1 且按 (page 升序) 排列
    for c in reloaded["chapters"]:
        members = [p for p in problems if p["chapterId"] == c["id"]]
        orders = [p["orderInChapter"] for p in members]
        if orders != list(range(len(members))):
            errors.append(f"章节 {c['id']} orderInChapter 不是 0..n-1")
        if [p["page"] for p in members] != sorted(p["page"] for p in members):
            errors.append(f"章节 {c['id']} 内题目未按 page 升序")

    # 当前数据集的期望分布（仅在 yiny 为空时适用；yiny 出现说明数据集已扩展）
    if not counts.get(YINY_ID):
        for cid, expected in EXPECTED_COUNTS.items():
            if counts.get(cid, 0) != expected:
                errors.append(f"章节 {cid} 计数 {counts.get(cid, 0)} != 期望 {expected}")
        if sum(EXPECTED_COUNTS.values()) != total:
            errors.append("EXPECTED_COUNTS 之和与总数不一致，请更新常量")

    # stdout 报告
    before = "、".join(f"{k}={v}" for k, v in sorted(original_counts.items()))
    after = "、".join(f"{c['id']}={counts[c['id']]}" for c in reloaded["chapters"])
    print(f"重组完成：schemaVersion -> 2")
    print(f"  重组前（旧 chapterId）：{before}")
    print(f"  重组后（新 chapterId）：{after}")
    print(f"  chapters 数组：{', '.join(chapter_ids)}")
    print(f"  视频题：{video}/{total}；区间外题目：{len(stray)}")
    for problem_id, page in stray:
        print(f"    - {problem_id}: page={page}（已归入 tyjc）")
    if errors:
        for e in errors:
            print(f"自校验失败：{e}", file=sys.stderr)
        return len(errors)
    print("自校验通过：总数/视频/章节计数/chapterId/orderInChapter/subtitle 全部一致")
    return 0


def main() -> int:
    if not DATA_FILE.exists():
        print(f"找不到数据文件：{DATA_FILE}", file=sys.stderr)
        return 1
    text = DATA_FILE.read_text(encoding="utf-8")
    data = json.loads(text)
    problems = data["problems"]

    original_counts = Counter(p["chapterId"] for p in problems)

    # 1) 按 page 重新分配 chapterId（原地赋值已有键，保持键顺序与数组顺序）
    stray: list[tuple[str, int]] = []
    grouped: dict[str, list[tuple[int, int]]] = {
        chapter_id: [] for chapter_id, _t, _lo, _hi in PAGE_RANGES
    }
    grouped[YINY_ID] = []
    for index, problem in enumerate(problems):
        page = int(problem["page"])
        chapter_id, in_range = chapter_for_page(page)
        problem["chapterId"] = chapter_id
        if not in_range:
            stray.append((problem["id"], page))
            print(
                f"warning: 题目 {problem['id']} 的 page={page} 不在任何映射区间内，已归入 tyjc",
                file=sys.stderr,
            )
        grouped[chapter_id].append((page, index))

    # 2) 章节内按 (page 升序, 原数组顺序) 重排 orderInChapter 为 0..n-1；
    #    groupIndex 与其余字段一律不动
    for _chapter_id, members in grouped.items():
        members.sort()  # (page, 原数组下标)
        for order, (_page, index) in enumerate(members):
            problems[index]["orderInChapter"] = order

    # 3) 重建 chapters（仅非空章）并升级 schemaVersion
    data["chapters"] = rebuild_chapters(grouped)
    data["schemaVersion"] = 2

    # 4) 回写：沿用现有文件的 CRLF 行尾与 EOF 无换行的序列化风格
    payload = json.dumps(data, ensure_ascii=False, indent=2)
    DATA_FILE.write_bytes(payload.replace("\n", "\r\n").encode("utf-8"))

    # 5) 重新读盘自校验
    return verify(data, original_counts, stray)


if __name__ == "__main__":
    sys.exit(main())
