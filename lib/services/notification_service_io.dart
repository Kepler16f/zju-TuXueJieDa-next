import 'dart:async';
import 'dart:io';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

/// 下载任务的系统通知封装。
///
/// - Android：awesome_notifications 常驻进度通知（进度条实时刷新），完成/失败转为普通通知。
/// - Windows / macOS：local_notifier 完成与失败 toast（下载中不弹通知，避免打扰）。
/// - Linux / 鸿蒙：暂不支持系统通知，静默降级。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _progressChannelKey = 'download_progress_channel';
  static const _progressNotificationId = 20260101;
  static const _resultNotificationId = 20260102;

  bool _initialized = false;
  Timer? _scheduleTimer;
  int _lastPercent = -1;

  bool get _isAndroid => Platform.isAndroid;
  bool get _usesLocalNotifier => Platform.isWindows || Platform.isMacOS;

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (_isAndroid) {
        await AwesomeNotifications().initialize(null, [
          NotificationChannel(
            channelKey: _progressChannelKey,
            channelName: '应用更新下载',
            channelDescription: '显示更新包下载进度与结果',
            importance: NotificationImportance.Low,
            channelShowBadge: false,
          ),
        ]);
      } else if (_usesLocalNotifier) {
        await LocalNotifier.instance.setup(appName: 'tuxuejieda_next');
      }
      _initialized = true;
    } catch (_) {
      // 通知初始化失败不阻塞应用（下载照常，仅无系统通知）。
    }
  }

  /// 下载进行中：Android 刷新常驻进度通知（调用方节流）。
  void showDownloadProgress({
    required String title,
    required int received,
    required int total,
  }) {
    if (!_isAndroid || !_initialized) return;
    final percent = total > 0 ? (received * 100 / total).floor() : 0;
    if (percent == _lastPercent) return;
    _lastPercent = percent;
    _schedule(() async {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: _progressNotificationId,
          channelKey: _progressChannelKey,
          title: title,
          body: '${_mb(received)} / ${_mb(total)} MB（$percent%）',
          category: NotificationCategory.Progress,
          notificationLayout: NotificationLayout.Default,
          locked: true,
        ),
      );
    });
  }

  /// 下载完成：转为完成通知并解锁。
  void showDownloadCompleted({required String name, required String path}) {
    if (!_initialized) return;
    _lastPercent = -1;
    if (_isAndroid) {
      _schedule(() async {
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: _resultNotificationId,
            channelKey: _progressChannelKey,
            title: '下载完成',
            body: '$name 已保存，可在应用内安装。',
            category: NotificationCategory.Status,
            notificationLayout: NotificationLayout.Default,
            locked: false,
          ),
        );
      });
    } else if (_usesLocalNotifier) {
      _schedule(() async {
        final n = LocalNotification(
          title: '下载完成',
          body: '$name 已保存，可在应用内安装。',
        );
        n.onClick = () async {
          try {
            await Process.start('explorer.exe', ['/select,', path]);
          } catch (_) {}
        };
        await n.show();
      });
    }
  }

  /// 下载失败通知。
  void showDownloadFailed({required String message}) {
    if (!_initialized) return;
    _lastPercent = -1;
    if (_isAndroid) {
      _schedule(() async {
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: _resultNotificationId,
            channelKey: _progressChannelKey,
            title: '下载失败',
            body: message,
            notificationLayout: NotificationLayout.Default,
            locked: false,
          ),
        );
      });
    } else if (_usesLocalNotifier) {
      _schedule(() async {
        final n = LocalNotification(title: '下载失败', body: message);
        await n.show();
      });
    }
  }

  /// Android 13+ 通知权限请求（后台下载启动前调用，失败不阻塞下载）。
  Future<void> ensurePermission() async {
    if (!_isAndroid || !_initialized) return;
    try {
      final allowed = await AwesomeNotifications().isNotificationAllowed();
      if (!allowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
    } catch (_) {}
  }

  /// 隐藏进行中的进度通知（下载取消时）。
  void dismissDownloadProgress() {
    _lastPercent = -1;
    if (_isAndroid && _initialized) {
      _schedule(() async {
        await AwesomeNotifications().dismiss(_progressNotificationId);
      });
    }
  }

  void _schedule(Future<void> Function() action) {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(action());
    });
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
