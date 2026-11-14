import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/curriculum_repository.dart';
import '../models/curriculum.dart';
import 'problem_workspace_page.dart';

/// Aggregation mode of the notes page: one card per problem (bookmarks and
/// notes combined), or one card per sticky note with its full text.
enum NotesView { byProblem, byNote }

/// 笔记 destination: aggregates bookmarked problems and problems carrying a
/// sticky note, switchable between a per-problem and a per-note view. Shown
/// as a shell tab only when the user enables it in settings (default off).
class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.repo});

  final CurriculumRepository repo;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  NotesView _view = NotesView.byProblem;

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

  /// Problems that are bookmarked and/or carry a note, in curriculum order.
  List<Problem> _collectedProblems(Curriculum c) {
    return c.problems
        .where((p) =>
            widget.repo.isBookmarked(p.id) ||
            widget.repo.noteFor(p.id).isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final repo = widget.repo;
        final theme = Theme.of(context);
        final curriculum = repo.curriculum;
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        if (curriculum == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final noted = curriculum.problems
            .where((p) => repo.noteFor(p.id).isNotEmpty)
            .toList(growable: false);
        final collected = _collectedProblems(curriculum);

        return Scaffold(
          appBar: AppBar(
            title: const Text('笔记'),
            actions: [
              IconButton(
                tooltip: repo.notesViewStyle == 'card'
                    ? '切换为列表视图'
                    : '切换为卡片视图',
                icon: Icon(
                  repo.notesViewStyle == 'card'
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                ),
                onPressed: () => repo.setNotesViewStyle(
                  repo.notesViewStyle == 'card' ? 'list' : 'card',
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '收藏 ${repo.bookmarkedIds.length} · 便签 ${noted.length} · 合计 ${collected.length} 题',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<NotesView>(
                            segments: const [
                              ButtonSegment(
                                value: NotesView.byProblem,
                                icon: Icon(Icons.library_books_outlined, size: 17),
                                label: Text('按题目'),
                              ),
                              ButtonSegment(
                                value: NotesView.byNote,
                                icon: Icon(Icons.sticky_note_2_outlined, size: 17),
                                label: Text('按便签'),
                              ),
                            ],
                            selected: {_view},
                            onSelectionChanged: (selection) =>
                                setState(() => _view = selection.first),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                  if (collected.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyNotesHint(),
                    )
                  else if (_view == NotesView.byProblem)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16, 4, 16,
                        math.max(24.0, bottomInset),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final problem = collected[index];
                            final note = repo.noteFor(problem.id);
                            if (repo.notesViewStyle == 'list') {
                              return _NoteProblemRow(
                                problem: problem,
                                chapterTitle:
                                    curriculum.chapterById(problem.chapterId).title,
                                bookmarked: repo.isBookmarked(problem.id),
                                done: repo.isCompleted(problem.id),
                                hasNote: note.isNotEmpty,
                                onTap: () => _openProblem(curriculum, problem),
                                onToggleBookmark: () =>
                                    repo.toggleBookmarked(problem.id),
                              );
                            }
                            return _ProblemNoteCard(
                              problem: problem,
                              chapterTitle:
                                  curriculum.chapterById(problem.chapterId).title,
                              bookmarked: repo.isBookmarked(problem.id),
                              done: repo.isCompleted(problem.id),
                              note: note,
                              onTap: () => _openProblem(curriculum, problem),
                              onToggleBookmark: () =>
                                  repo.toggleBookmarked(problem.id),
                            );
                          },
                          childCount: collected.length,
                        ),
                      ),
                    )
                  else if (noted.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16, 4, 16,
                        math.max(24.0, bottomInset),
                      ),
                      sliver: SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            '还没有写过便签，打开题目后在右侧详情面板即可添加。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16, 4, 16,
                        math.max(24.0, bottomInset),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final problem = noted[index];
                            final note = repo.noteFor(problem.id);
                            Future<void> onDelete() async {
                              final messenger = ScaffoldMessenger.of(context);
                              await repo.setNote(problem.id, '');
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '已删除 ${problem.displayLabel} 的便签'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                            if (repo.notesViewStyle == 'list') {
                              return _NoteEntryRow(
                                problem: problem,
                                note: note,
                                onTap: () => _openProblem(curriculum, problem),
                                onDelete: onDelete,
                              );
                            }
                            return _NoteCard(
                              problem: problem,
                              chapterTitle:
                                  curriculum.chapterById(problem.chapterId).title,
                              note: note,
                              onTap: () => _openProblem(curriculum, problem),
                              onDelete: onDelete,
                            );
                          },
                          childCount: noted.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyNotesHint extends StatelessWidget {
  const _EmptyNotesHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 44,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有收藏或便签',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '在题库中点 ☆ 收藏题目，或在解题页右侧添加便签，\n它们会自动汇总到这里。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 按题目视图：收藏与便签聚合在一张题目卡片上。
class _ProblemNoteCard extends StatelessWidget {
  const _ProblemNoteCard({
    required this.problem,
    required this.chapterTitle,
    required this.bookmarked,
    required this.done,
    required this.note,
    required this.onTap,
    required this.onToggleBookmark,
  });

  final Problem problem;
  final String chapterTitle;
  final bool bookmarked;
  final bool done;
  final String note;
  final VoidCallback onTap;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
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
                  Container(
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
                  if (note.isNotEmpty)
                    _CountBadge(
                      icon: Icons.sticky_note_2_outlined,
                      tooltip: '含便签',
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
                  Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 18,
                    color: done
                        ? Colors.green.shade600
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 按便签视图：每条便签一张卡片，展示全文并可快捷删除。
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.problem,
    required this.chapterTitle,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final Problem problem;
  final String chapterTitle;
  final String note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
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
                    tooltip: '删除便签',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 按题目视图的紧凑行：收藏星标 + 便签/完成状态单行展示。
class _NoteProblemRow extends StatelessWidget {
  const _NoteProblemRow({
    required this.problem,
    required this.chapterTitle,
    required this.bookmarked,
    required this.done,
    required this.hasNote,
    required this.onTap,
    required this.onToggleBookmark,
  });

  final Problem problem;
  final String chapterTitle;
  final bool bookmarked;
  final bool done;
  final bool hasNote;
  final VoidCallback onTap;
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
                bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                size: 17,
                color: bookmarked
                    ? Colors.amber.shade700
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Text(
                problem.displayLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                size: 17,
                color: done
                    ? Colors.green.shade600
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按便签视图的紧凑行：题号 + 单行便签摘要 + 快捷删除。
class _NoteEntryRow extends StatelessWidget {
  const _NoteEntryRow({
    required this.problem,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final Problem problem;
  final String note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
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
                Icons.sticky_note_2_outlined,
                size: 15,
                color: Colors.indigo.shade400,
              ),
              const SizedBox(width: 8),
              Text(
                problem.displayLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: '删除便签',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
