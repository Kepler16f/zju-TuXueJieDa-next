import 'package:flutter/services.dart';

/// Native window channel (Windows tray contract shared with the native side).
class WindowChannel {
  static const MethodChannel _channel = MethodChannel('com.kepler16f.tuxuejieda/window');
  static Future<void> setCloseToTray(bool enabled) async {
    try { await _channel.invokeMethod('setCloseToTray', {'enabled': enabled}); } catch (_) {}
  }
}
