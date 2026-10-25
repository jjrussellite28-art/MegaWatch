import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/platform_util.dart';
import 'cursor_auto_hide.dart';
import 'windows_gamepad_service.dart';

/// "Remote mode" on Windows: the whole app uses its TV layout and focus
/// navigation, runs full screen, and an Xbox / PlayStation controller or HTPC
/// remote drives it like a TV remote on an Android box. The mouse pointer
/// hides itself when it is not being used.
///
/// Everything here can be changed in Settings (Windows display). The old
/// `--remote-mode=off` / `--remote-mode=on` start-up options still work.
class DesktopRemoteMode {
  DesktopRemoteMode._();

  static const String _remoteKey = 'desktop_remote_mode_v1';
  static const String _fullScreenKey = 'desktop_fullscreen_start_v1';
  static const String _hideCursorKey = 'desktop_hide_cursor_v1';

  static Future<bool> remoteModeEnabled() => _read(_remoteKey);
  static Future<bool> fullScreenOnStart() => _read(_fullScreenKey);
  static Future<bool> hideCursorWhenIdle() => _read(_hideCursorKey);

  static Future<void> setRemoteModeEnabled(bool value) =>
      _write(_remoteKey, value);

  static Future<void> setFullScreenOnStart(bool value) =>
      _write(_fullScreenKey, value);

  static Future<void> setHideCursorWhenIdle(bool value) async {
    await _write(_hideCursorKey, value);
    CursorAutoHide.instance.setEnabled(value);
  }

  static Future<bool> _read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('DesktopRemoteMode: could not save $key ($e)');
    }
  }

  static Future<void> start(List<String> launchArguments) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final arg in launchArguments) {
        if (arg == '--remote-mode=off') await prefs.setBool(_remoteKey, false);
        if (arg == '--remote-mode=on') await prefs.setBool(_remoteKey, true);
      }
      final enabled = prefs.getBool(_remoteKey) ?? true;
      final fullScreen = prefs.getBool(_fullScreenKey) ?? true;
      final hideCursor = prefs.getBool(_hideCursorKey) ?? true;
      PlatformUtil.desktopRemoteMode = enabled;
      if (enabled) WindowsGamepadService.instance.start();
      CursorAutoHide.instance.start(enabled: hideCursor);
      if (fullScreen) unawaited(_enterFullScreen());
    } catch (e) {
      debugPrint('DesktopRemoteMode: could not start ($e)');
    }
  }

  /// Full screen is asked for twice: once now, and once a moment later in case
  /// the window was not on screen yet the first time.
  static Future<void> _enterFullScreen() async {
    Future<void> apply() async {
      try {
        if (!await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(true);
        }
      } catch (e) {
        debugPrint('DesktopRemoteMode: full screen failed ($e)');
      }
    }

    await apply();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await apply();
  }
}
