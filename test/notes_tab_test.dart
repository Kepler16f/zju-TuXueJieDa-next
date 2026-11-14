import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuxuejieda_next/data/curriculum_repository.dart';
import 'package:tuxuejieda_next/pages/app_shell.dart';
import 'package:tuxuejieda_next/pages/home_page.dart';
import 'package:tuxuejieda_next/pages/notes_page.dart';

/// Notes-tab feature: repository toggle persistence and the aggregated
/// notes page (per-problem / per-note views).
void main() {
  // initialize() performs real asset I/O, which only completes inside
  // tester.runAsync(); plain awaits deadlock the fake-async test zone.
  Future<CurriculumRepository> makeRepo(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(prefs);
    final repo = CurriculumRepository();
    await tester.runAsync(() => repo.initialize());
    return repo;
  }

  group('CurriculumRepository.showNotesTab', () {
    testWidgets('defaults to false and persists the user choice', (tester) async {
      // The mock MUST be installed before initialize(): without it the
      // plugin channel call never resolves in flutter_tester and the suite
      // hangs (observed 45 min idle dartvm on this machine).
      SharedPreferences.setMockInitialValues(<String, Object>{});
      CurriculumRepository repo = CurriculumRepository();
      await tester.runAsync(() => repo.initialize());
      expect(repo.showNotesTab, isFalse);

      await repo.setShowNotesTab(true);
      expect(repo.showNotesTab, isTrue);

      // Simulated restart: the preference must survive re-initialization.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ui_show_notes_tab': true,
      });
      repo = CurriculumRepository();
      await tester.runAsync(() => repo.initialize());
      expect(repo.showNotesTab, isTrue);
    });
  });

  group('CurriculumRepository.noteEntries', () {
    testWidgets('exposes stored notes and removes them on empty writes', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{});
      await repo.setNote('13_1', '辅助线从对角线入手');
      expect(repo.noteEntries['13_1'], '辅助线从对角线入手');
      expect(
        () => repo.noteEntries.remove('13_1'),
        throwsUnsupportedError,
        reason: 'noteEntries must be unmodifiable',
      );

      await repo.setNote('13_1', '  ');
      expect(repo.noteEntries.containsKey('13_1'), isFalse,
          reason: 'blank note text clears the entry');
    });
  });

  group('collection view styles', () {
    testWidgets('题库 and 笔记 view styles are stored independently', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{});
      expect(repo.problemViewStyle, 'card');
      expect(repo.notesViewStyle, 'card');

      await repo.setProblemViewStyle('list');
      expect(repo.problemViewStyle, 'list');
      expect(repo.notesViewStyle, 'card',
          reason: '两页的视图偏好不得耦合');

      await repo.setNotesViewStyle('list');
      await repo.setProblemViewStyle('card');
      expect(repo.notesViewStyle, 'list');
      expect(repo.problemViewStyle, 'card');

      // Simulated restart: both preferences persist independently.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ui_problem_view_style': 'list',
        'ui_notes_view_style': 'card',
      });
      final restored = CurriculumRepository();
      await tester.runAsync(() => restored.initialize());
      expect(restored.problemViewStyle, 'list');
      expect(restored.notesViewStyle, 'card');
    });

    testWidgets('HomePage switches between card grid and compact list', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{'ui_problem_view_style': 'list'});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(home: HomePage(repo: repo)));
      await tester.pumpAndSettle();

      // 列表视图不渲染卡片特有的迷你标签（避开筛选 chip 文案"分步 / 多视图"）。
      expect(find.textContaining(RegExp('分步 \\d+ 步')), findsNothing);
      expect(find.textContaining(RegExp('多视图 \\d+ 项')), findsNothing);

      await repo.setProblemViewStyle('card');
      await tester.pumpAndSettle();
      // 首张卡片 13_1 为分步题，应渲染出"分步 N 步"标签。
      expect(find.textContaining(RegExp('分步 \\d+ 步')), findsWidgets);
    });
  });

  group('AppShell destinations', () {
    testWidgets('notes tab hidden by default', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{});
      await tester.pumpWidget(MaterialApp(home: AppShell(repo: repo)));
      await tester.pumpAndSettle();
      expect(find.text('笔记'), findsNothing);
    });

    testWidgets('notes tab appears when enabled and opens the notes page', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{'ui_show_notes_tab': true});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(home: AppShell(repo: repo)));
      await tester.pumpAndSettle();
      expect(find.text('笔记'), findsWidgets);

      await tester.tap(find.text('笔记').first);
      await tester.pumpAndSettle();
      expect(find.text('按题目'), findsOneWidget);
      expect(find.text('按便签'), findsOneWidget);
    });
  });

  group('NotesPage aggregation', () {
    testWidgets('collects bookmarks and notes; note view deletes entries', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{});
      await repo.toggleBookmarked('13_1');
      await repo.setNote('36_7_n', '注意相贯线取公共部分');

      await tester.pumpWidget(MaterialApp(home: NotesPage(repo: repo)));
      await tester.pumpAndSettle();

      expect(find.text('收藏 1 · 便签 1 · 合计 2 题'), findsOneWidget);
      // 按题目 view shows the note as a preview under its problem.
      expect(find.textContaining('注意相贯线'), findsOneWidget);

      await tester.tap(find.text('按便签'));
      await tester.pumpAndSettle();
      expect(find.text('注意相贯线取公共部分'), findsOneWidget);

      await tester.tap(find.byTooltip('删除便签'));
      await tester.pumpAndSettle();
      expect(repo.noteEntries.containsKey('36_7_n'), isFalse);
      expect(find.textContaining('已删除'), findsOneWidget);
    });

    testWidgets('shows an empty hint when nothing is collected', (tester) async {
      final repo = await makeRepo(tester, <String, Object>{});
      await tester.pumpWidget(MaterialApp(home: NotesPage(repo: repo)));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏或便签'), findsOneWidget);
    });
  });
}
