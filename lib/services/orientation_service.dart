import 'package:flutter/services.dart';

import 'platform_caps.dart';

/// Applies the user's screen-rotation preference (Android and HarmonyOS).
class OrientationService {
  OrientationService._();

  /// [followSensor] true → follow the gravity sensor (all orientations);
  /// false → lock to portrait. No-op on non-handset platforms.
  ///
  /// On HarmonyOS the OHOS embedder forwards this to the ability's
  /// setPreferredOrientation; the generated module.json5 additionally
  /// declares `auto_rotation` (see scripts/setup_ohos.sh) so rotation works
  /// even before Flutter's first SystemChrome call lands.
  static Future<void> apply({required bool followSensor}) async {
    if (!PlatformCaps.isAndroid && !PlatformCaps.isOhos) return;
    await SystemChrome.setPreferredOrientations(
      followSensor
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }
}
