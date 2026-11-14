import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/curriculum_repository.dart';
import '../services/orientation_service.dart';
import '../services/update_service.dart';
import '../services/window_channel.dart';
import 'home_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';

/// Responsive application shell hosting the top-level destinations
/// (题库 / 笔记 / 设置; the 笔记 tab is opt-in via settings). Wide layouts use a
/// leading NavigationRail with visible labels; narrow layouts fall back to a
/// bottom NavigationBar. Workspace pages are pushed fullscreen above this
/// shell.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.repo});

  final CurriculumRepository repo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Same breakpoint as the workspace desktop layout.
  static const _desktopBreakpoint = 960.0;

  final UpdateService _updateService = UpdateService();

  int _selectedIndex = 0;
  bool _platformPrefsApplied = false;

  @override
  void initState() {
    super.initState();
    // Android full-screen edge-to-edge: content extends behind the status and
    // navigation bars (overlay colors are pinned in build via AnnotatedRegion).
    // Other platforms ignore this call, so it is guarded explicitly.
    if (!kIsWeb && Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    widget.repo.addListener(_maybeApplyPlatformPrefs);
    _maybeApplyPlatformPrefs();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_maybeApplyPlatformPrefs);
    _updateService.close();
    super.dispose();
  }

  /// Applies tray / rotation prefs once persisted settings have finished
  /// loading (they are read asynchronously by [CurriculumRepository.initialize]).
  void _maybeApplyPlatformPrefs() {
    if (_platformPrefsApplied || widget.repo.isLoading) return;
    _platformPrefsApplied = true;
    _applyPlatformPrefs();
  }

  Future<void> _applyPlatformPrefs() async {
    if (kIsWeb) return;
    if (Platform.isWindows) {
      await WindowChannel.setCloseToTray(widget.repo.closeToTray);
    } else if (Platform.isAndroid) {
      await OrientationService.apply(followSensor: widget.repo.followSensor);
    }
  }

  void _onDestinationSelected(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    // Listens to the repo so toggling the notes-tab preference in settings
    // adds / removes the destination immediately.
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final pages = <Widget>[
          HomePage(repo: widget.repo),
          if (widget.repo.showNotesTab) NotesPage(repo: widget.repo),
          SettingsPage(repo: widget.repo, updateService: _updateService),
        ];
        // The tab list can shrink under the current selection (e.g. turning
        // the notes tab off while viewing it); clamp to stay in range.
        final selectedIndex = _selectedIndex.clamp(0, pages.length - 1);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
              final destinations = _buildDestinations();

              if (isDesktop) {
                return Scaffold(
                  body: Row(
                    children: [
                      _buildNavigationRail(theme, destinations),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: IndexedStack(
                          index: selectedIndex,
                          children: pages,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // extendBody lets the pages scroll behind the NavigationBar; the
              // scaffold re-exposes the bar height (inset included) as the
              // body's bottom padding, which the pages add to their scroll
              // padding.
              return Scaffold(
                extendBody: true,
                body: IndexedStack(index: selectedIndex, children: pages),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: _onDestinationSelected,
                  destinations: destinations
                      .map((d) => NavigationDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: d.label,
                          ))
                      .toList(growable: false),
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<_ShellDestination> _buildDestinations() {
    return [
      const _ShellDestination(
        icon: Icons.library_books_outlined,
        selectedIcon: Icons.library_books_rounded,
        label: '题库',
      ),
      if (widget.repo.showNotesTab)
        const _ShellDestination(
          icon: Icons.sticky_note_2_outlined,
          selectedIcon: Icons.sticky_note_2_rounded,
          label: '笔记',
        ),
      const _ShellDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: '设置',
      ),
    ];
  }

  Widget _buildNavigationRail(
    ThemeData theme,
    List<_ShellDestination> destinations,
  ) {
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.architecture_rounded,
                size: 22,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: _selectedIndex.clamp(0, destinations.length - 1),
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: const SizedBox(height: 4),
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + label pair for one shell destination, shared by the rail and the
/// bottom bar so both layouts always stay in sync.
class _ShellDestination {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
