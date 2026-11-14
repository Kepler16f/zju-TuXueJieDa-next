import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/curriculum.dart';

/// Loads curriculum metadata from bundled assets and persists user study state.
class CurriculumRepository extends ChangeNotifier {
  CurriculumRepository();

  static const _curriculumAsset = 'assets/data/curriculum.json';
  static const _prefCompleted = 'study_completed_ids';
  static const _prefBookmarked = 'study_bookmarked_ids';
  static const _prefLastProblem = 'study_last_problem_id';
  static const _prefThemeMode = 'ui_theme_mode';
  static const _prefLegacyDarkMode = 'ui_dark_mode';
  static const _prefNotes = 'study_notes';
  static const _prefCloseToTray = 'ui_close_to_tray';
  static const _prefFollowSensor = 'ui_follow_sensor';
  static const _prefShowNotesTab = 'ui_show_notes_tab';
  static const _prefProblemViewStyle = 'ui_problem_view_style';
  static const _prefNotesViewStyle = 'ui_notes_view_style';

  Curriculum? _curriculum;
  bool _loading = true;
  Object? _error;

  final Set<String> _completedIds = <String>{};
  final Set<String> _bookmarkedIds = <String>{};
  String? _lastProblemId;
  ThemeMode _themeMode = ThemeMode.system;
  final Map<String, String> _notes = <String, String>{};
  bool _closeToTray = true;
  bool _followSensor = true;
  bool _showNotesTab = false;

  /// Whether collection pages render rich cards ('card') or compact rows
  /// ('list'). The 题库 and 笔记 pages expose the same toggle feature but keep
  /// independent preferences on purpose (they must not be coupled).
  String _problemViewStyle = 'card';
  String _notesViewStyle = 'card';

  Curriculum? get curriculum => _curriculum;
  bool get isLoading => _loading;
  Object? get error => _error;
  Set<String> get completedIds => Set.unmodifiable(_completedIds);
  Set<String> get bookmarkedIds => Set.unmodifiable(_bookmarkedIds);
  String? get lastProblemId => _lastProblemId;
  ThemeMode get themeMode => _themeMode;
  bool get closeToTray => _closeToTray;
  bool get followSensor => _followSensor;
  bool get showNotesTab => _showNotesTab;
  String get problemViewStyle => _problemViewStyle;
  String get notesViewStyle => _notesViewStyle;
  int get noteCount => _notes.length;

  /// Read-only view of every stored note, keyed by problem id. Consumers
  /// (the notes page) must not mutate it; edits go through [setNote].
  Map<String, String> get noteEntries => Map.unmodifiable(_notes);

  bool isCompleted(String id) => _completedIds.contains(id);
  bool isBookmarked(String id) => _bookmarkedIds.contains(id);
  String noteFor(String id) => _notes[id] ?? '';

  Future<void> initialize() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final rawJson = await rootBundle.loadString(_curriculumAsset);
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      _curriculum = Curriculum.fromJson(decoded);

      final prefs = await SharedPreferences.getInstance();
      _completedIds
        ..clear()
        ..addAll(prefs.getStringList(_prefCompleted) ?? const []);
      _bookmarkedIds
        ..clear()
        ..addAll(prefs.getStringList(_prefBookmarked) ?? const []);
      _lastProblemId = prefs.getString(_prefLastProblem);
      _closeToTray = prefs.getBool(_prefCloseToTray) ?? true;
      _followSensor = prefs.getBool(_prefFollowSensor) ?? true;
      _showNotesTab = prefs.getBool(_prefShowNotesTab) ?? false;
      _problemViewStyle = _normalizeViewStyle(prefs.getString(_prefProblemViewStyle));
      _notesViewStyle = _normalizeViewStyle(prefs.getString(_prefNotesViewStyle));
      await _restoreThemeMode(prefs);
      _restoreNotes(prefs);
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markOpened(String problemId) async {
    if (_lastProblemId == problemId) return;
    _lastProblemId = problemId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastProblem, problemId);
  }

  Future<void> toggleCompleted(String problemId) async {
    if (!_completedIds.add(problemId)) {
      _completedIds.remove(problemId);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefCompleted, _completedIds.toList());
  }

  Future<void> toggleBookmarked(String problemId) async {
    if (!_bookmarkedIds.add(problemId)) {
      _bookmarkedIds.remove(problemId);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefBookmarked, _bookmarkedIds.toList());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefThemeMode, mode.name);
  }

  Future<void> setNote(String problemId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (!_notes.containsKey(problemId)) return;
      _notes.remove(problemId);
    } else {
      if (_notes[problemId] == trimmed) return;
      _notes[problemId] = trimmed;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNotes, jsonEncode(_notes));
  }

  Future<void> clearNotes() async {
    if (_notes.isEmpty) return;
    _notes.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNotes, jsonEncode(_notes));
  }

  Future<void> setCloseToTray(bool value) async {
    if (_closeToTray == value) return;
    _closeToTray = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefCloseToTray, value);
  }

  Future<void> setFollowSensor(bool value) async {
    if (_followSensor == value) return;
    _followSensor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefFollowSensor, value);
  }

  Future<void> setShowNotesTab(bool value) async {
    if (_showNotesTab == value) return;
    _showNotesTab = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowNotesTab, value);
  }

  Future<void> setProblemViewStyle(String value) =>
      _setViewStyle(_prefProblemViewStyle, value, (v) => _problemViewStyle = v);

  Future<void> setNotesViewStyle(String value) =>
      _setViewStyle(_prefNotesViewStyle, value, (v) => _notesViewStyle = v);

  Future<void> _setViewStyle(
    String prefKey,
    String value,
    void Function(String) assign,
  ) async {
    final next = _normalizeViewStyle(value);
    final current =
        prefKey == _prefProblemViewStyle ? _problemViewStyle : _notesViewStyle;
    if (current == next) return;
    assign(next);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, next);
  }

  static String _normalizeViewStyle(String? value) =>
      value == 'list' ? 'list' : 'card';

  Future<void> clearProgress() async {
    if (_completedIds.isEmpty && _lastProblemId == null) return;
    _completedIds.clear();
    _lastProblemId = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefCompleted);
    await prefs.remove(_prefLastProblem);
  }

  Future<void> clearBookmarks() async {
    if (_bookmarkedIds.isEmpty) return;
    _bookmarkedIds.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefBookmarked);
  }

  /// Restores the tri-state theme mode; migrates the legacy boolean
  /// `ui_dark_mode` key to the new `ui_theme_mode` key when needed.
  Future<void> _restoreThemeMode(SharedPreferences prefs) async {
    final stored = prefs.getString(_prefThemeMode);
    if (stored != null) {
      _themeMode = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      return;
    }
    final legacyDark = prefs.getBool(_prefLegacyDarkMode);
    if (legacyDark == null) return;
    _themeMode = legacyDark ? ThemeMode.dark : ThemeMode.light;
    await prefs.setString(_prefThemeMode, _themeMode.name);
    await prefs.remove(_prefLegacyDarkMode);
  }

  void _restoreNotes(SharedPreferences prefs) {
    _notes.clear();
    final raw = prefs.getString(_prefNotes);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) => _notes[key.toString()] = value.toString());
      }
    } catch (_) {
      // Ignore corrupted payloads and start with an empty notebook.
    }
  }
}
