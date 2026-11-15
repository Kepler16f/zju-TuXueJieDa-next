import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
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

/// GitHub 产物下载镜像（前缀 + 完整原始 URL 的拼接方式）。
/// 镜像站时效性强，列表允许后续在代码里增删。
class DownloadMirror {
  const DownloadMirror(this.label, this.prefix);

  final String label;
  final String prefix;
}

/// 一次后台下载任务的实时状态（进度/完成/失败）。
class BackgroundDownloadState {
  const BackgroundDownloadState({
    required this.asset,
    this.received = 0,
    this.total = 0,
    this.done = false,
    this.failed = false,
    this.cancelled = false,
    this.path,
    this.error,
  });

  final ReleaseAsset asset;
  final int received;
  final int total;
  final bool done;
  final bool failed;
  final bool cancelled;
  final String? path;
  final String? error;
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

  /// 下载镜像（国内直连 GitHub 产物缓慢）。默认启用镜像加速。
  static const List<DownloadMirror> downloadMirrors = [
    DownloadMirror('官方 GitHub（直连）', ''),
    DownloadMirror('GHProxy 镜像', 'https://mirror.ghproxy.com/'),
    DownloadMirror('GH-Proxy 镜像', 'https://gh-proxy.com/'),
    DownloadMirror('GHFast 镜像', 'https://ghfast.top/'),
  ];
  static const _prefUseMirror = 'update_use_mirror';
  static const _prefMirrorIndex = 'update_mirror_index';

  final Dio _dio;

  /// 后台下载任务的实时状态；null = 没有进行中/刚完成的任务。
  final ValueNotifier<BackgroundDownloadState?> backgroundDownload =
      ValueNotifier(null);

  CancelToken? _backgroundToken;

