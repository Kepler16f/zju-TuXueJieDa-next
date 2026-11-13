import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  static const _prefDarkMode = 'ui_dark_mode';

  Curriculum? _curriculum;
  bool _loading = true;
  Object? _error;

  final Set<String> _completedIds = <String>{};
  final Set<String> _bookmarkedIds = <String>{};
  String? _lastProblemId;
  bool _darkMode = false;

  Curriculum? get curriculum => _curriculum;
  bool get isLoading => _loading;
  Object? get error => _error;
  Set<String> get completedIds => Set.unmodifiable(_completedIds);
  Set<String> get bookmarkedIds => Set.unmodifiable(_bookmarkedIds);
  String? get lastProblemId => _lastProblemId;
  bool get darkMode => _darkMode;

  bool isCompleted(String id) => _completedIds.contains(id);
  bool isBookmarked(String id) => _bookmarkedIds.contains(id);

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
      _darkMode = prefs.getBool(_prefDarkMode) ?? false;
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

  Future<void> setDarkMode(bool value) async {
    if (_darkMode == value) return;
    _darkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDarkMode, value);
  }
}
