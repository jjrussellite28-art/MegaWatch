import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'open_windows.dart';
import 'playnite_service.dart';

/// Keeps Playnite open in the background so switching to it is instant, and
/// lets the controller (Back + Start held together) switch back to Debrify.
///
/// Debrify and Playnite stay two separate programs; this just brings the
/// right window to the front.
class PlayniteSwitcher {
  PlayniteSwitcher._();
  static final PlayniteSwitcher instance = PlayniteSwitcher._();

  bool _started = false;
  Timer? _timer;
  bool _comboWasDown = false;
  Pointer<Uint8>? _state;
  late final int Function(int, Pointer<Uint8>) _getState;

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// Call once after the app window is up.
  void start() {
    if (_started || !supported) return;
    try {
      for (final name in const ['xinput1_4.dll', 'xinput1_3.dll', 'xinput9_1_0.dll']) {
        try {
          _getState = DynamicLibrary.open(name)
              .lookup<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>>('XInputGetState')
              .asFunction();
          _state = calloc<Uint8>(16);
          break;
        } catch (_) {}
      }
      if (_state == null) return;
    } catch (_) {
      return;
    }
    _started = true;
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) => _tick());
    Future<void>.delayed(const Duration(seconds: 6), _prelaunch);
  }

  OpenWindow? _findPlaynite() {
    for (final w in OpenWindows.instance.list()) {
      if (w.title == 'Playnite' || w.title.startsWith('Playnite ')) return w;
    }
    return null;
  }

  void _tick() {
    var down = false;
    for (var i = 0; i < 4; i++) {
      if (_getState(i, _state!) != 0) continue;
      final b = ByteData.sublistView(_state!.asTypedList(16)).getUint16(4, Endian.little);
      if (b & 0x0010 != 0 && b & 0x0020 != 0) down = true; // Start + Back
    }
    final pressed = down && !_comboWasDown;
    _comboWasDown = down;
    if (pressed && !OpenWindows.instance.foregroundIsSelf()) {
      backToDebrify();
    }
  }

  /// Brings Debrify to the front.
  Future<void> backToDebrify() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  /// Starts Playnite in the background (minimized) if it isn't running yet.
  Future<void> _prelaunch() async {
    if (_findPlaynite() != null) return;
    final ok = await PlayniteService.instance.openPlaynite();
    if (!ok) return;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final w = _findPlaynite();
      if (w != null) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        OpenWindows.instance.minimize(w.hwnd);
        await backToDebrify();
        return;
      }
    }
  }

  /// Switches to Playnite right away; starts it first if it isn't open.
  Future<bool> openPlaynite() async {
    var w = _findPlaynite();
    if (w == null) {
      final ok = await PlayniteService.instance.openPlaynite();
      if (!ok) return false;
      for (var i = 0; i < 40 && w == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        w = _findPlaynite();
      }
      return true; // Playnite opens itself in front when it starts.
    }
    OpenWindows.instance.switchTo(w.hwnd);
    return true;
  }
}
