import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuxuejieda_next/pages/consent_page.dart';
import 'package:tuxuejieda_next/services/consent_service.dart';

/// 首次启动隐私授权页：必须显式勾选并同意才能进入，且同意状态持久化。
void main() {
  group('ConsentService', () {
    testWidgets('默认未同意，同意后可持久化，撤回后清空', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = ConsentService();
      expect(await service.hasAgreed(), isFalse);

      await service.agree();
      expect(await service.hasAgreed(), isTrue);
      expect(await service.agreedAt(), isNotNull);

      await service.revoke();
      expect(await service.hasAgreed(), isFalse);
    });

    testWidgets('协议地址为公开可访问的 GitHub Pages 链接', (tester) async {
      expect(ConsentService.privacyPolicyUrl.startsWith('https://'), isTrue);
      expect(ConsentService.userAgreementUrl.startsWith('https://'), isTrue);
      expect(ConsentService.privacyPolicyUrl, contains('privacy.html'));
      expect(ConsentService.userAgreementUrl, contains('terms.html'));
    });
  });

  group('ConsentPage', () {
    testWidgets('未勾选时同意按钮禁用；勾选后可同意并回调', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      var agreed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ConsentPage(onAgreed: () async => agreed = true),
        ),
      );
      await tester.pumpAndSettle();

      // 两个按钮都在
      expect(find.text('同意并继续'), findsOneWidget);
      expect(find.text('拒绝并退出'), findsOneWidget);
      // 入口可点击的协议链接
      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('用户协议'), findsOneWidget);

      // 未勾选时「同意并继续」不可用
      final agreeBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '同意并继续'),
      );
      expect(agreeBtn.onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final enabledBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '同意并继续'),
      );
      expect(enabledBtn.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, '同意并继续'));
      await tester.pumpAndSettle();
      expect(agreed, isTrue);
      expect(await ConsentService().hasAgreed(), isTrue);
    });
  });
}
