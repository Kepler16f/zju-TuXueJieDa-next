import 'package:flutter/services.dart';

import 'platform_caps.dart';

/// Applies the user's screen-rotation preference (Android only).
class OrientationService {
  OrientationService._();

  /// [followSensor] true → follow the gravity sensor (all orientations);
  /// false → lock to portrait. No-op on non-Android platforms.
  static Future<void> apply({required bool followSensor}) async {
    if (!PlatformCaps.isAndroid) return;
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