  /// 当前生效的镜像（读取持久化设置；默认启用第一个镜像加速）。
  Future<DownloadMirror> resolveMirror() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final use = prefs.getBool(_prefUseMirror) ?? true;
      final index = prefs.getInt(_prefMirrorIndex) ?? 1;
      if (!use) return downloadMirrors.first;
      if (index < 0 || index >= downloadMirrors.length) {
        return downloadMirrors.first;
      }
      return downloadMirrors[index];
    } catch (_) {
      return downloadMirrors.first;
    }
  }

  /// 读取镜像设置的原始值（设置页 UI 用；resolveMirror 返回的是生效镜像）。
  Future<({bool useMirror, int mirrorIndex})> loadMirrorSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final use = prefs.getBool(_prefUseMirror) ?? true;
      var index = prefs.getInt(_prefMirrorIndex) ?? 1;
      if (index < 0 || index >= downloadMirrors.length) index = 1;
      return (useMirror: use, mirrorIndex: index);
    } catch (_) {
      return (useMirror: true, mirrorIndex: 1);
    }
  }

  /// 持久化镜像设置（设置页调用）。
  Future<void> setMirrorSettings({required bool useMirror, required int index}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUseMirror, useMirror);
    await prefs.setInt(_prefMirrorIndex, index);
  }

  /// 给 GitHub 产物 URL 套上当前镜像前缀。
  Future<String> applyMirror(String url) async {
    final mirror = await resolveMirror();
    if (mirror.prefix.isEmpty || url.startsWith(mirror.prefix)) return url;
    return mirror.prefix + url;
  }

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

    if (kIsWeb) {
      return UpdateCheckResult(
        status: UpdateStatus.unsupportedPlatform,
        currentVersion: currentVersion,
        target: target,
        message: '当前运行于 Web 端，网页部署后即自动加载最新版；如需下载桌面或移动端安装包，可点击下方“打开发布页”。',
      );
    }

    if (target.os != 'windows' &&
        target.os != 'android' &&
        target.os != 'linux') {
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
    bool reportBackground = false,
  }) async {
    final savePath = await resolveUpdateDownloadPath(asset.name);
    await prepareTempDownloadFile(savePath);
    final url = await applyMirror(asset.downloadUrl);
    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        onProgress(received, total);
        if (reportBackground) {
          backgroundDownload.value = BackgroundDownloadState(
            asset: asset,
            received: received,
            total: total > 0 ? total : asset.size,
          );
        }
      },
    );
    if (reportBackground) {
      backgroundDownload.value = BackgroundDownloadState(
        asset: asset,
        received: asset.size,
        total: asset.size,
        done: true,
        path: savePath,
      );
    }
    return savePath;
  }

  /// 后台下载：对话框关闭后任务继续；进度通过 [backgroundDownload] 广播，
  /// 并刷新系统通知（Android 进度条 / Windows、macOS 完成通知）。
  Future<void> startBackgroundDownload(ReleaseAsset asset) async {
    await NotificationService.instance.ensurePermission();
    backgroundDownload.value = BackgroundDownloadState(
      asset: asset,
      received: 0,
      total: asset.size,
    );
    _backgroundToken = CancelToken();
    final token = _backgroundToken!;
    try {
      final path = await downloadAsset(
        asset,
        onProgress: (_, _) {},
        cancelToken: token,
        reportBackground: true,
      );
      backgroundDownload.value = BackgroundDownloadState(
        asset: asset,
        received: asset.size,
        total: asset.size,
        done: true,
        path: path,
      );
      NotificationService.instance.showDownloadCompleted(
        name: asset.name,
        path: path,
      );
    } catch (e) {
      final prev = backgroundDownload.value;
      final dioError = e is DioException ? e : null;
      final cancelled = dioError != null && CancelToken.isCancel(dioError);
      backgroundDownload.value = BackgroundDownloadState(
        asset: asset,
        received: prev?.received ?? 0,
        total: prev?.total ?? asset.size,
        cancelled: cancelled,
        failed: !cancelled,
        error: '$e',
      );
      if (cancelled) {
        NotificationService.instance.dismissDownloadProgress();
      } else {
        NotificationService.instance.showDownloadFailed(message: '$e');
      }
    } finally {
      _backgroundToken = null;
    }
  }

  /// 取消后台下载。
  void cancelBackgroundDownload() {
    _backgroundToken?.cancel();
    NotificationService.instance.dismissDownloadProgress();
  }

  Future<String?> launchDownloadedPackage(
    String filePath, {
    required PlatformTargetInfo target,
  }) {
    return triggerDownloadedUpdateInstall(filePath, os: target.os);
  }

  /// Releases the underlying Dio client and its socket resources.
  ///
  /// Call this when the widget that owns the service instance is disposed;
  /// the service must not be used for further network requests afterwards.
  void close() => _dio.close(force: true);

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

  /// Word-boundary token matcher for lower-cased asset names: any character
  /// outside `[a-z0-9]` (hyphen, underscore, dot, CJK, whitespace, ...) acts
  /// as a separator, so `-x64-` matches while `max64` / `x64bit` never do.
  /// Compound tokens such as `x86_64`, `arm64-v8a` and `armeabi-v7a` must be
  /// checked before their shorter prefixes (`x86`, `arm64`, `armeabi`) so a
  /// x86_64 package is never misread as a pure x86 build.
  static final Map<String, RegExp> _wordTokenPatterns = {};

  static bool _hasWordToken(String lowerName, String token) {
    final pattern = _wordTokenPatterns.putIfAbsent(
      token,
      () => RegExp('(?<![a-z0-9])${RegExp.escape(token)}(?![a-z0-9])'),
    );
    return pattern.hasMatch(lowerName);
  }

  /// arm64 family; `aarch64` is an alias (mostly seen on Linux).
  static bool _hasArm64Token(String lowerName) =>
      _hasWordToken(lowerName, 'arm64') || _hasWordToken(lowerName, 'aarch64');

  static bool _hasArm32Token(String lowerName) =>
      _hasWordToken(lowerName, 'arm32');

  /// x64 family; `x86_64` / `amd64` / `win64` are aliases.
  static bool _hasX64Token(String lowerName) =>
      _hasWordToken(lowerName, 'x64') ||
      _hasWordToken(lowerName, 'x86_64') ||
      _hasWordToken(lowerName, 'amd64') ||
      _hasWordToken(lowerName, 'win64');

  /// Pure 32-bit x86 family. Only meaningful when [_hasX64Token] is false,
  /// because `x86_64` also contains the `x86` letters.
  static bool _hasX86Token(String lowerName) =>
      _hasWordToken(lowerName, 'x86') ||
      _hasWordToken(lowerName, 'win32') ||
      _hasWordToken(lowerName, 'i386') ||
      _hasWordToken(lowerName, 'i686') ||
      _hasWordToken(lowerName, 'ia32');

  @visibleForTesting
  static ReleaseAsset? matchAssetForPlatform(
    List<ReleaseAsset> assets,
    PlatformTargetInfo target,
  ) {
    if (assets.isEmpty) return null;
    final os = target.os.toLowerCase();
    final arch = target.arch.toLowerCase();

    ReleaseAsset? best;
    var bestScore = -1;
    for (final a in assets) {
      final sc = _scoreAsset(a.name.toLowerCase(), os, arch);
      if (sc > bestScore) {
        bestScore = sc;
        best = a;
      }
    }
    return best;
  }

  /// Scoring rules (shared shape across platforms):
  /// - wrong extension: -1;
  /// - OS keyword (Windows/Linux) or APK base (Android): +20;
  /// - architecture token matching the target family: +30;
  /// - conflicting architecture token (mutually exclusive family): -1;
  /// - no architecture token at all: 0 (neutral fallback);
  /// - Android `universal`: +15 (below the exact-ABI +30);
  /// - installer format bonus on Windows / Linux.
  static int _scoreAsset(String name, String os, String arch) {
    if (os == 'windows') {
      if (!(name.endsWith('.exe') ||
          name.endsWith('.msix') ||
          name.endsWith('.msi') ||
          name.endsWith('.zip'))) {
        return -1;
      }
      var s = 0;
      // x64 family must be tested before x86: `x86_64` also contains `x86`.
      final x64 = _hasX64Token(name);
      final x86 = !x64 && _hasX86Token(name);
      final arm64 = _hasArm64Token(name);
      final arm32 = _hasArm32Token(name);
      if (_hasWordToken(name, 'windows') ||
          _hasWordToken(name, 'win') ||
          _hasWordToken(name, 'win64') ||
          _hasWordToken(name, 'win32')) {
        s += 20;
      }
      if (arch == 'arm64') {
        if (arm64) {
          s += 30;
        } else if (x64 || x86) {
          // Contains an x64/x86 token and no arm64 token: not an arm64 build.
          return -1;
        }
      } else if (arch == 'x64') {
        if (x64) {
          s += 30;
        } else if (arm64 || arm32 || x86) {
          // ARM builds and pure x86 builds cannot serve an x64 target.
          return -1;
        }
      } else if (arch == 'x86') {
        if (x86) {
          s += 30;
        } else if (x64 || arm64) {
          return -1;
        }
      } else if (_hasWordToken(name, arch)) {
        s += 30;
      }
      if (name.endsWith('.exe') ||
          name.endsWith('.msi') ||
          name.endsWith('.msix')) {
        s += 10;
      }
      if (name.endsWith('.zip')) {
        s += 5;
      }
      return s;
    }

    if (os == 'android') {
      if (!name.endsWith('.apk')) return -1;
      var s = 20;
      final abiArm64 =
          _hasWordToken(name, 'arm64-v8a') || _hasWordToken(name, 'arm64');
      final abiArmeabi =
          _hasWordToken(name, 'armeabi-v7a') || _hasWordToken(name, 'armeabi');
      final abiX64 = _hasWordToken(name, 'x86_64') || _hasWordToken(name, 'x64');
      final abiX86 = !abiX64 && _hasWordToken(name, 'x86');
      final abiUniversal = _hasWordToken(name, 'universal');
      final isTargetAbi = switch (arch) {
        'arm64' => abiArm64,
        'armeabi' => abiArmeabi,
        'x64' => abiX64,
        'x86' => abiX86,
        _ => false,
      };
      if (isTargetAbi) {
        s += 30;
      } else if (abiUniversal) {
        // Universal APKs install on every ABI but rank below exact ABI builds.
        s += 15;
      } else if (abiArm64 || abiArmeabi || abiX64 || abiX86) {
        // APK built for a different ABI.
        return -1;
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
      var s = 0;
      if (_hasWordToken(name, 'linux')) s += 20;
      final x64 = _hasX64Token(name);
      final x86 = !x64 && _hasX86Token(name);
      final arm64 = _hasArm64Token(name);
      if (arch == 'arm64') {
        // aarch64 is equivalent to arm64.
        if (arm64) {
          s += 30;
        } else if (x64 || x86) {
          return -1;
        }
      } else if (arch == 'x64') {
        if (x64) {
          s += 30;
        } else if (arm64 || x86) {
          // x64 and arm64 are mutually exclusive.
          return -1;
        }
      } else if (arch == 'x86') {
        if (x86) {
          s += 30;
        } else if (x64 || arm64) {
          return -1;
        }
      } else if (_hasWordToken(name, arch)) {
        s += 30;
      }
      if (name.endsWith('.appimage')) s += 10;
      if (name.endsWith('.deb')) s += 8;
      if (name.endsWith('.tar.gz')) s += 5;
      return s;
    }

    return -1;
  }
}
