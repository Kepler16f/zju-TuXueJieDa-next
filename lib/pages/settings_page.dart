import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/curriculum_repository.dart';
import '../services/orientation_service.dart';
import '../services/platform_caps.dart';
import '../services/update_service.dart';
import '../services/window_channel.dart';
import '../widgets/update_dialog.dart';

/// Grouped settings page: appearance, platform window/screen options, study
/// data maintenance, and about info. Uses the shared [UpdateService] owned by
/// the app shell so update checks share one Dio client with the shell.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repo,
    required this.updateService,
  });

  final CurriculumRepository repo;
  final UpdateService updateService;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _repoUrl = 'https://github.com/Kepler16f/zju-TuXueJieDa-next';

  String _appVersion = '';

  bool get _isWindows => PlatformCaps.isWindows;
  bool get _isAndroid => PlatformCaps.isAndroid;
  bool get _isIOS => PlatformCaps.isIOS;
  bool get _isOhos => PlatformCaps.isOhos;
  bool get _isWeb => PlatformCaps.isWeb;

  /// 镜像下载设置（异步加载后落到本地状态）。
  bool _mirrorUse = true;
  int _mirrorIndex = 1;
  bool _mirrorLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadMirrorSettings();
  }

  Future<void> _loadMirrorSettings() async {
    final settings = await widget.updateService.loadMirrorSettings();
    if (!mounted) return;
    setState(() {
      _mirrorUse = settings.useMirror;
      _mirrorIndex = settings.mirrorIndex;
      _mirrorLoaded = true;
    });
  }

  Future<void> _saveMirrorSettings() async {
    await widget.updateService.setMirrorSettings(
      useMirror: _mirrorUse,
      index: _mirrorIndex,
    );
  }

  Future<void> _loadVersion() async {
    final version = await widget.updateService.getCurrentVersion();
    if (mounted) setState(() => _appVersion = version);
  }

  Future<void> _openRepository() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse(_repoUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('无法打开链接，请检查系统默认浏览器设置。')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('无法打开链接，请手动访问：$_repoUrl')),
      );
    }
  }

  Future<void> _clearWithConfirm({
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title完成'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final repo = widget.repo;
        final problemTotal = repo.curriculum?.problems.length ?? 0;
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16, 12, 16,
                  bottomInset < 24 ? 24 : bottomInset,
                ),
                children: [
                  const _SectionHeader('外观'),
                  _SettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined, size: 17),
                              label: Text('跟随系统'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined, size: 17),
                              label: Text('浅色'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined, size: 17),
                              label: Text('深色'),
                            ),
                          ],
                          selected: {repo.themeMode},
                          onSelectionChanged: (selection) =>
                              repo.setThemeMode(selection.first),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '界面主题随此选择全局即时生效。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (!_isWeb)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('显示“笔记”页签'),
                            subtitle: const Text(
                                '在底部/侧边导航中增加笔记页签，聚合查看收藏的题目与写过便签的题目（默认关闭）'),
                            value: repo.showNotesTab,
                            onChanged: (value) => repo.setShowNotesTab(value),
                          ),
                      ],
                    ),
                  ),
                  if (_isWindows || _isAndroid) ...[
                    const _SectionHeader('窗口与屏幕'),
                    _SettingsCard(
                      child: Column(
                        children: [
                          if (_isWindows)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('关闭窗口时最小化到托盘'),
                              subtitle: const Text('关闭主窗口后保留在系统托盘，可从托盘再次打开'),
                              value: repo.closeToTray,
                              onChanged: (value) {
                                repo.setCloseToTray(value);
                                WindowChannel.setCloseToTray(value);
                              },
                            ),
                          if (_isAndroid)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('跟随重力感应自动旋转'),
                              subtitle: const Text('关闭后锁定为竖屏显示'),
                              value: repo.followSensor,
                              onChanged: (value) {
                                repo.setFollowSensor(value);
                                OrientationService.apply(followSensor: value);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  const _SectionHeader('学习数据'),
                  _SettingsCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StatTile(
                                label: '已完成',
                                value: '${repo.completedIds.length} / $problemTotal',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatTile(
                                label: '收藏',
                                value: '${repo.bookmarkedIds.length}',
                              ),
                            ),
                            if (!_isWeb) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatTile(
                                  label: '便签',
                                  value: '${repo.noteCount}',
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => _clearWithConfirm(
                                title: '清空学习进度',
                                message: '将清除全部已完成标记与最近学习记录，且无法恢复。确定继续吗？',
                                action: repo.clearProgress,
                              ),
                              child: const Text('清空学习进度'),
                            ),
                            OutlinedButton(
                              onPressed: () => _clearWithConfirm(
                                title: '清空收藏',
                                message: '将取消全部题目收藏，且无法恢复。确定继续吗？',
                                action: repo.clearBookmarks,
                              ),
                              child: const Text('清空收藏'),
                            ),
                            if (!_isWeb)
                              OutlinedButton(
                                onPressed: () => _clearWithConfirm(
                                  title: '清空便签',
                                  message: '将删除全部题目的便签内容，且无法恢复。确定继续吗？',
                                  action: repo.clearNotes,
                                ),
                                child: const Text('清空便签'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const _SectionHeader('关于'),
                  _SettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.architecture_rounded,
                                size: 26,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '图学基础教程习题解答',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _appVersion.isEmpty
                                        ? '正在获取版本…'
                                        : '非官方重制 · 版本 v$_appVersion',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!_isIOS && !_isOhos)
                          FilledButton.tonalIcon(
                            onPressed: () => UpdateDialog.show(
                              context,
                              service: widget.updateService,
                            ),
                            icon: Icon(
                              _isWeb
                                  ? Icons.cloud_done_outlined
                                  : Icons.system_update_alt_rounded,
                              size: 18,
                            ),
                            label: Text(_isWeb ? '查看最新版本 / 客户端下载' : '检查更新'),
                          ),
                        if (!_isWeb && !_isIOS && !_isOhos) ...[
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('使用镜像加速下载'),
                            subtitle: const Text('国内直连 GitHub Releases 缓慢时开启'),
                            value: _mirrorUse,
                            onChanged: (value) {
                              setState(() => _mirrorUse = value);
                              _saveMirrorSettings();
                            },
                          ),
                          if (_mirrorUse)
                            RadioGroup<int>(
                              groupValue: _mirrorIndex,
                              onChanged: (value) {
                                setState(() => _mirrorIndex = value ?? 1);
                                _saveMirrorSettings();
                              },
                              child: Column(
                                children: [
                                  for (var i = 0;
                                      i <
                                          UpdateService
                                              .downloadMirrors.length;
                                      i++)
                                    RadioListTile<int>(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: i,
                                      title: Text(UpdateService
                                          .downloadMirrors[i].label),
                                      subtitle: UpdateService
                                              .downloadMirrors[i].prefix.isEmpty
                                          ? null
                                          : Text(
                                              UpdateService
                                                  .downloadMirrors[i].prefix,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          if (!_mirrorLoaded)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                          Text(
                            '镜像站由社区维护、时效不定；若下载仍失败可切换其它选项或关闭镜像直连。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.person_outline_rounded),
                          title: const Text('开发者'),
                          trailing: Text(
                            'Kepler16f',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.code_rounded),
                          title: const Text('GitHub 仓库'),
                          subtitle: const Text('github.com/Kepler16f/zju-TuXueJieDa-next'),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                          onTap: _openRepository,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '《图学基础教程》配套习题的跨平台数字化解答手册：'
                          '收录 177 道习题的原题、分步图解与动画演示，'
                          '支持搜索、收藏${_isWeb ? '' : '、便签'}、深浅色主题与多端使用。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '本项目为学生个人学习用途的非官方重制，'
                          '与教材编者及出版方无关联；'
                          '习题内容版权归原出版方所有。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 20),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
