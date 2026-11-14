import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// Modal dialog checking GitHub Releases, streaming package downloads with
/// progress, and triggering native installation on Windows / Android / Linux.
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
  bool _downloading = false;
  double? _progress;
  int _received = 0;
  int _total = 0;
  String? _downloadedPath;
  String? _statusMessage;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
      _statusMessage = null;
    });
    final res = await widget.service.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _result = res;
      _checking = false;
    });
  }

  Future<void> _startDownload(ReleaseAsset asset) async {
    final token = CancelToken();
    setState(() {
      _cancelToken = token;
      _downloading = true;
      _progress = 0;
      _received = 0;
      _total = asset.size;
      _statusMessage = '正在从 GitHub 下载更新包：${asset.name}';
    });

    try {
      final path = await widget.service.downloadAsset(
        asset,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total > 0 ? total : asset.size;
            _progress = _total > 0 ? (received / _total).clamp(0.0, 1.0) : null;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedPath = path;
        _progress = 1.0;
        _statusMessage = '下载完成，正在准备安装...';
      });
      await _installDownloaded(path);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _statusMessage = CancelToken.isCancel(e)
            ? '已取消下载，可稍后重新下载。'
            : '下载失败：${e.message ?? e.type.name}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _statusMessage = '下载或安装出错：$e';
      });
    }
  }

  Future<void> _installDownloaded(String path) async {
    final res = _result;
    if (res == null) return;
    final msg = await widget.service.launchDownloadedPackage(
      path,
      target: res.target,
    );
    if (!mounted) return;
    setState(() {
      _statusMessage = msg ?? '下载已保存到：$path';
    });
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
                  if (res?.release != null && res!.release!.body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          res.release!.body,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  if (_downloading || _progress != null) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 6),
                    Text(
                      _progress != null
                          ? '${(_progress! * 100).toStringAsFixed(0)}% · '
                              '${_formatBytes(_received)} / ${_formatBytes(_total)}'
                          : '${_formatBytes(_received)} / ${_formatBytes(_total)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(res?.release?.htmlUrl ?? UpdateService.releasesPageUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('打开发布页'),
        ),
        if (_downloading)
          TextButton(
            onPressed: () => _cancelToken?.cancel(),
            child: const Text('取消下载'),
          )
        else ...[
          if (!_checking &&
              res?.status == UpdateStatus.error)
            TextButton(
              onPressed: _runCheck,
              child: const Text('重试'),
            ),
          if (!_checking &&
              res?.status == UpdateStatus.updateAvailable &&
              res?.matchedAsset != null &&
              _downloadedPath == null)
            FilledButton.icon(
              onPressed: () => _startDownload(res!.matchedAsset!),
              icon: const Icon(Icons.download_rounded),
              label: const Text('立即下载更新'),
            ),
          if (_downloadedPath != null)
            FilledButton.icon(
              onPressed: () => _installDownloaded(_downloadedPath!),
              icon: const Icon(Icons.install_desktop_rounded),
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
