/// Web / non-IO no-op stub for [NotificationService] so Web builds stay clean
/// without pulling `dart:io`, `awesome_notifications`, or `local_notifier`.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  Future<void> init() async {}

  void showDownloadProgress({
    required String title,
    required int received,
    required int total,
  }) {}

  void showDownloadCompleted({required String name, required String path}) {}

  void showDownloadFailed({required String message}) {}

  Future<void> ensurePermission() async {}

  void dismissDownloadProgress() {}
}
