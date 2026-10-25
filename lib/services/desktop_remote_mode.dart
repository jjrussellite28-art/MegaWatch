import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_util.dart';
import 'windows_gamepad_service.dart';

/// "Remote mode" on Windows: the whole app uses its TV layout and focus
/// navigation, and an Xbox-style controller or HTPC remote drives it like a
/// TV remote on an Android box.
///
/// On by default on Windows. To turn it off, start the app with
/// `--remote-mode=off` (and `--remote-mode=on` to turn it back on). The choice
/// is remembered.
class DesktopRemoteMode {
  DesktopRemoteMode._();

  static const String _prefsKey = 'desktop_remote_mode_v1';

  static Future<void> start(List<String> launchArguments) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final arg in launchArguments) {
        if (arg == '--remote-mode=off') await prefs.setBool(_prefsKey, false);
        if (arg == '--remote-mode=on') await prefs.setBool(_prefsKey, true);
      }
      final enabled = prefs.getBool(_prefsKey) ?? true;
      PlatformUtil.desktopRemoteMode = enabled;
      if (enabled) WindowsGamepadService.instance.start();
    } catch (e) {
      debugPrint('DesktopRemoteMode: could not start ($e)');
    }
  }
}
