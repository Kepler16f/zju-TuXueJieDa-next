import 'package:flutter/material.dart';

import 'data/curriculum_repository.dart';
import 'pages/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TuxueJiedaApp());
}

class TuxueJiedaApp extends StatefulWidget {
  const TuxueJiedaApp({super.key});

  @override
  State<TuxueJiedaApp> createState() => _TuxueJiedaAppState();
}

class _TuxueJiedaAppState extends State<TuxueJiedaApp> {
  final CurriculumRepository _repo = CurriculumRepository();

  @override
  void initState() {
    super.initState();
    _repo.initialize();
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F4E8C);
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        return MaterialApp(
          title: '图学基础教程习题解答',
          debugShowCheckedModeBanner: false,
          themeMode: _repo.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'AppSansCJK',
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            fontFamily: 'AppSansCJK',
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
          ),
          home: AppShell(repo: _repo),
        );
      },
    );
  }
}
