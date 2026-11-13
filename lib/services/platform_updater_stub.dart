import 'package:flutter/foundation.dart';

/// Platform capabilities for checking/downloading/installing app updates.
class PlatformTargetInfo {
  const PlatformTargetInfo({
    required this.os,
    required this.arch,
    required this.supportsInAppDownload,
    required this.supportsDirectInstall,
  });

  final String os;
  final String arch;
  final bool supportsInAppDownload;
  final bool supportsDirectInstall;
}

Future<PlatformTargetInfo> detectPlatformTarget() async {
  if (kIsWeb) {
    return const PlatformTargetInfo(
      os: 'web',
      arch: 'wasm',
      supportsInAppDownload: false,
      supportsDirectInstall: false,
    );
  }
  return const PlatformTargetInfo(
    os: 'unknown',
    arch: 'unknown',
    supportsInAppDownload: false,
    supportsDirectInstall: false,
  );
}

Future<String> resolveUpdateDownloadPath(String fileName) {
  throw UnsupportedError('Direct file download is not supported on Web.');
}

Future<String?> triggerDownloadedUpdateInstall(
  String filePath, {
  required String os,
}) async {
  return null;
}

Future<bool> prepareTempDownloadFile(String filePath) async => false;
