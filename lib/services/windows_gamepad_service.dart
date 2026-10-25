import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform, pid;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lets an Xbox-style controller (XInput) and ordinary HTPC remotes drive the
/// whole app on Windows, exactly like a TV remote on an Android box.
///
/// The controller is turned into plain keyboard presses (arrows, Enter,
/// Escape, Page Up/Down, Play/Pause), so every screen that already works with
/// a TV remote works with a controller. Keys are only sent while the Debrify
/// window is the active window — a game or another app in front is never
/// touched.
///
///   D-pad / left stick  arrows          A  Enter (OK)
///   B / Back (View)     Escape (back)   Start  Play/Pause
///   LB / RB             Page Up / Down (previous / next channel)
class WindowsGamepadService {
  WindowsGamepadService._();
  static final WindowsGamepadService instance = WindowsGamepadService._();

  // XInput button bits.
  static const int _dpadUp = 0x0001;
  static const int _dpadDown = 0x0002;
  static const int _dpadLeft = 0x0004;
  static const int _dpadRight = 0x0008;
  static const int _start = 0x0010;
  static const int _back = 0x0020;
  static const int _lb = 0x0100;
  static const int _rb = 0x0200;
  static const int _a = 0x1000;
  static const int _b = 0x2000;

  // Windows virtual-key codes.
  static const int _vkReturn = 0x0D;
  static const int _vkEscape = 0x1B;
  static const int _vkPageUp = 0x21;
  static const int _vkPageDown = 0x22;
  static const int _vkLeft = 0x25;
  static const int _vkUp = 0x26;
  static const int _vkRight = 0x27;
  static const int _vkDown = 0x28;
  static const int _vkPlayPause = 0xB3;

  static const int _keyEventExtended = 0x0001;
  static const int _keyEventKeyUp = 0x0002;

  // Keys that need the "extended key" flag to be read as the navigation keys.
  static const Set<int> _extendedKeys = {
    _vkPageUp,
    _vkPageDown,
    _vkLeft,
    _vkUp,
    _vkRight,
    _vkDown,
    _vkPlayPause,
  };

  bool _started = false;
  Timer? _timer;
  Pointer<Uint8>? _state;
  int _lastScan = 0;
  List<int> _connected = const [];

  final Set<int> _held = <int>{};
  final Map<int, int> _nextRepeatMs = <int, int>{};
  final Stopwatch _clock = Stopwatch()..start();

  late final int Function(int, Pointer<Uint8>) _getState;
  late final void Function(int, int, int, int) _keybdEvent;
  late final int Function() _foregroundWindow;
  late final int Function(int, Pointer<Uint32>) _windowProcessId;

  /// Starts polling. Safe to call more than once; does nothing off Windows or
  /// when XInput can't be loaded.
  void start() {
    if (_started || kIsWeb || !Platform.isWindows) return;
    try {
      final xinput = _openXInput();
      _getState = xinput
          .lookup<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>>(
            'XInputGetState',
          )
          .asFunction();
      final user32 = DynamicLibrary.open('user32.dll');
      _keybdEvent = user32
          .lookup<NativeFunction<Void Function(Uint8, Uint8, Uint32, IntPtr)>>(
            'keybd_event',
          )
          .asFunction();
      _foregroundWindow = user32
          .lookup<NativeFunction<IntPtr Function()>>('GetForegroundWindow')
          .asFunction();
      _windowProcessId = user32
          .lookup<NativeFunction<Uint32 Function(IntPtr, Pointer<Uint32>)>>(
            'GetWindowThreadProcessId',
          )
          .asFunction();
      _state = calloc<Uint8>(16);
    } catch (e) {
      debugPrint('WindowsGamepadService: unavailable ($e)');
      return;
    }
    _started = true;
    // HTPC remotes: the "Back" button arrives as Browser Back. The app's
    // screens listen for Escape, so turn one into the other.
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  DynamicLibrary _openXInput() {
    for (final name in const [
      'xinput1_4.dll',
      'xinput1_3.dll',
      'xinput9_1_0.dll',
    ]) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {}
    }
    throw StateError('XInput not found');
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      _tap(_vkEscape);
      return true;
    }
    return false;
  }

  bool get _appIsActive {
    final hwnd = _foregroundWindow();
    if (hwnd == 0) return false;
    final out = calloc<Uint32>();
    try {
      _windowProcessId(hwnd, out);
      return out.value == pid;
    } finally {
      calloc.free(out);
    }
  }

  void _sendKey(int vk, {required bool down}) {
    var flags = _extendedKeys.contains(vk) ? _keyEventExtended : 0;
    if (!down) flags |= _keyEventKeyUp;
    _keybdEvent(vk, 0, flags, 0);
  }

  void _tap(int vk) {
    _sendKey(vk, down: true);
    _sendKey(vk, down: false);
  }

  void _releaseAll() {
    for (final vk in _held) {
      _sendKey(vk, down: false);
    }
    _held.clear();
    _nextRepeatMs.clear();
  }

  void _tick() {
    final nowMs = _clock.elapsedMilliseconds;

    // Look for connected controllers about once a second; polling an empty
    // slot every frame is wasteful.
    if (nowMs - _lastScan > 1000) {
      _lastScan = nowMs;
      _connected = [
        for (var i = 0; i < 4; i++)
          if (_getState(i, _state!) == 0) i,
      ];
    }

    final wanted = <int>{};
    if (_connected.isNotEmpty && _appIsActive) {
      for (final index in _connected) {
        if (_getState(index, _state!) != 0) continue;
        final data = ByteData.sublistView(_state!.asTypedList(16));
        final buttons = data.getUint16(4, Endian.little);
        final lx = data.getInt16(8, Endian.little);
        final ly = data.getInt16(10, Endian.little);
        const stick = 16000;
        if (buttons & _dpadUp != 0 || ly > stick) wanted.add(_vkUp);
        if (buttons & _dpadDown != 0 || ly < -stick) wanted.add(_vkDown);
        if (buttons & _dpadLeft != 0 || lx < -stick) wanted.add(_vkLeft);
        if (buttons & _dpadRight != 0 || lx > stick) wanted.add(_vkRight);
        if (buttons & _a != 0) wanted.add(_vkReturn);
        if (buttons & (_b | _back) != 0) wanted.add(_vkEscape);
        if (buttons & _start != 0) wanted.add(_vkPlayPause);
        if (buttons & _lb != 0) wanted.add(_vkPageUp);
        if (buttons & _rb != 0) wanted.add(_vkPageDown);
      }
    }

    // Released keys.
    for (final vk in _held.difference(wanted).toList()) {
      _sendKey(vk, down: false);
      _held.remove(vk);
      _nextRepeatMs.remove(vk);
    }
    // New presses, then held-key repeats (like a keyboard's typematic repeat).
    for (final vk in wanted) {
      if (_held.add(vk)) {
        _sendKey(vk, down: true);
        _nextRepeatMs[vk] = nowMs + (_isNavigation(vk) ? 350 : 500);
      } else if (nowMs >= (_nextRepeatMs[vk] ?? nowMs + 1)) {
        _sendKey(vk, down: true);
        _nextRepeatMs[vk] = nowMs + (_isNavigation(vk) ? 90 : 40);
      }
    }
    if (_connected.isEmpty && _held.isNotEmpty) _releaseAll();
  }

  bool _isNavigation(int vk) =>
      vk == _vkUp ||
      vk == _vkDown ||
      vk == _vkLeft ||
      vk == _vkRight ||
      vk == _vkPageUp ||
      vk == _vkPageDown;
}
