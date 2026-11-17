import 'package:flutter/material.dart';

import 'dart:async';

import 'data/curriculum_repository.dart';
import 'pages/app_shell.dart';
import 'pages/consent_page.dart';
import 'services/consent_service.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(NotificationService.instance.init());
  runApp(const TuxueJiedaApp());
}

class TuxueJiedaApp extends StatefulWidget {
  const TuxueJiedaApp({super.key});

  @override
  State<TuxueJiedaApp> createState() => _TuxueJiedaAppState();
}

class _TuxueJiedaAppState extends State<TuxueJiedaApp> {
  final CurriculumRepository _repo = CurriculumRepository();

  /// 授权状态检查是否完成（未完成前显示启动页）。
  bool _consentResolved = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _repo.initialize();
    _resolveConsent();
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  Future<void> _resolveConsent() async {
    final agreed = await ConsentService().hasAgreed();
    if (!mounted) return;
    setState(() {
      _agreed = agreed;
      _consentResolved = true;
    });
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
          home: !_consentResolved
              ? const _StartupScreen()
              : (_agreed
                  ? AppShell(repo: _repo)
                  : ConsentPage(onAgreed: _onConsentAgreed)),
        );
      },
    );
  }

  Future<void> _onConsentAgreed() async {
    if (!mounted) return;
    setState(() => _agreed = true);
  }
}

/// 授权状态检查期间的启动页（极简，避免闪白）。
class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.architecture_rounded,
              size: 52,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '图学习题解答',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
