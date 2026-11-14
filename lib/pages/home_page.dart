import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/curriculum_repository.dart';
import '../models/curriculum.dart';
import 'problem_workspace_page.dart';

enum ProblemFilter { all, withVideo, multiStep, bookmarked, unfinished }

/// Main curriculum browser with chapter navigation, search and study progress.
/// Embedded as the 题库 destination inside the responsive AppShell.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repo});

  final CurriculumRepository repo;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchCtrl = TextEditingController();

  String? _selectedChapterId;
  ProblemFilter _filter = ProblemFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openProblem(Curriculum curriculum, Problem problem) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProblemWorkspacePage(
          repo: widget.repo,
          curriculum: curriculum,
          initialProblem: problem,
        ),
      ),
    );
  }

  List<Problem> _filteredProblems(Curriculum c) {
    final q = _searchCtrl.text;
    return c.problems.where((p) {
      if (_selectedChapterId != null && p.chapterId != _selectedChapterId) {
        return false;
      }
      switch (_filter) {
        case ProblemFilter.withVideo:
          if (!p.hasVideo) return false;
        case ProblemFilter.multiStep:
          if (!p.hasMultiStep) return false;
        case ProblemFilter.bookmarked:
          if (!widget.repo.isBookmarked(p.id)) return false;
        case ProblemFilter.unfinished:
          if (widget.repo.isCompleted(p.id)) return false;
        case ProblemFilter.all:
          break;
      }
      final chTitle = c.chapterById(p.chapterId).title;
      return p.matchesQuery(q, chTitle);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final repo = widget.repo;
        final theme = Theme.of(context);

        if (repo.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载图学习题与数字资产...'),
                ],
              ),
            ),
          );
        }

        if (repo.error != null || repo.curriculum == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    Text('课程数据加载失败：${repo.error}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: repo.initialize,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final curriculum = repo.curriculum!;
        final filtered = _filteredProblems(curriculum);
        final lastProblem = repo.lastProblemId != null
            ? curriculum.findById(repo.lastProblemId!)
            : null;
        final videoTotal = curriculum.problems.where((p) => p.hasVideo).length;
        final doneCount = repo.completedIds.length;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            actions: [
              IconButton(
                tooltip: repo.problemViewStyle == 'card'
                    ? '切换为列表视图'
                    : '切换为卡片视图',
                icon: Icon(
                  repo.problemViewStyle == 'card'
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                ),
                onPressed: () => repo.setProblemViewStyle(
                  repo.problemViewStyle == 'card' ? 'list' : 'card',
                ),
              ),
              const SizedBox(width: 4),
            ],
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.architecture_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '图学基础教程习题解答',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '非官方重制 · 原课件数字化重构',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary stats + optional resume card
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatPill(
                            icon: Icons.menu_book_rounded,
                            label: '已启用 ${curriculum.problems.length} 题',
                          ),
                          _StatPill(
                            icon: Icons.play_circle_outline_rounded,
                            label: '配套动画 $videoTotal 题',
                          ),
                          _StatPill(
                            icon: Icons.check_circle_outline_rounded,
                            label: '已完成 $doneCount / ${curriculum.problems.length}',
                          ),
                          if (lastProblem != null)
                            FilledButton.tonalIcon(
                              onPressed: () => _openProblem(curriculum, lastProblem),
                              icon: const Icon(Icons.history_rounded, size: 18),
                              label: Text('继续：${lastProblem.displayLabel}'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Chapter cards
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 780;
                          final cards = curriculum.chapters.map((ch) {
                            final list = curriculum.problemsInChapter(ch.id);
                            final chDone = list.where((p) => repo.isCompleted(p.id)).length;
                            final selected = _selectedChapterId == ch.id;
                            return _ChapterCard(
                              chapter: ch,
                              total: list.length,
                              done: chDone,
                              selected: selected,
                              onTap: () => setState(() {
                                _selectedChapterId = selected ? null : ch.id;
                              }),
                            );
                          }).toList(growable: false);

                          if (wide) {
                            return Row(
                              children: [
                                for (var i = 0; i < cards.length; i++) ...[
                                  Expanded(child: cards[i]),
                                  if (i < cards.length - 1) const SizedBox(width: 10),
                                ],
                              ],
                            );
                          }
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0; i < cards.length; i++) ...[
                                  SizedBox(width: 220, child: cards[i]),
                                  if (i < cards.length - 1) const SizedBox(width: 10),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      // Search + filter bar
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 720;
                          final searchBox = TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: '搜索页码 (如 43)、题号 (如 85_3)、题干关键词或步骤要点...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchCtrl.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {});
                                      },
                                    ),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );

                          final chips = Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _FilterChipBtn(
                                label: '全部 (${curriculum.problems.length})',
                                selected: _filter == ProblemFilter.all,
                                onTap: () => setState(() => _filter = ProblemFilter.all),
                              ),
                              _FilterChipBtn(
                                label: '有动画视频 ($videoTotal)',
                                selected: _filter == ProblemFilter.withVideo,
                                onTap: () => setState(() => _filter = ProblemFilter.withVideo),
                              ),
                              _FilterChipBtn(
                                label: '分步 / 多视图',
                                selected: _filter == ProblemFilter.multiStep,
                                onTap: () => setState(() => _filter = ProblemFilter.multiStep),
                              ),
                              _FilterChipBtn(
                                label: '已收藏 (${repo.bookmarkedIds.length})',
                                selected: _filter == ProblemFilter.bookmarked,
                                onTap: () => setState(() => _filter = ProblemFilter.bookmarked),
                              ),
                              _FilterChipBtn(
                                label: '未完成',
                                selected: _filter == ProblemFilter.unfinished,
                                onTap: () => setState(() => _filter = ProblemFilter.unfinished),
                              ),
                            ],
                          );

                          if (isWide) {
                            return Row(
                              children: [
                                SizedBox(width: 340, child: searchBox),
                                const SizedBox(width: 12),
                                Expanded(child: chips),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              searchBox,
                              const SizedBox(height: 10),
                              chips,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            _selectedChapterId == null
                                ? '全部章节 · 匹配 ${filtered.length} 道题'
                                : '${curriculum.chapterById(_selectedChapterId!).title} · 匹配 ${filtered.length} 道题',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_selectedChapterId != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => setState(() => _selectedChapterId = null),
                              child: const Text('查看全部章节'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('未找到匹配该条件的习题，请尝试更改关键词或筛选器。'),
                  ),
                )
              else if (repo.problemViewStyle == 'list')
                SliverPadding(
                  // Leave room for the shell's bottom NavigationBar under
                  // edge-to-edge (padding.bottom already carries the allowance).
                  padding: EdgeInsets.fromLTRB(
                    16, 4, 16,
                    math.max(24.0, MediaQuery.paddingOf(context).bottom),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final problem = filtered[index];
                        final ch = curriculum.chapterById(problem.chapterId);
                        return _ProblemRow(
                          problem: problem,
                          chapterTitle: ch.title,
                          done: repo.isCompleted(problem.id),
                          bookmarked: repo.isBookmarked(problem.id),
                          hasNote: repo.noteFor(problem.id).isNotEmpty,
                          onTap: () => _openProblem(curriculum, problem),
                          onToggleDone: () => repo.toggleCompleted(problem.id),
                          onToggleBookmark: () => repo.toggleBookmarked(problem.id),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  // Leave room for the shell's bottom NavigationBar under
                  // edge-to-edge (padding.bottom already carries the allowance).
                  padding: EdgeInsets.fromLTRB(
                    16, 4, 16,
                    math.max(24.0, MediaQuery.paddingOf(context).bottom),
                  ),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 390,
                      mainAxisExtent: 172,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final problem = filtered[index];
                        final ch = curriculum.chapterById(problem.chapterId);
                        return _ProblemCard(
                          problem: problem,
                          chapterTitle: ch.title,
                          done: repo.isCompleted(problem.id),
                          bookmarked: repo.isBookmarked(problem.id),
                          onTap: () => _openProblem(curriculum, problem),
                          onToggleDone: () => repo.toggleCompleted(problem.id),
                          onToggleBookmark: () => repo.toggleBookmarked(problem.id),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.chapter,
    required this.total,
    required this.done,
    required this.selected,
    required this.onTap,
  });

  final Chapter chapter;
  final int total;
  final int done;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : done / total;
    return Card(
      elevation: selected ? 2 : 0,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: selected ? 1.6 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$done/$total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                chapter.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  const _FilterChipBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({
    required this.problem,
    required this.chapterTitle,
    required this.done,
    required this.bookmarked,
    required this.onTap,
    required this.onToggleDone,
    required this.onToggleBookmark,
  });

  final Problem problem;
  final String chapterTitle;
  final bool done;
  final bool bookmarked;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepText = switch (problem.jietiMode) {
      JietiMode.tabbed => '多视图 ${problem.steps.length} 项',
      JietiMode.stepped => '分步 ${problem.steps.length} 步',
      JietiMode.twoState => '题面 / 答案',
    };

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          problem.displayLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      chapterTitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: bookmarked ? '取消收藏' : '收藏本题',
                    icon: Icon(
                      bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                      color: bookmarked ? Colors.amber.shade700 : null,
                    ),
                    onPressed: onToggleBookmark,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: done ? '标记为未完成' : '标记为已完成',
                    icon: Icon(
                      done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                      color: done ? Colors.green.shade600 : null,
                    ),
                    onPressed: onToggleDone,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _OverflowScrollText(
                  text: problem.statement.isNotEmpty
                      ? problem.statement.replaceAll('\n', ' ')
                      : '点击查看原题图形、分步详解与标准答案',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _MiniTag(
                    icon: Icons.layers_outlined,
                    label: stepText,
                    highlight: problem.hasMultiStep,
                  ),
                  if (problem.hasVideo) ...[
                    const SizedBox(width: 6),
                    const _MiniTag(
                      icon: Icons.play_circle_filled_rounded,
                      label: '动画视频',
                      highlight: true,
                      isVideo: true,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '#${problem.id}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表视图的紧凑题目行：与卡片同数据、同操作，单行展示。
class _ProblemRow extends StatelessWidget {
  const _ProblemRow({
    required this.problem,
    required this.chapterTitle,
    required this.done,
    required this.bookmarked,
    required this.hasNote,
    required this.onTap,
    required this.onToggleDone,
    required this.onToggleBookmark,
  });

  final Problem problem;
  final String chapterTitle;
  final bool done;
  final bool bookmarked;
  final bool hasNote;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                size: 17,
                color: done
                    ? Colors.green.shade600
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    problem.displayLabel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chapterTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasNote)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.sticky_note_2_outlined,
                    size: 15,
                    color: Colors.indigo.shade400,
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: bookmarked ? '取消收藏' : '收藏本题',
                icon: Icon(
                  bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                  color: bookmarked ? Colors.amber.shade700 : null,
                ),
                onPressed: onToggleBookmark,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: done ? '标记为未完成' : '标记为已完成',
                icon: Icon(
                  done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  color: done ? Colors.green.shade600 : null,
                ),
                onPressed: onToggleDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.icon,
    required this.label,
    required this.highlight,
    this.isVideo = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isVideo
        ? Colors.indigo.withValues(alpha: 0.14)
        : highlight
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.7)
            : theme.colorScheme.surfaceContainerHighest;
    final fg = isVideo
        ? Colors.indigo.shade700
        : highlight
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 卡片内题干：内容不超框时按普通文本展示（全局滑动不受影响），
/// 溢出时才启用内部滚动，供用户查看完整题干。
class _OverflowScrollText extends StatelessWidget {
  const _OverflowScrollText({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.height > constraints.maxHeight + 0.5;
        if (!overflows) {
          return Text(text, style: style);
        }
        return SingleChildScrollView(
          child: Text(text, style: style),
        );
      },
    );
  }
}
