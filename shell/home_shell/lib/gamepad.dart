import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform, pid;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lets an Xbox-style controller (XInput) and ordinary HTPC remotes drive the
/// home screen on Windows, exactly like a TV remote on an Android box.
///
/// The controller is turned into plain keyboard presses (arrows, Enter,
/// Escape, Page Up/Down, Play/Pause), so every screen that already works with
/// a TV remote works with a controller. Keys are only sent while the Home Shell
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
  static const int _x = 0x4000;
  static const int _y = 0x8000;

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
  static const int _vkF2 = 0x71; // X / Square: edit or close
  static const int _vkF3 = 0x72; // Y / Triangle: add

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

  /// The Xbox/Guide button (the big logo button). Windows hides it from the
  /// normal XInput call, so it is read through the undocumented XInputGetStateEx.
  static const int _guide = 0x0400;
  int Function(int, Pointer<Uint8>)? _getStateEx;
  Pointer<Uint8>? _exState;
  bool _guideWasDown = false;

  /// Called when the Home gesture is used while another app is in front.
  void Function()? onHomeRequested;
  Pointer<Uint8>? _state;
  int _lastScan = 0;
  List<int> _connected = const [];

  /// Other (non-Xbox) controllers, read through the older Windows joystick
  /// API: PlayStation pads, generic USB pads, GameSir in DirectInput mode.
  List<int> _joyConnected = const [];
  Pointer<Uint8>? _joyInfo;
  Pointer<Uint8>? _joyCaps;
  bool _joyOk = false;
  final Map<int, _PadKind> _joyKinds = <int, _PadKind>{};

  /// Name of the controller last seen driving the app, e.g. "Xbox controller"
  /// or "PlayStation controller". Null when none is connected.
  final ValueNotifier<String?> controllerName = ValueNotifier<String?>(null);

  final Set<int> _held = <int>{};
  final Map<int, int> _nextRepeatMs = <int, int>{};
  final Stopwatch _clock = Stopwatch()..start();

  late final int Function(int, Pointer<Uint8>) _getState;
  late final void Function(int, int, int, int) _keybdEvent;
  late final int Function() _foregroundWindow;
  late final int Function(int, Pointer<Uint32>) _windowProcessId;
  late final int Function(int, Pointer<Uint8>) _joyGetPosEx;
  late final int Function(int, Pointer<Uint8>, int) _joyGetDevCaps;

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
      _exState = calloc<Uint8>(16);
      _asyncKey = user32
          .lookup<NativeFunction<Int16 Function(Int32)>>('GetAsyncKeyState')
          .asFunction();
      try {
        final kernel = DynamicLibrary.open('kernel32.dll');
        final loadLib = kernel
            .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>('LoadLibraryA')
            .asFunction<int Function(Pointer<Utf8>)>();
        final getProc = kernel
            .lookup<NativeFunction<IntPtr Function(IntPtr, IntPtr)>>('GetProcAddress')
            .asFunction<int Function(int, int)>();
        for (final name in const ['xinput1_4.dll', 'xinput1_3.dll']) {
          final n = name.toNativeUtf8();
          final h = loadLib(n);
          calloc.free(n);
          if (h == 0) continue;
          final addr = getProc(h, 100); // ordinal 100 = XInputGetStateEx
          if (addr != 0) {
            _getStateEx = Pointer<
              NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>
            >.fromAddress(addr).asFunction();
            break;
          }
        }
      } catch (e) {
        debugPrint('Guide button unavailable ($e)');
      }
      try {
        final winmm = DynamicLibrary.open('winmm.dll');
        _joyGetPosEx = winmm
            .lookup<NativeFunction<Uint32 Function(Uint32, Pointer<Uint8>)>>(
              'joyGetPosEx',
            )
            .asFunction();
        _joyGetDevCaps = winmm
            .lookup<
              NativeFunction<Uint32 Function(IntPtr, Pointer<Uint8>, Uint32)>
            >('joyGetDevCapsW')
            .asFunction();
        _joyInfo = calloc<Uint8>(52);
        _joyCaps = calloc<Uint8>(1024);
        _joyOk = true;
      } catch (e) {
        debugPrint('WindowsGamepadService: joystick API unavailable ($e)');
      }
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

  int _guideHeldSince = -1;
  bool _guideFired = false;
  bool _hotkeyWasDown = false;
  int Function(int)? _asyncKey;

  /// "Home" gesture: HOLD the Guide button for one second (or press
  /// Ctrl+Alt+H) from any app to bring the home screen forward. Nothing is
  /// closed, and a quick tap of Guide still goes to the other app untouched
  /// (Playnite, Steam, Game Bar), because this only watches the button.
  void _checkGuide() {
    final nowMs = _clock.elapsedMilliseconds;
    var wantHome = false;

    final ex = _getStateEx;
    if (ex != null && _connected.isNotEmpty) {
      var down = false;
      for (final i in _connected) {
        if (ex(i, _exState!) != 0) continue;
        final b = ByteData.sublistView(_exState!.asTypedList(16))
            .getUint16(4, Endian.little);
        if (b & _guide != 0) down = true;
      }
      if (down) {
        if (_guideHeldSince < 0) _guideHeldSince = nowMs;
        if (!_guideFired && nowMs - _guideHeldSince >= 1000) {
          _guideFired = true;
          wantHome = true;
        }
      } else {
        _guideHeldSince = -1;
        _guideFired = false;
      }
    }

    final key = _asyncKey;
    if (key != null) {
      final combo = key(0x11) & 0x8000 != 0 &&
          key(0x12) & 0x8000 != 0 &&
          key(0x48) & 0x8000 != 0;
      if (combo && !_hotkeyWasDown) wantHome = true;
      _hotkeyWasDown = combo;
    }

    if (wantHome && !_appIsActive) onHomeRequested?.call();
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

    if (_joyOk && nowMs - _lastJoyScan > 1000) {
      _lastJoyScan = nowMs;
      _scanJoysticks();
    }

    _checkGuide();

    final wanted = <int>{};
    if (_connected.isEmpty && _joyConnected.isNotEmpty && _appIsActive) {
      for (final id in _joyConnected) {
        _readJoystick(id, wanted);
      }
    }
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
        if (buttons & _x != 0) wanted.add(_vkF2);
        if (buttons & _y != 0) wanted.add(_vkF3);
        if (buttons & _lb != 0) wanted.add(_vkPageUp);
        if (buttons & _rb != 0) wanted.add(_vkPageDown);
      }
    }
    if (_connected.isNotEmpty) {
      controllerName.value = 'Xbox controller';
    } else if (_joyConnected.isNotEmpty) {
      controllerName.value = _joyKinds[_joyConnected.first]?.label;
    } else {
      controllerName.value = null;
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
    if (_connected.isEmpty && _joyConnected.isEmpty && _held.isNotEmpty) {
      _releaseAll();
    }
  }

  int _lastJoyScan = 0;

  void _scanJoysticks() {
    final found = <int>[];
    final info = _joyInfo!;
    for (var id = 0; id < 16; id++) {
      info.asTypedList(52).fillRange(0, 52, 0);
      ByteData.sublistView(info.asTypedList(52)).setUint32(0, 52, Endian.little);
      ByteData.sublistView(info.asTypedList(52)).setUint32(4, 0xFF, Endian.little);
      if (_joyGetPosEx(id, info) != 0) continue;
      found.add(id);
      _joyKinds.putIfAbsent(id, () => _identify(id));
    }
    _joyKinds.removeWhere((id, _) => !found.contains(id));
    _joyConnected = found;
  }

  _PadKind _identify(int id) {
    try {
      final caps = _joyCaps!;
      if (_joyGetDevCaps(id, caps, 728) != 0) return _PadKind.generic;
      final vendor = ByteData.sublistView(caps.asTypedList(8)).getUint16(
        0,
        Endian.little,
      );
      final nameBytes = caps.asTypedList(68).sublist(4, 68);
      final name = String.fromCharCodes(
        Uint16List.view(Uint8List.fromList(nameBytes).buffer),
      ).split('\u0000').first.toLowerCase();
      if (vendor == 0x054C ||
          name.contains('dualsense') ||
          name.contains('dualshock') ||
          name.contains('wireless controller')) {
        return _PadKind.playstation;
      }
    } catch (_) {}
    return _PadKind.generic;
  }

  /// Reads one non-Xbox controller and adds the keys it is pressing.
  void _readJoystick(int id, Set<int> wanted) {
    final info = _joyInfo!;
    info.asTypedList(52).fillRange(0, 52, 0);
    final data = ByteData.sublistView(info.asTypedList(52));
    data.setUint32(0, 52, Endian.little);
    data.setUint32(4, 0xFF, Endian.little);
    if (_joyGetPosEx(id, info) != 0) return;
    final x = data.getUint32(8, Endian.little);
    final y = data.getUint32(12, Endian.little);
    final buttons = data.getUint32(32, Endian.little);
    final pov = data.getUint32(40, Endian.little) & 0xFFFF;
    const low = 32768 - 16000;
    const high = 32768 + 16000;
    if (y < low) wanted.add(_vkUp);
    if (y > high) wanted.add(_vkDown);
    if (x < low) wanted.add(_vkLeft);
    if (x > high) wanted.add(_vkRight);
    if (pov != 0xFFFF) {
      if (pov >= 31500 || pov <= 4500) wanted.add(_vkUp);
      if (pov >= 4500 && pov <= 13500) wanted.add(_vkRight);
      if (pov >= 13500 && pov <= 22500) wanted.add(_vkDown);
      if (pov >= 22500 && pov <= 31500) wanted.add(_vkLeft);
    }
    bool pressed(int n) => buttons & (1 << n) != 0;
    final kind = _joyKinds[id] ?? _PadKind.generic;
    if (kind == _PadKind.playstation) {
      // Windows numbers a PlayStation pad: 0 Square, 1 Cross, 2 Circle,
      // 3 Triangle, 4 L1, 5 R1, 8 Share, 9 Options.
      if (pressed(1)) wanted.add(_vkReturn); // Cross = OK
      if (pressed(2) || pressed(8)) wanted.add(_vkEscape); // Circle = back
      if (pressed(9)) wanted.add(_vkPlayPause); // Options
      if (pressed(0)) wanted.add(_vkF2); // Square
      if (pressed(3)) wanted.add(_vkF3); // Triangle
      if (pressed(4)) wanted.add(_vkPageUp);
      if (pressed(5)) wanted.add(_vkPageDown);
    } else {
      // Generic pad (Xbox-style order): 0 A, 1 B, 4 LB, 5 RB, 6 Back, 7 Start.
      if (pressed(0)) wanted.add(_vkReturn);
      if (pressed(1) || pressed(6)) wanted.add(_vkEscape);
      if (pressed(7)) wanted.add(_vkPlayPause);
      if (pressed(2)) wanted.add(_vkF2);
      if (pressed(3)) wanted.add(_vkF3);
      if (pressed(4)) wanted.add(_vkPageUp);
      if (pressed(5)) wanted.add(_vkPageDown);
    }
  }

  bool _isNavigation(int vk) =>
      vk == _vkUp ||
      vk == _vkDown ||
      vk == _vkLeft ||
      vk == _vkRight ||
      vk == _vkPageUp ||
      vk == _vkPageDown;
}

enum _PadKind {
  generic('Game controller'),
  playstation('PlayStation controller');

  const _PadKind(this.label);
  final String label;
}
