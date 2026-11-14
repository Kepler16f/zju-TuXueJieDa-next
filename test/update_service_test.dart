import 'package:flutter_test/flutter_test.dart';
import 'package:tuxuejieda_next/services/platform_updater_stub.dart';
import 'package:tuxuejieda_next/services/update_service.dart';

/// 纯 Dart 静态方法测试：matchAssetForPlatform / compareVersions /
/// normalizeVersion。不依赖 widget binding，也不发起网络请求。
void main() {
  ReleaseAsset asset(String name) => ReleaseAsset(
        name: name,
        downloadUrl: 'https://example.com/$name',
        size: 12345678,
      );

  PlatformTargetInfo target(String os, String arch) => PlatformTargetInfo(
        os: os,
        arch: arch,
        supportsInAppDownload: true,
        supportsDirectInstall: true,
      );

  group('matchAssetForPlatform · Windows', () {
    test('arm64 目标命中 arm64 安装包（含中文文件名与版本号干扰词）', () {
      final assets = [
        asset('图学基础教程习题解答-Windows-x64-0.1.0-setup.exe'),
        asset('图学基础教程习题解答-Windows-arm64-0.1.0-setup.exe'),
      ];
      final matched = UpdateService.matchAssetForPlatform(
        assets,
        target('windows', 'arm64'),
      );
      expect(matched, isNotNull);
      expect(matched!.name, '图学基础教程习题解答-Windows-arm64-0.1.0-setup.exe');
    });

    test('arm64 目标拒绝 x64 安装包', () {
      final matched = UpdateService.matchAssetForPlatform(
        [asset('图学基础教程习题解答-Windows-x64-0.1.0-setup.exe')],
        target('windows', 'arm64'),
      );
      expect(matched, isNull);
    });

    test('arm64 目标拒绝 x86 与 x86_64 安装包', () {
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-Windows-x86-setup.exe')],
          target('windows', 'arm64'),
        ),
        isNull,
      );
      // x86_64 属 x64 家族，同样不能作为 arm64 包。
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-Windows-x86_64-setup.exe')],
          target('windows', 'arm64'),
        ),
        isNull,
      );
    });

    test('x64 目标拒绝纯 x86 安装包并命中 x64', () {
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-Windows-x86-setup.exe')],
          target('windows', 'x64'),
        ),
        isNull,
      );
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-Windows-x86-setup.exe'), asset('app-Windows-x64-setup.exe')],
        target('windows', 'x64'),
      );
      expect(matched!.name, 'app-Windows-x64-setup.exe');
    });

    test('x64 目标命中 x86_64 命名的安装包（x86_64 属 x64 家族）', () {
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-Windows-x86_64-setup.exe')],
        target('windows', 'x64'),
      );
      expect(matched, isNotNull);
    });

    test('x86 目标命中 x86 并拒绝 x64 / x86_64 / arm64', () {
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-Windows-x86-setup.exe')],
        target('windows', 'x86'),
      );
      expect(matched, isNotNull);
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-Windows-x64-setup.exe')],
          target('windows', 'x86'),
        ),
        isNull,
      );
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-Windows-x86_64-setup.exe')],
          target('windows', 'x86'),
        ),
        isNull,
      );
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-Windows-arm64-setup.exe')],
          target('windows', 'x86'),
        ),
        isNull,
      );
    });

    test('扩展名不符的资产直接忽略', () {
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-windows-arm64.apk')],
          target('windows', 'arm64'),
        ),
        isNull,
      );
    });

    test('空资产列表返回 null', () {
      expect(
        UpdateService.matchAssetForPlatform(const [], target('windows', 'arm64')),
        isNull,
      );
    });
  });

  group('matchAssetForPlatform · Android', () {
    test('arm64 目标命中 arm64-v8a 并拒绝其他 ABI', () {
      final matched = UpdateService.matchAssetForPlatform(
        [
          asset('app-armeabi-v7a.apk'),
          asset('app-x86_64.apk'),
          asset('app-x86.apk'),
          asset('app-arm64-v8a.apk'),
        ],
        target('android', 'arm64'),
      );
      expect(matched!.name, 'app-arm64-v8a.apk');

      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-armeabi-v7a.apk')],
          target('android', 'arm64'),
        ),
        isNull,
      );
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-x86_64.apk')],
          target('android', 'arm64'),
        ),
        isNull,
      );
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-x86.apk')],
          target('android', 'arm64'),
        ),
        isNull,
      );
    });

    test('armeabi 目标命中 armeabi-v7a 并拒绝 arm64-v8a', () {
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-arm64-v8a.apk'), asset('app-armeabi-v7a.apk')],
        target('android', 'armeabi'),
      );
      expect(matched!.name, 'app-armeabi-v7a.apk');
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-arm64-v8a.apk')],
          target('android', 'armeabi'),
        ),
        isNull,
      );
    });

    test('x64 目标命中 x86_64 APK（并拒绝 arm64-v8a）', () {
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-arm64-v8a.apk'), asset('app-x86_64.apk')],
        target('android', 'x64'),
      );
      expect(matched!.name, 'app-x86_64.apk');
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-arm64-v8a.apk')],
          target('android', 'x64'),
        ),
        isNull,
      );
    });

    test('universal APK 任意 ABI 均可命中，但分数低于精确 ABI', () {
      for (final arch in const ['arm64', 'armeabi', 'x64', 'x86']) {
        final matched = UpdateService.matchAssetForPlatform(
          [asset('app-universal.apk')],
          target('android', arch),
        );
        expect(matched, isNotNull, reason: 'universal 应命中 android/$arch');
        expect(matched!.name, 'app-universal.apk');
      }

      // 同时存在 universal 与精确 ABI 时，精确 ABI 必须胜出（分数更高）。
      final best = UpdateService.matchAssetForPlatform(
        [asset('app-universal.apk'), asset('app-arm64-v8a.apk')],
        target('android', 'arm64'),
      );
      expect(best!.name, 'app-arm64-v8a.apk');
    });

    test('非 APK 资产直接忽略', () {
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-windows-arm64-setup.exe')],
          target('android', 'arm64'),
        ),
        isNull,
      );
    });
  });

  group('matchAssetForPlatform · Linux', () {
    test('arm64 目标命中 aarch64 AppImage（aarch64 与 arm64 等价）', () {
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-linux-x86_64.AppImage'), asset('app-linux-aarch64.AppImage')],
        target('linux', 'arm64'),
      );
      expect(matched!.name, 'app-linux-aarch64.AppImage');
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-linux-x86_64.AppImage')],
          target('linux', 'arm64'),
        ),
        isNull,
      );
    });

    test('linux x64 与 arm64 互斥', () {
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-linux-aarch64.AppImage')],
          target('linux', 'x64'),
        ),
        isNull,
      );
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-linux-arm64.AppImage')],
          target('linux', 'x64'),
        ),
        isNull,
      );
      final matched = UpdateService.matchAssetForPlatform(
        [asset('app-linux-aarch64.AppImage'), asset('app-linux-x86_64.AppImage')],
        target('linux', 'x64'),
      );
      expect(matched!.name, 'app-linux-x86_64.AppImage');
    });

    test('扩展名不符的资产直接忽略', () {
      expect(
        UpdateService.matchAssetForPlatform(
          [asset('app-linux-aarch64.apk')],
          target('linux', 'arm64'),
        ),
        isNull,
      );
    });
  });

  group('compareVersions', () {
    test('数值逐段比较', () {
      expect(UpdateService.compareVersions('0.1.0', '0.0.1'), greaterThan(0));
      expect(UpdateService.compareVersions('0.0.1', '0.1.0'), lessThan(0));
      expect(UpdateService.compareVersions('0.2.0', '0.1.9'), greaterThan(0));
      expect(UpdateService.compareVersions('1.2.3', '1.2.3'), 0);
      // 数值比较而非字典序：1.2.4 < 1.10.0。
      expect(UpdateService.compareVersions('1.2.4', '1.10.0'), lessThan(0));
    });

    test('段数不一致按 0 补齐（1.0 与 1.0.0 等价）', () {
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.0', '1.0'), 0);
      expect(UpdateService.compareVersions('1.0', '1.0.1'), lessThan(0));
      expect(UpdateService.compareVersions('2', '1.9.9'), greaterThan(0));
    });

    test('v 前缀与 build 号不影响比较', () {
      expect(UpdateService.compareVersions('v0.1.0', '0.1.0'), 0);
      expect(UpdateService.compareVersions('0.1.0+2', '0.1.0'), 0);
      expect(UpdateService.compareVersions('v1.2.0', '1.1.9'), greaterThan(0));
    });
  });

  group('normalizeVersion', () {
    test('提取 v 前缀、tag 前缀与 build 号中的三段版本', () {
      expect(UpdateService.normalizeVersion('v0.1.0'), '0.1.0');
      expect(UpdateService.normalizeVersion('V0.1.0'), '0.1.0');
      expect(UpdateService.normalizeVersion('0.1.0+2'), '0.1.0');
      expect(UpdateService.normalizeVersion('refs/tags/v0.1.0'), '0.1.0');
      expect(UpdateService.normalizeVersion('图学基础教程习题解答 v0.2.0'), '0.2.0');
    });

    test('两段版本与边例保持原样返回', () {
      expect(UpdateService.normalizeVersion('v0.1'), '0.1');
      expect(UpdateService.normalizeVersion('1.0'), '1.0');
      expect(UpdateService.normalizeVersion(''), '');
      expect(UpdateService.normalizeVersion('unknown'), 'unknown');
    });
  });
}
