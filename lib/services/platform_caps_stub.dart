/// Web / fallback runtime platform flags without `dart:io`.
class PlatformCaps {
  PlatformCaps._();

  static const bool isWeb = true;
  static const bool isWindows = false;
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isMacOS = false;
  static const bool isLinux = false;
  static const bool isOhos = false;
  static const bool supportsInAppUpdate = false;
}
