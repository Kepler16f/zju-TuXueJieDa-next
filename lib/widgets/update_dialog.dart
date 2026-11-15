import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_service.dart';
import '../services/update_service.dart';

/// 模态更新对话框：检查 GitHub Releases、后台下载安装包（可关闭对话框，
/// 系统通知显示进度），并在对话框内以 Markdown 展示 Release 说明。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.service});

  final UpdateService service;

  static Future<void> show(BuildContext context, {UpdateService? service}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(service: service ?? UpdateService()),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  UpdateCheckResult? _result;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.init();
    widget.service.backgroundDownload.addListener(_onBackgroundChanged);
    _runCheck();
  }

  @override
  void dispose() {
    widget.service.backgroundDownload.removeListener(_onBackgroundChanged);
    super.dispose();
  }

  void _onBackgroundChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final res = await widget.service.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _result = res;
      _checking = false;
    });
  }

  /// 判定当前检查结果对应的下载任务状态。
  BackgroundDownloadState? _stateFor(ReleaseAsset? asset) {
    final bg = widget.service.backgroundDownload.value;
    if (bg == null || asset == null || bg.asset.name != asset.name) return null;
    return bg;
  }

  Future<void> _startDownload(ReleaseAsset asset) async {
    await widget.service.startBackgroundDownload(asset);
    if (mounted) setState(() {});
  }

  Future<void> _installDownloaded(String path) async {
    final res = _result;
    if (res == null) return;
    final msg = await widget.service.launchDownloadedPackage(
      path,
      target: res.target,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? '下载已保存到：$path')),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '--';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = _result;
    final release = res?.release;
    final bg = _stateFor(res?.matchedAsset);
    final downloading = bg != null && !bg.done && !bg.failed && !bg.cancelled;
    final percent = (bg != null && bg.total > 0)
        ? (bg.received * 100 / bg.total).clamp(0.0, 100.0)
        : null;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.system_update_alt_rounded),
          SizedBox(width: 10),
          Text('应用更新检查'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _checking
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('正在连接 GitHub Releases 检查最新版本...'),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前版本：v${res?.currentVersion ?? '0.0.1'} · 平台：${res?.target.os ?? '-'}/${res?.target.arch ?? '-'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    res?.message ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (release != null && release.body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '更新内容',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 220),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: MarkdownBody(
                          data: release.body,
                          selectable: false,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme)
                              .copyWith(
                            h1: theme.textTheme.titleMedium,
                            h2: theme.textTheme.titleMedium,
                            h3: theme.textTheme.titleSmall,
                            p: theme.textTheme.bodySmall
                                ?.copyWith(height: 1.45),
                            listBullet: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (downloading || (bg?.done ?? false)) ...[
                    const SizedBox(height: 14),
                    if (downloading) ...[
                      LinearProgressIndicator(value: percent),
                      const SizedBox(height: 6),
                      Text(
                        '${_formatBytes(bg.received)} / ${_formatBytes(bg.total)}'
                        '（${percent?.toStringAsFixed(0)}%）· 可关闭此窗口，通知栏显示进度',
                        style: theme.textTheme.labelSmall,
                      ),
                    ] else if (bg?.done ?? false)
                      Text(
                        '下载完成：${_formatBytes(bg!.received)} · ${bg.path}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                  if (bg?.failed ?? false) ...[
                    const SizedBox(height: 10),
                    Text(
                      '下载失败：${bg!.error}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  if (bg?.cancelled ?? false) ...[
                    const SizedBox(height: 10),
                    Text(
                      '下载已取消，可重新下载。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(release?.htmlUrl ?? UpdateService.releasesPageUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('打开发布页'),
        ),
        if (downloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('后台下载'),
          ),
          TextButton(
            onPressed: widget.service.cancelBackgroundDownload,
            child: const Text('取消下载'),
          ),
        ] else ...[
          if (!_checking && res?.status == UpdateStatus.error)
            TextButton(
              onPressed: _runCheck,
              child: const Text('重试'),
            ),
          if (!_checking &&
              res?.status == UpdateStatus.updateAvailable &&
              res?.matchedAsset != null &&
              !(bg?.done ?? false))
            FilledButton.icon(
              onPressed: bg != null && bg.failed
                  ? () => _startDownload(res!.matchedAsset!)
                  : () => _startDownload(res!.matchedAsset!),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text((bg?.failed ?? false) ? '重试下载' : '立即下载更新'),
            ),
          if (bg?.done ?? false)
            FilledButton.icon(
              onPressed: () => _installDownloaded(bg!.path!),
              icon: const Icon(Icons.install_desktop_rounded, size: 16),
              label: const Text('立即安装 / 打开'),
            ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
