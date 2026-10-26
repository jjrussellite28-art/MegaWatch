import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Remembers whether the person is using a controller/remote or a real
/// keyboard and mouse, so the on-screen keyboard only pops up for the former.
class InputMode {
  InputMode._();
  static final InputMode instance = InputMode._();

  /// True when the last thing used was a controller / remote.
  final ValueNotifier<bool> controller = ValueNotifier<bool>(true);

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent || event is PointerScrollEvent) {
        _set(false);
      } else if (event is PointerHoverEvent && event.kind == PointerDeviceKind.mouse) {
        // Only real movement counts (not a pointer that is just sitting there).
        if (event.delta != Offset.zero) _set(false);
      }
    });
    HardwareKeyboard.instance.addHandler((event) {
      if (event is! KeyDownEvent) return false;
      if (_fromController) return false;
      final k = event.logicalKey;
      // Letters, digits, space, backspace = a real keyboard.
      final label = k.keyLabel;
      if ((label.length == 1 && label.trim().isNotEmpty) ||
          k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.backspace) {
        _set(false);
      }
      return false;
    });
  }

  bool _fromController = false;

  /// Called by the gamepad service around the key presses it injects.
  void noteController() {
    _fromController = true;
    _set(true);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      _fromController = false;
    });
  }

  void _set(bool value) {
    if (controller.value != value) controller.value = value;
  }
}
