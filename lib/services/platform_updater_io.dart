import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_updater_stub.dart' show PlatformTargetInfo;

export 'platform_updater_stub.dart' show PlatformTargetInfo;

const _updaterChannel = MethodChannel('com.kepler16f.tuxuejieda/updater');

String _normalizeArch(String raw) {
  final v = raw.toLowerCase().trim();
  if (v.contains('arm64') || v.contains('aarch64') || v.contains('arm64_v8a') || v.contains('arm64-v8a')) {
    return 'arm64';
  }
  if (v.contains('x86_64') || v.contains('amd64') || v.contains('x64') || v.contains('win64')) {
    return 'x64';
  }
  if (v.contains('armeabi') || (v.contains('arm') && !v.contains('64'))) {
    return Platform.isAndroid ? 'armeabi' : 'arm32';
  }
  if (v.contains('x86') || v.contains('i686') || v.contains('i386') || v.contains('ia32')) {
    return 'x86';
  }
  return v.isEmpty ? 'unknown' : v;
}

Future<PlatformTargetInfo> detectPlatformTarget() async {
  final os = Platform.operatingSystem.toLowerCase();
  String arch = _normalizeArch(Platform.version);

  if (Platform.isWindows) {
    final envArch = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
    if (envArch.isNotEmpty && arch == 'unknown') {
      arch = _normalizeArch(envArch);
    } else if (arch == 'unknown') {
      arch = _normalizeArch(Platform.version);
    }
    return PlatformTargetInfo(
      os: 'windows',
      arch: arch,
      supportsInAppDownload: true,
      supportsDirectInstall: true,
    );
  }

  if (Platform.isAndroid) {
    try {
      final abis = await _updaterChannel.invokeListMethod<String>('getSupportedAbis');
      if (abis != null && abis.isNotEmpty) {
        arch = _normalizeArch(abis.first);
      }
    } catch (_) {
      // Fall back to Dart runtime Platform.version ABI detection.
    }
    return PlatformTargetInfo(
      os: 'android',
      arch: arch,
      supportsInAppDownload: true,
      supportsDirectInstall: true,
    );
  }

  if (Platform.isLinux) {
    try {
      final res = await Process.run('uname', ['-m']);
      if (res.exitCode == 0) {
        arch = _normalizeArch(res.stdout.toString());
      }
    } catch (_) {}
    return PlatformTargetInfo(
      os: 'linux',
      arch: arch,
      supportsInAppDownload: true,
      supportsDirectInstall: true,
    );
  }

  if (os == 'ohos') {
    return PlatformTargetInfo(
      os: 'ohos',
      arch: arch,
      supportsInAppDownload: false,
      supportsDirectInstall: false,
    );
  }

  return PlatformTargetInfo(
    os: os,
    arch: arch,
    supportsInAppDownload: false,
    supportsDirectInstall: false,
  );
}

Future<String> resolveUpdateDownloadPath(String fileName) async {
  Directory baseDir;
  if (Platform.isAndroid) {
    baseDir = (await getExternalStorageDirectory()) ?? await getTemporaryDirectory();
  } else {
    baseDir = (await getDownloadsDirectory()) ?? await getTemporaryDirectory();
  }
  final updateDir = Directory(p.join(baseDir.path, 'tuxuejieda_updates'));
  if (!await updateDir.exists()) {
    await updateDir.create(recursive: true);
  }
  // Remove old installers of previous versions in the update cache folder.
  await for (final entity in updateDir.list()) {
    if (entity is File && p.basename(entity.path) != fileName) {
      try {
        await entity.delete();
      } catch (_) {}
    }
  }
  return p.join(updateDir.path, fileName);
}

/// Launches the downloaded update package or opens its directory if compressed.
/// Returns a status message describing what was triggered, or null if unsupported.
Future<String?> triggerDownloadedUpdateInstall(
  String filePath, {
  required String os,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return '安装包文件不存在：$filePath';
  }
  final ext = p.extension(filePath).toLowerCase();

  if (os == 'windows') {
    if (ext == '.exe' || ext == '.msi' || ext == '.msix') {
      await Process.start(filePath, const [], mode: ProcessStartMode.detached);
      return '已启动安装程序，请按向导完成更新并重启应用。';
    }
    if (ext == '.zip') {
      await Process.start('explorer.exe', ['/select,', filePath], mode: ProcessStartMode.detached);
      return '已下载便携压缩包并在资源管理器中选中，解压覆盖即可完成更新。';
    }
    await Process.start('explorer.exe', [filePath], mode: ProcessStartMode.detached);
    return '已打开下载文件。';
  }

  if (os == 'android') {
    final result = await _updaterChannel.invokeMethod<String>('installApk', {'path': filePath});
    return result ?? '已拉起系统安装器，请确认安装新版 APK。';
  }

  if (os == 'linux') {
    if (ext == '.appimage' || ext == '.sh' || ext.isEmpty) {
      await Process.run('chmod', ['+x', filePath]);
      await Process.start(filePath, const [], mode: ProcessStartMode.detached);
      return '已赋予执行权限并启动新版程序：$filePath';
    }
    await Process.start('xdg-open', [p.dirname(filePath)], mode: ProcessStartMode.detached);
    return '已打开下载目录，请安装新版软件包：${p.basename(filePath)}';
  }

  return null;
}

Future<bool> prepareTempDownloadFile(String filePath) async {
  final f = File(filePath);
  if (await f.exists()) {
    await f.delete();
    return true;
  }
  return false;
}
