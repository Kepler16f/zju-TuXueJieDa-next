import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/curriculum_repository.dart';
import '../models/curriculum.dart';
import '../widgets/problem_video_player.dart';
import '../widgets/sticky_note_card.dart';
import '../widgets/zoomable_diagram_canvas.dart';

enum WorkspaceTab { subject, answer, jieti, video }

/// Interactive problem study workbench featuring side-by-side chapter navigation,
/// zoomable blueprint stage, 原题↔答案 instant peek comparison, stepped/tabbed
/// solution player, XMED text notes, and unified H.264 video playback.
class ProblemWorkspacePage extends StatefulWidget {
  const ProblemWorkspacePage({
    super.key,
    required this.repo,
    required this.curriculum,
    required this.initialProblem,
  });

  final CurriculumRepository repo;
  final Curriculum curriculum;
  final Problem initialProblem;

  @override
  State<ProblemWorkspacePage> createState() => _ProblemWorkspacePageState();
}

class _ProblemWorkspacePageState extends State<ProblemWorkspacePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late Problem _problem;
  late List<Problem> _chapterProblems;
  WorkspaceTab _tab = WorkspaceTab.jieti;
  int _stepIdx = 0;
  bool _peekingCompare = false;
  bool _showNavSidebar = true;
  bool _showDetailSidebar = true;
  bool _autoPlayingSteps = false;
  Timer? _autoPlayTimer;

  /// Horizontal scroll controller for the toolbar tab segments. It only
  /// becomes active when the window is too narrow to show every segment
  /// without squeezing the labels onto two lines.
  final ScrollController _toolbarTabsController = ScrollController();

  /// Guarded tab view: the 解题 tab stays reachable only when the problem
  /// carries more than 3 steps (its segment is hidden otherwise).
  WorkspaceTab get _effectiveTab =>
      (_tab == WorkspaceTab.jieti && _problem.steps.length <= 3)
          ? WorkspaceTab.answer
          : _tab;

  @override
  void initState() {
    super.initState();
    _selectProblem(widget.initialProblem, initial: true);
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _toolbarTabsController.dispose();
    super.dispose();
  }

  void _selectProblem(Problem p, {bool initial = false}) {
    _stopAutoPlay();
    setState(() {
      _problem = p;
      _chapterProblems = widget.curriculum.problemsInChapter(p.chapterId);
      _stepIdx = 0;
      _peekingCompare = false;
      // Keep the 解题 tab only for problems with more than 3 steps.
      _tab = p.steps.length > 3 ? WorkspaceTab.jieti : WorkspaceTab.answer;
    });
    if (initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.repo.markOpened(p.id);
      });
    } else {
      widget.repo.markOpened(p.id);
    }
  }

  void _navigateProblemDelta(int delta) {
    final idx = _chapterProblems.indexWhere((p) => p.id == _problem.id);
    if (idx == -1) return;
    final nextIdx = idx + delta;
    if (nextIdx >= 0 && nextIdx < _chapterProblems.length) {
      _selectProblem(_chapterProblems[nextIdx]);
    }
  }

  void _stepDelta(int delta) {
    if (_problem.steps.isEmpty) return;
    final next = (_stepIdx + delta).clamp(0, _problem.steps.length - 1);
    if (next != _stepIdx) {
      setState(() => _stepIdx = next);
    }
  }

  void _toggleAutoPlay() {
    if (_autoPlayingSteps) {
      _stopAutoPlay();
      return;
    }
    if (_problem.steps.length <= 3) return;
    setState(() {
      _tab = WorkspaceTab.jieti;
      _autoPlayingSteps = true;
      if (_stepIdx >= _problem.steps.length - 1) {
        _stepIdx = 0;
      }
    });
    _autoPlayTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      if (_stepIdx < _problem.steps.length - 1) {
        setState(() => _stepIdx++);
      } else {
        _stopAutoPlay();
      }
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    if (_autoPlayingSteps && mounted) {
      setState(() => _autoPlayingSteps = false);
    } else {
      _autoPlayingSteps = false;
    }
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制$label'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final theme = Theme.of(context);
        final chapter = widget.curriculum.chapterById(_problem.chapterId);
        final idxInChapter = _chapterProblems.indexWhere((p) => p.id == _problem.id);
        final hasPrev = idxInChapter > 0;
        final hasNext = idxInChapter >= 0 && idxInChapter < _chapterProblems.length - 1;
        final done = widget.repo.isCompleted(_problem.id);
        final bookmarked = widget.repo.isBookmarked(_problem.id);

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              if (_effectiveTab == WorkspaceTab.jieti) _stepDelta(-1);
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              if (_effectiveTab == WorkspaceTab.jieti) _stepDelta(1);
            },
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _navigateProblemDelta(-1),
            const SingleActivator(LogicalKeyboardKey.pageDown): () => _navigateProblemDelta(1),
            const SingleActivator(LogicalKeyboardKey.space): () {
              if (_effectiveTab != WorkspaceTab.video) {
                setState(() => _peekingCompare = !_peekingCompare);
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 960;
                // Below ~400 px five 48 px AppBar action buttons would leave
                // the title row less than its own 本章题单 menu button wide
                // (RenderFlex overflow); 上一题/下一题 relocate into the
                // toolbar row instead.
                final isCompact = constraints.maxWidth < 400;

                return Scaffold(
                  key: _scaffoldKey,
                  drawer: !isDesktop
                      ? Drawer(
                          child: _ProblemNavList(
                            chapterTitle: chapter.title,
                            problems: _chapterProblems,
                            activeId: _problem.id,
                            repo: widget.repo,
                            onSelect: (p) {
                              Navigator.of(context).pop();
                              _selectProblem(p);
                            },
                          ),
                        )
                      : null,
                  endDrawer: !isDesktop
                      ? Drawer(
                          child: SafeArea(
                            bottom: false,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '题目详情与便签',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '收起详情面板',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _ProblemDetailPanel(
                                    problem: _problem,
                                    activeStep: (_effectiveTab == WorkspaceTab.jieti &&
                                            _stepIdx < _problem.steps.length)
                                        ? _problem.steps[_stepIdx]
                                        : null,
                                    repo: widget.repo,
                                    onCopy: _copyText,
                                    noteEditorInDialog: !isDesktop,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                  appBar: AppBar(
                    titleSpacing: 8,
                    leading: IconButton(
                      tooltip: '返回题库首页',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    title: Row(
                      children: [
                        if (!isDesktop)
                          IconButton(
                            tooltip: '本章题单',
                            icon: const Icon(Icons.menu_rounded),
                            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _problem.displayLabel,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${chapter.title} (${idxInChapter + 1}/${_chapterProblems.length}) · #${_problem.id}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // 上一题/下一题 are dropped here on very narrow screens
                      // and reappear next to the compare button in the toolbar
                      // (see _buildToolbar); chapter paging also remains
                      // available via the 本章题单 drawer and PageUp/PageDown.
                      if (!isCompact) ...[
                        IconButton(
                          tooltip: '上一题 (PageUp)',
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: hasPrev ? () => _navigateProblemDelta(-1) : null,
                        ),
                        IconButton(
                          tooltip: '下一题 (PageDown)',
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: hasNext ? () => _navigateProblemDelta(1) : null,
                        ),
                      ],
                      IconButton(
                        tooltip: bookmarked ? '取消收藏' : '收藏',
                        icon: Icon(
                          bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                          color: bookmarked ? Colors.amber.shade700 : null,
                        ),
                        onPressed: () => widget.repo.toggleBookmarked(_problem.id),
                      ),
                      IconButton(
                        tooltip: done ? '已完成' : '标记完成',
                        icon: Icon(
                          done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                          color: done ? Colors.green.shade600 : null,
                        ),
                        onPressed: () => widget.repo.toggleCompleted(_problem.id),
                      ),
                      if (isDesktop) ...[
                        // NOTE: Icons.left_panel_close/open_rounded and
                        // right_panel_close/open_rounded are not yet shipped in
                        // this Flutter SDK's Icons; view_sidebar / chrome_reader_mode
                        // (filled = visible, outlined = hidden) are the closest
                        // available stand-ins.
                        IconButton(
                          tooltip: _showNavSidebar ? '收起左侧题单栏' : '显示左侧题单栏',
                          icon: Icon(
                            _showNavSidebar
                                ? Icons.view_sidebar_rounded
                                : Icons.view_sidebar_outlined,
                          ),
                          onPressed: () => setState(() => _showNavSidebar = !_showNavSidebar),
                        ),
                        IconButton(
                          tooltip: _showDetailSidebar ? '收起右侧详情栏' : '显示右侧详情栏',
                          icon: Icon(
                            _showDetailSidebar
                                ? Icons.chrome_reader_mode_rounded
                                : Icons.chrome_reader_mode_outlined,
                          ),
                          onPressed: () => setState(() => _showDetailSidebar = !_showDetailSidebar),
                        ),
                      ] else
                        IconButton(
                          tooltip: '题目详情与便签',
                          icon: const Icon(Icons.description_rounded),
                          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  body: Row(
                    children: [
                      if (isDesktop && _showNavSidebar) ...[
                        SizedBox(
                          width: 265,
                          child: _ProblemNavList(
                            chapterTitle: chapter.title,
                            problems: _chapterProblems,
                            activeId: _problem.id,
                            repo: widget.repo,
                            onSelect: _selectProblem,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: Column(
                          children: [
                            _buildToolbar(
                              theme,
                              showNavArrows: isCompact,
                              hasPrev: hasPrev,
                              hasNext: hasNext,
                            ),
                            const Divider(height: 1),
                            if (!isDesktop) _buildStatementBanner(theme),
                            Expanded(child: _buildMainStage()),
                            if (_effectiveTab == WorkspaceTab.jieti &&
                                _problem.steps.length > 3)
                              _buildJietiControls(theme),
                          ],
                        ),
                      ),
                      if (isDesktop && _showDetailSidebar) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 300,
                          child: _ProblemDetailPanel(
                            problem: _problem,
                            activeStep: (_effectiveTab == WorkspaceTab.jieti &&
                                    _stepIdx < _problem.steps.length)
                                ? _problem.steps[_stepIdx]
                                : null,
                            repo: widget.repo,
                            onCopy: _copyText,
                            noteEditorInDialog: false,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 竖屏/窄屏：把题干直接并入主界面（图片上方），替代抽屉里的"题目要求"。
  /// 长题干在限高区域内内部滚动，图片始终占据剩余空间。
  Widget _buildStatementBanner(ThemeData theme) {
    if (_problem.statement.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 132),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            child: Text(
              _problem.statement,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(
    ThemeData theme, {
    required bool showNavArrows,
    required bool hasPrev,
    required bool hasNext,
  }) {
    // maxLines:1/softWrap:false keeps every segment label on a single line;
    // combined with the horizontal SingleChildScrollView below this guarantees
    // one-line labels from 320 px phones to ultra-wide desktop windows (a
    // squeezed SegmentedButton used to wrap 解题(9) / 动画视频 onto two lines).
    final segments = <ButtonSegment<WorkspaceTab>>[
      const ButtonSegment(
        value: WorkspaceTab.subject,
        icon: Icon(Icons.image_outlined, size: 17),
        label: Text('原题', maxLines: 1, softWrap: false),
      ),
      const ButtonSegment(
        value: WorkspaceTab.answer,
        icon: Icon(Icons.verified_outlined, size: 17),
        label: Text('答案', maxLines: 1, softWrap: false),
      ),
      if (_problem.steps.length > 3)
        ButtonSegment(
          value: WorkspaceTab.jieti,
          icon: Icon(
            _problem.jietiMode == JietiMode.tabbed
                ? Icons.view_carousel_outlined
                : Icons.stairs_outlined,
            size: 17,
          ),
          label: Text(
            _problem.jietiMode == JietiMode.tabbed
                ? '多视图(${_problem.steps.length})'
                : '解题(${_problem.steps.length})',
            maxLines: 1,
            softWrap: false,
          ),
        ),
      if (_problem.hasVideo)
        const ButtonSegment(
          value: WorkspaceTab.video,
          icon: Icon(Icons.play_circle_outline_rounded, size: 17),
          label: Text('动画视频', maxLines: 1, softWrap: false),
        ),
    ];

    final compareButton = _effectiveTab == WorkspaceTab.video
        ? const SizedBox.shrink()
        : GestureDetector(
            onTapDown: (_) => setState(() => _peekingCompare = true),
            onTapUp: (_) => setState(() => _peekingCompare = false),
            onTapCancel: () => setState(() => _peekingCompare = false),
            child: FilledButton.tonalIcon(
              onPressed: () => setState(() => _peekingCompare = !_peekingCompare),
              icon: Icon(
                _peekingCompare ? Icons.compare_rounded : Icons.flip_rounded,
                size: 17,
              ),
              label: Text(
                _effectiveTab == WorkspaceTab.subject
                    ? (_peekingCompare ? '看原题' : '按住/点按对比答案')
                    : (_peekingCompare ? '看回当前' : '按住/点按对比原题'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );

    // Compact AppBar (<400 px): the 上一题/下一题 paging icons live here so
    // one-tap paging stays available on phones.
    final pagingButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '上一题 (PageUp)',
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: hasPrev ? () => _navigateProblemDelta(-1) : null,
        ),
        const SizedBox(width: 2),
        IconButton(
          tooltip: '下一题 (PageDown)',
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: hasNext ? () => _navigateProblemDelta(1) : null,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surface,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // The segmented control keeps its intrinsic width and scrolls
          // horizontally when the available width is insufficient; the
          // scrollbar thumb only appears when it actually overflows.
          Scrollbar(
            controller: _toolbarTabsController,
            child: SingleChildScrollView(
              controller: _toolbarTabsController,
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<WorkspaceTab>(
                segments: segments,
                selected: {_effectiveTab},
                onSelectionChanged: (sel) {
                  _stopAutoPlay();
                  setState(() {
                    _tab = sel.first;
                    _peekingCompare = false;
                  });
                },
              ),
            ),
          ),
          compareButton,
          if (showNavArrows) pagingButtons,
        ],
      ),
    );
  }

  Widget _buildMainStage() {
    if (_tab == WorkspaceTab.video && _problem.video != null) {
      return ProblemVideoPlayer(
        assetPath: _problem.video!.asset,
        sourceName: _problem.video!.sourceAvi,
      );
    }

    String primaryAsset;
    String compareAsset;
    String compareLabel;

    switch (_effectiveTab) {
      case WorkspaceTab.subject:
        primaryAsset = _problem.subjectImage;
        compareAsset = _problem.answerImage;
        compareLabel = '标准答案';
      case WorkspaceTab.answer:
        primaryAsset = _problem.answerImage;
        compareAsset = _problem.subjectImage;
        compareLabel = '原题题面';
      case WorkspaceTab.jieti:
        if (_problem.steps.isEmpty) {
          // Defensive: never index into an empty step list.
          primaryAsset = _problem.answerImage;
        } else {
          final safeIdx = _stepIdx.clamp(0, _problem.steps.length - 1);
          primaryAsset = _problem.steps[safeIdx].image;
        }
        compareAsset = _problem.subjectImage;
        compareLabel = '原题题面';
      case WorkspaceTab.video:
        primaryAsset = _problem.answerImage;
        compareAsset = _problem.subjectImage;
        compareLabel = '原题题面';
    }

    return ZoomableDiagramCanvas(
      primaryAsset: primaryAsset,
      compareAsset: compareAsset,
      compareLabel: compareLabel,
      isPeekingCompare: _peekingCompare,
    );
  }

  Widget _buildJietiControls(ThemeData theme) {
    final steps = _problem.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final safeIdx = _stepIdx.clamp(0, steps.length - 1);
    final current = steps[safeIdx];
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final stepTitleStyle =
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600) ??
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    final stepTitleText = '${current.title} (${safeIdx + 1}/${steps.length})';

    return Container(
      // Extend past the system navigation bar under Android edge-to-edge.
      padding: EdgeInsets.fromLTRB(12, 8, 12, 10 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Threshold: stack into two rows when the center column is narrow
          // (760 px baseline — e.g. a 960 px desktop window with both side
          // panels open leaves ~390 px) OR whenever the measured single-line
          // step title would not leave ~200 px of slider room in one row.
          // The title width is measured with the exact style + text scaler so
          // the single-row mode below can keep the title unflexible and let
          // the Expanded slider absorb the full remainder: no overlap, no
          // overflow, and no dead space, for any title length.
          final textScaler = MediaQuery.textScalerOf(context);
          final titlePainter = TextPainter(
            text: TextSpan(text: stepTitleText, style: stepTitleStyle),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            textScaler: textScaler,
          )..layout();
          final titleWidth = titlePainter.width;
          titlePainter.dispose();
          // Reset/prev/next/auto buttons + inter-row gaps (~308 px at scale 1,
          // only the button labels scale) plus a ~200 px slider minimum.
          final chromeBudget =
              224 * textScaler.scale(1.0) + 84 * textScaler.scale(14.0) / 14.0 + 200;
          final stacked =
              constraints.maxWidth < 760 ||
              constraints.maxWidth < titleWidth + chromeBudget;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (current.note.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '当前要点：${current.note}',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              if (_problem.jietiMode == JietiMode.tabbed)
                _buildTabbedStepChips(steps, safeIdx)
              else
                stacked
                    ? _buildStackedStepControls(
                        steps: steps,
                        safeIdx: safeIdx,
                        titleStyle: stepTitleStyle,
                        titleText: stepTitleText,
                      )
                    : _buildSingleRowStepControls(
                        steps: steps,
                        safeIdx: safeIdx,
                        titleStyle: stepTitleStyle,
                        titleText: stepTitleText,
                      ),
            ],
          );
        },
      ),
    );
  }

  /// 多视图 mode: horizontally scrollable ChoiceChip strip. Unaffected by
  /// window width (chips get unbounded width inside the scroller, so labels
  /// never wrap) and sits fine above the note banner on narrow screens.
  Widget _buildTabbedStepChips(List<SolutionStep> steps, int safeIdx) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            ChoiceChip(
              label: Text(steps[i].title, style: const TextStyle(fontSize: 12)),
              selected: i == safeIdx,
              onSelected: (_) => setState(() => _stepIdx = i),
              visualDensity: VisualDensity.compact,
            ),
            if (i < steps.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// Wide single row — same arrangement as before (reset / prev / title /
  /// slider / auto / next), with the title left unflexible so the Expanded
  /// slider absorbs the entire remainder. Safe because the stacked threshold
  /// above guarantees title + chrome + ~200 px of slider fit in one line.
  Widget _buildSingleRowStepControls({
    required List<SolutionStep> steps,
    required int safeIdx,
    required TextStyle titleStyle,
    required String titleText,
  }) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: '重置到第 1 步',
          icon: const Icon(Icons.first_page_rounded, size: 19),
          onPressed: safeIdx > 0 ? () => _stepDelta(-safeIdx) : null,
        ),
        const SizedBox(width: 4),
        FilledButton.tonalIcon(
          onPressed: safeIdx > 0 ? () => _stepDelta(-1) : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('上一步', maxLines: 1, softWrap: false),
        ),
        const SizedBox(width: 10),
        // Deliberately NOT wrapped in Flexible: an inflexible title takes its
        // exact intrinsic width, so the Expanded slider absorbs the *entire*
        // remainder (a Flexible title would cap the slider at its flex share
        // and strand dead space after 下一步 on wide windows). The stacked
        // threshold above guarantees this row always fits.
        Text(titleText, maxLines: 1, softWrap: false, style: titleStyle),
        Expanded(
          child: steps.length > 1
              ? Slider(
                  value: safeIdx.toDouble(),
                  min: 0,
                  max: (steps.length - 1).toDouble(),
                  divisions: steps.length - 1,
                  onChanged: (v) {
                    _stopAutoPlay();
                    setState(() => _stepIdx = v.round());
                  },
                )
              : const SizedBox.shrink(),
        ),
        IconButton.filledTonal(
          tooltip: _autoPlayingSteps ? '暂停自动步进' : '自动分步演示',
          icon: Icon(
            _autoPlayingSteps ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 19,
          ),
          onPressed: steps.length > 1 ? _toggleAutoPlay : null,
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: safeIdx < steps.length - 1 ? () => _stepDelta(1) : null,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('下一步', maxLines: 1, softWrap: false),
        ),
      ],
    );
  }

  /// Narrow two-row variant (320 px safe):
  /// row 1 = 重置 / 上一步 / 步骤标题(Expanded+ellipsis) / 下一步,
  /// row 2 = 滑块占满 / 自动步进.
  Widget _buildStackedStepControls({
    required List<SolutionStep> steps,
    required int safeIdx,
    required TextStyle titleStyle,
    required String titleText,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: '重置到第 1 步',
              icon: const Icon(Icons.first_page_rounded, size: 19),
              onPressed: safeIdx > 0 ? () => _stepDelta(-safeIdx) : null,
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: safeIdx > 0 ? () => _stepDelta(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              label: const Text('上一步', maxLines: 1, softWrap: false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titleText,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: safeIdx < steps.length - 1 ? () => _stepDelta(1) : null,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('下一步', maxLines: 1, softWrap: false),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: steps.length > 1
                  ? Slider(
                      value: safeIdx.toDouble(),
                      min: 0,
                      max: (steps.length - 1).toDouble(),
                      divisions: steps.length - 1,
                      onChanged: (v) {
                        _stopAutoPlay();
                        setState(() => _stepIdx = v.round());
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton.filledTonal(
              tooltip: _autoPlayingSteps ? '暂停自动步进' : '自动分步演示',
              icon: Icon(
                _autoPlayingSteps ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 19,
              ),
              onPressed: steps.length > 1 ? _toggleAutoPlay : null,
            ),
          ],
        ),
      ],
    );
  }

}

class _ProblemNavList extends StatelessWidget {
  const _ProblemNavList({
    required this.chapterTitle,
    required this.problems,
    required this.activeId,
    required this.repo,
    required this.onSelect,
  });

  final String chapterTitle;
  final List<Problem> problems;
  final String activeId;
  final CurriculumRepository repo;
  final void Function(Problem) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          // Clear the status bar when embedded in a fullscreen drawer.
          padding: EdgeInsets.fromLTRB(
            14,
            12 + MediaQuery.paddingOf(context).top,
            14,
            10,
          ),
          color: theme.colorScheme.surfaceContainerLow,
          child: Text(
            '$chapterTitle（${problems.length} 题）',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 8,
            ),
            itemCount: problems.length,
            itemBuilder: (context, index) {
              final p = problems[index];
              final selected = p.id == activeId;
              final done = repo.isCompleted(p.id);
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                leading: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: done
                      ? Colors.green.shade600
                      : selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                ),
                title: Text(
                  p.displayLabel,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                trailing: p.hasVideo
                    ? Icon(Icons.play_circle_outline_rounded, size: 16, color: Colors.indigo.shade600)
                    : null,
                onTap: () => onSelect(p),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProblemDetailPanel extends StatelessWidget {
  const _ProblemDetailPanel({
    required this.problem,
    required this.activeStep,
    required this.repo,
    required this.onCopy,
    required this.noteEditorInDialog,
  });

  final Problem problem;
  final SolutionStep? activeStep;
  final CurriculumRepository repo;
  final Future<void> Function(String text, String label) onCopy;

  /// 竖屏抽屉：便签通过弹窗输入/编辑（横屏侧栏为内联展开输入）。
  final bool noteEditorInDialog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepNotes = problem.steps
        .where((s) => s.note.isNotEmpty)
        .toList(growable: false);

    return SingleChildScrollView(
      // Clear the system navigation bar when used inside a fullscreen drawer.
      padding: EdgeInsets.fromLTRB(
        14, 14, 14,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '题目要求',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (problem.statement.isNotEmpty)
                IconButton(
                  tooltip: '复制题目文字',
                  iconSize: 18,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => onCopy(problem.statement, '题目要求'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SelectableText(
              problem.statement.isNotEmpty
                  ? problem.statement
                  : '本题未在旧版字库中附带纯文本描述，请直接查看图面与分步解答。',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ),
          const SizedBox(height: 16),
          StickyNoteCard(
            repo: repo,
            problemId: problem.id,
            editorInDialog: noteEditorInDialog,
          ),
          if (activeStep != null && activeStep!.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '当前步骤注释（${activeStep!.title}）',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                activeStep!.note,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
          ],
          if (stepNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '全部作图步骤注释',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final st in stepNotes) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      st.title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(st.note, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Text(
            '快捷提示',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '• 滚轮/双指缩放图纸，双击恢复默认比例\n'
            '• 空格键快速切换原题与当前图对比\n'
            '• 方向键 ← / → 切换解题步骤\n'
            '• PageUp / PageDown 切换上/下一题'
            '${problem.hasVideo ? '\n• 配套动画来源：${problem.video!.sourceAvi}' : ''}',
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
