import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:window_manager/window_manager.dart';

/// Home Shell has two looks:
///  * full  – the big home screen (fullscreen)
///  * bar   – a small bar floating on top of whatever app or game is open,
///            shown when you hold the Guide button.
class ShellMode {
  ShellMode._();
  static final ShellMode instance = ShellMode._();

  final ValueNotifier<bool> bar = ValueNotifier<bool>(false);

  /// Goes up by one each time the bar is asked for, so it re-appears even when
  /// it is already in bar mode but hidden.
  final ValueNotifier<int> barRequest = ValueNotifier<int>(0);

  void showBar() {
    bar.value = true;
    barRequest.value++;
  }

  void showFull() {
    bar.value = false;
    barRequest.value++;
  }

  /// Makes the real window match the current look.
  Future<void> applyWindow({required int itemCount}) async {
    if (bar.value) {
      final display = ui.PlatformDispatcher.instance.displays.first;
      final screenW = display.size.width / display.devicePixelRatio;
      final width = (itemCount * 76.0 + 56).clamp(380.0, screenW - 80.0);
      await windowManager.setFullScreen(false);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(ui.Size(width, 132));
      await windowManager.setAlignment(Alignment.topCenter);
      await windowManager.show();
      await windowManager.focus();
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    }
  }
}
