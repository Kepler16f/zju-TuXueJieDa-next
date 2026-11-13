import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'platform_updater_stub.dart'
    if (dart.library.io) 'platform_updater_io.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  final String tagName;
  final String version;
  final String title;
  final String body;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
}

enum UpdateStatus {
  upToDate,
  updateAvailable,
  noReleaseYet,
  unsupportedPlatform,
  error,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    required this.target,
    this.release,
    this.matchedAsset,
    this.message,
  });

  final UpdateStatus status;
  final String currentVersion;
  final PlatformTargetInfo target;
  final ReleaseInfo? release;
  final ReleaseAsset? matchedAsset;
  final String? message;
}

/// Checks GitHub Releases for `Kepler16f/zju-TuXueJieDa-next` and downloads
/// matching platform installers on Windows, Android, and Linux.
class UpdateService {
  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 60),
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'zju-TuXueJieDa-next-updater',
                },
              ),
            );

  static const String repoOwner = 'Kepler16f';
  static const String repoName = 'zju-TuXueJieDa-next';
  static const String releasesPageUrl =
      'https://github.com/$repoOwner/$repoName/releases';

  final Dio _dio;

  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.1';
    }
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    final target = await detectPlatformTarget();
    final currentVersion = await getCurrentVersion();

    if (kIsWeb ||
        (target.os != 'windows' &&
            target.os != 'android' &&
            target.os != 'linux')) {
      return UpdateCheckResult(
        status: UpdateStatus.unsupportedPlatform,
        currentVersion: currentVersion,
        target: target,
        message: '当前平台 (${target.os}/${target.arch}) 暂不启用应用内直装更新，可前往 GitHub Releases 查看版本。',
      );
    }

    try {
      Map<String, dynamic>? releaseJson;
      try {
        final resp = await _dio.get<Map<String, dynamic>>(
          'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
        );
        releaseJson = resp.data;
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // Fallback to listing releases (handles pre-release tags cleanly).
          final listResp = await _dio.get<List<dynamic>>(
            'https://api.github.com/repos/$repoOwner/$repoName/releases',
            queryParameters: const {'per_page': 1},
          );
          final items = listResp.data;
          if (items == null || items.isEmpty) {
            return UpdateCheckResult(
              status: UpdateStatus.noReleaseYet,
              currentVersion: currentVersion,
              target: target,
              message: 'GitHub 仓库尚未发布正式 Release（当前版本 v$currentVersion）。',
            );
          }
          releaseJson = items.first as Map<String, dynamic>;
        } else {
          rethrow;
        }
      }

      if (releaseJson == null) {
        return UpdateCheckResult(
          status: UpdateStatus.noReleaseYet,
          currentVersion: currentVersion,
          target: target,
          message: '暂未检测到远端 Release 信息。',
        );
      }

      final release = _parseRelease(releaseJson);
      final hasNewer = compareVersions(release.version, currentVersion) > 0;
      if (!hasNewer) {
        return UpdateCheckResult(
          status: UpdateStatus.upToDate,
          currentVersion: currentVersion,
          target: target,
          release: release,
          message: '当前 v$currentVersion 已是最新版本（远端最新 ${release.tagName}）。',
        );
      }

      final matched = matchAssetForPlatform(release.assets, target);
      return UpdateCheckResult(
        status: UpdateStatus.updateAvailable,
        currentVersion: currentVersion,
        target: target,
        release: release,
        matchedAsset: matched,
        message: matched != null
            ? '发现新版本 v${release.version}（适配 ${target.os}/${target.arch}）'
            : '发现新版本 v${release.version}，但未找到直接匹配 ${target.os}/${target.arch} 的安装包，可前往发布页下载。',
      );
    } on DioException catch (e) {
      return UpdateCheckResult(
        status: UpdateStatus.error,
        currentVersion: currentVersion,
        target: target,
        message: '检查更新失败：${e.message ?? e.type.name}',
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateStatus.error,
        currentVersion: currentVersion,
        target: target,
        message: '检查更新异常：$e',
      );
    }
  }

  Future<String> downloadAsset(
    ReleaseAsset asset, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final savePath = await resolveUpdateDownloadPath(asset.name);
    await prepareTempDownloadFile(savePath);
    await _dio.download(
      asset.downloadUrl,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
    return savePath;
  }

  Future<String?> launchDownloadedPackage(
    String filePath, {
    required PlatformTargetInfo target,
  }) {
    return triggerDownloadedUpdateInstall(filePath, os: target.os);
  }

  static ReleaseInfo _parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final version = normalizeVersion(tag.isNotEmpty ? tag : (json['name'] as String? ?? '0.0.0'));
    final rawAssets = (json['assets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final assets = rawAssets
        .map(
          (a) => ReleaseAsset(
            name: a['name'] as String? ?? '',
            downloadUrl: a['browser_download_url'] as String? ?? '',
            size: (a['size'] as num? ?? 0).toInt(),
          ),
        )
        .toList(growable: false);

    return ReleaseInfo(
      tagName: tag.isEmpty ? 'v$version' : tag,
      version: version,
      title: (json['name'] as String? ?? tag).trim(),
      body: (json['body'] as String? ?? '').trim(),
      htmlUrl: json['html_url'] as String? ?? releasesPageUrl,
      assets: assets,
    );
  }

  static String normalizeVersion(String raw) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(raw);
    if (m != null) {
      return '${m.group(1)}.${m.group(2)}.${m.group(3)}';
    }
    return raw.replaceFirst(RegExp(r'^v'), '').split('+').first.trim();
  }

  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      final norm = normalizeVersion(v);
      return norm.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  @visibleForTesting
  static ReleaseAsset? matchAssetForPlatform(
    List<ReleaseAsset> assets,
    PlatformTargetInfo target,
  ) {
    if (assets.isEmpty) return null;
    final os = target.os.toLowerCase();
    final arch = target.arch.toLowerCase();

    int score(ReleaseAsset asset) {
      final name = asset.name.toLowerCase();
      var s = 0;

      if (os == 'windows') {
        if (!(name.endsWith('.exe') ||
            name.endsWith('.msix') ||
            name.endsWith('.msi') ||
            name.endsWith('.zip'))) {
          return -1;
        }
        if (name.contains('windows') || name.contains('win')) s += 20;
        if (name.contains(arch)) s += 30;
        if (arch == 'arm64' && (name.contains('x64') || name.contains('x86'))) return -1;
        if (arch == 'x64' && (name.contains('arm64') || name.contains('arm32'))) return -1;
        if (name.endsWith('.exe') || name.endsWith('.msi') || name.endsWith('.msix')) s += 10;
        if (name.endsWith('.zip')) s += 5;
        return s;
      }

      if (os == 'android') {
        if (!name.endsWith('.apk')) return -1;
        s += 20;
        if (name.contains(arch)) {
          s += 30;
        } else if (arch == 'arm64' && name.contains('arm64-v8a')) {
          s += 30;
        } else if (arch == 'armeabi' && name.contains('armeabi-v7a')) {
          s += 30;
        } else if (name.contains('universal')) {
          s += 15;
        } else if (name.contains('arm64') ||
            name.contains('armeabi') ||
            name.contains('x86_64') ||
            name.contains('x86')) {
          // Different ABI apk.
          if (!name.contains(arch)) return -1;
        }
        return s;
      }

      if (os == 'linux') {
        if (!(name.endsWith('.appimage') ||
            name.endsWith('.deb') ||
            name.endsWith('.tar.gz') ||
            name.endsWith('.zip'))) {
          return -1;
        }
        if (name.contains('linux')) s += 20;
        if (name.contains(arch) || (arch == 'arm64' && name.contains('aarch64'))) {
          s += 30;
        } else if (name.contains('x64') || name.contains('arm64') || name.contains('aarch64')) {
          return -1;
        }
        if (name.endsWith('.appimage')) s += 10;
        if (name.endsWith('.deb')) s += 8;
        if (name.endsWith('.tar.gz')) s += 5;
        return s;
      }

      return -1;
    }

    ReleaseAsset? best;
    var bestScore = -1;
    for (final a in assets) {
      final sc = score(a);
      if (sc > bestScore) {
        bestScore = sc;
        best = a;
      }
    }
    return best;
  }
}
