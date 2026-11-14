import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Applies the user's screen-rotation preference (Android only).
class OrientationService {
  OrientationService._();

  /// [followSensor] true → follow the gravity sensor (all orientations);
  /// false → lock to portrait. No-op on non-Android platforms.
  static Future<void> apply({required bool followSensor}) async {
    if (kIsWeb || !Platform.isAndroid) return;
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
