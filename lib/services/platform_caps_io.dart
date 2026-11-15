import 'dart:io';

/// Native runtime platform flags isolated cleanly away from Web builds.
class PlatformCaps {
  PlatformCaps._();

  static const bool isWeb = false;
  static bool get isWindows => Platform.isWindows;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;

  static bool get isOhos {
    try {
      if (Platform.operatingSystem.toLowerCase() == 'ohos') return true;
      return Platform.operatingSystemVersion.toLowerCase().contains('openharmony');
    } catch (_) {
      return false;
    }
  }

  static bool get supportsInAppUpdate => isWindows || isAndroid || isLinux;
}
