import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动的隐私授权（隐私政策 + 用户协议）状态。
///
/// 依据《个人信息保护法》与常见应用商店审核要求，应用在首次启动时须以
/// 显著方式告知用户并取得同意，之后才可继续使用；本应用不收集任何
/// 上传型个人信息，所有学习数据仅存本地。
class ConsentService {
  static const _prefVersion = 'privacy_consent_version';
  static const _prefAgreedAt = 'privacy_consent_agreed_at';

  /// 当前协议版本。协议内容变更时递增，已同意过旧版本的用户会重新看到授权页。
  static const String currentPolicyVersion = '1.0';

  /// 隐私政策与用户协议的公开地址（GitHub Pages）。
  static const String privacyPolicyUrl =
      'https://kepler16f.github.io/zju-TuXueJieDa-next/privacy.html';
  static const String userAgreementUrl =
      'https://kepler16f.github.io/zju-TuXueJieDa-next/terms.html';
  static const String homeUrl =
      'https://kepler16f.github.io/zju-TuXieJieDa-next/';

  Future<bool> hasAgreed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefVersion) == currentPolicyVersion;
    } catch (_) {
      return false;
    }
  }

  Future<void> agree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVersion, currentPolicyVersion);
    await prefs.setString(
      _prefAgreedAt,
      DateTime.now().toIso8601String(),
    );
  }

  /// 撤回同意（设置页提供），下次启动重新展示授权页。
  Future<void> revoke() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefVersion);
    await prefs.remove(_prefAgreedAt);
  }

  Future<DateTime?> agreedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefAgreedAt);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }
}
