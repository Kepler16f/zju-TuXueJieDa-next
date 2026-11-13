import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuxuejieda_next/data/curriculum_repository.dart';
import 'package:tuxuejieda_next/models/curriculum.dart';
import 'package:tuxuejieda_next/pages/home_page.dart';
import 'package:tuxuejieda_next/services/platform_updater_stub.dart';
import 'package:tuxuejieda_next/services/update_service.dart';

void main() {
  group('Curriculum integrity', () {
    test('curriculum.json has exact 177 wired problems, 67 videos, and valid assets', () {
      final raw = File('assets/data/curriculum.json').readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final curriculum = Curriculum.fromJson(decoded);

      expect(curriculum.chapters.length, 4);
      expect(curriculum.problems.length, 177);
      expect(curriculum.problemsInChapter('jcty').length, 64);
      expect(curriculum.problemsInChapter('zht').length, 78);
      expect(curriculum.problemsInChapter('gct').length, 32);
      expect(curriculum.problemsInChapter('other').length, 3);
      expect(curriculum.problems.where((p) => p.hasVideo).length, 67);

      // Verify verified button page/no overrides vs naive filename IDs
      final p13 = curriculum.findById('13_1')!;
      expect(p13.page, 11);
      expect(p13.no, '1');

      final p36 = curriculum.findById('36_7_n')!;
      expect(p36.page, 36);
      expect(p36.no, '7');

      final p125 = curriculum.findById('125_5')!;
      expect(p125.page, 71);
      expect(p125.no, '1');

      final p127 = curriculum.findById('127_8')!;
      expect(p127.page, 124);
      expect(p127.no, '1');

      // Every referenced file must exist on disk
      for (final p in curriculum.problems) {
        expect(File(p.subjectImage).existsSync(), isTrue, reason: p.subjectImage);
        expect(File(p.answerImage).existsSync(), isTrue, reason: p.answerImage);
        expect(p.steps, isNotEmpty, reason: p.id);
        for (final s in p.steps) {
          expect(File(s.image).existsSync(), isTrue, reason: s.image);
        }
        if (p.video != null) {
          expect(File(p.video!.asset).existsSync(), isTrue, reason: p.video!.asset);
        }
      }
    });
  });

  group('UpdateService', () {
    test('compares semantic versions correctly', () {
      expect(UpdateService.compareVersions('0.0.2', '0.0.1'), greaterThan(0));
      expect(UpdateService.compareVersions('0.1.0', '0.0.9'), greaterThan(0));
      expect(UpdateService.compareVersions('v0.0.1', '0.0.1+1'), 0);
      expect(UpdateService.compareVersions('0.0.1', '0.0.2'), lessThan(0));
    });

    test('matches exact platform and ABI release assets', () {
      const assets = [
        ReleaseAsset(
          name: '图学基础教程习题解答-Windows-arm64-0.0.2-setup.exe',
          downloadUrl: 'https://example.com/win-arm64-setup.exe',
          size: 100,
        ),
        ReleaseAsset(
          name: '图学基础教程习题解答-Windows-x64-0.0.2-setup.exe',
          downloadUrl: 'https://example.com/win-x64-setup.exe',
          size: 100,
        ),
        ReleaseAsset(
          name: '图学基础教程习题解答-Android-arm64-0.0.2.apk',
          downloadUrl: 'https://example.com/android-arm64.apk',
          size: 100,
        ),
        ReleaseAsset(
          name: '图学基础教程习题解答-Android-x86_64-0.0.2.apk',
          downloadUrl: 'https://example.com/android-x86_64.apk',
          size: 100,
        ),
        ReleaseAsset(
          name: '图学基础教程习题解答-Linux-arm64-0.0.2.AppImage',
          downloadUrl: 'https://example.com/linux-arm64.AppImage',
          size: 100,
        ),
      ];

      expect(
        UpdateService.matchAssetForPlatform(
          assets,
          const PlatformTargetInfo(
            os: 'windows',
            arch: 'arm64',
            supportsInAppDownload: true,
            supportsDirectInstall: true,
          ),
        )?.name,
        '图学基础教程习题解答-Windows-arm64-0.0.2-setup.exe',
      );
      expect(
        UpdateService.matchAssetForPlatform(
          assets,
          const PlatformTargetInfo(
            os: 'android',
            arch: 'arm64',
            supportsInAppDownload: true,
            supportsDirectInstall: true,
          ),
        )?.name,
        '图学基础教程习题解答-Android-arm64-0.0.2.apk',
      );
      expect(
        UpdateService.matchAssetForPlatform(
          assets,
          const PlatformTargetInfo(
            os: 'linux',
            arch: 'arm64',
            supportsInAppDownload: true,
            supportsDirectInstall: true,
          ),
        )?.name,
        '图学基础教程习题解答-Linux-arm64-0.0.2.AppImage',
      );
    });
  });

  testWidgets('HomePage loads and renders 177 problems', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'tuxuejieda_next',
      packageName: 'com.kepler16f.tuxuejieda.tuxuejieda_next',
      version: '0.0.1',
      buildNumber: '1',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = CurriculumRepository();
    await tester.runAsync(() => repo.initialize());

    await tester.pumpWidget(MaterialApp(home: HomePage(repo: repo)));
    await tester.pumpAndSettle();

    expect(find.text('图学基础教程习题解答'), findsOneWidget);
    expect(find.text('已启用 177 题'), findsOneWidget);
    expect(find.text('配套动画 67 题'), findsOneWidget);
    expect(find.text('第 11 页 No.1 题'), findsOneWidget);
  });
}
