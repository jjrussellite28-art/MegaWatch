import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:window_manager/window_manager.dart';

import 'freezer.dart';
import 'settings.dart';

/// Controls the small bar window: where it sits, when it shows and hides, and
/// the temporary bigger window used for the Add/Edit and Power dialogs.
class ShellMode {
  ShellMode._();
  static final ShellMode instance = ShellMode._();

  /// Goes up by one each time the bar is asked for (hold Guide, Ctrl+Alt+H).
  final ValueNotifier<int> barRequest = ValueNotifier<int>(0);

  bool visible = false;

  /// [freeze] pauses the app in front (if the setting is on) so it doesn't keep
  /// running or reacting behind the bar. It is resumed by [hide].
  void showBar({bool freeze = true}) {
    if (freeze && ShellSettings.instance.freeze) {
      Freezer.instance.freezeForeground();
    }
    barRequest.value++;
  }

  Future<void> applyBar({required int itemCount}) async {
    final display = ui.PlatformDispatcher.instance.displays.first;
    final screenW = display.size.width / display.devicePixelRatio;
    final width = (itemCount * 70.0 + 64).clamp(320.0, screenW - 60.0);
    await windowManager.setFullScreen(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(ui.Size(width, 156));
    await windowManager.setAlignment(Alignment.topCenter);
    await windowManager.show();
    await windowManager.focus();
    visible = true;
  }

  Future<void> hide() async {
    visible = false;
    Freezer.instance.thawAll();
    await windowManager.hide();
  }

  /// A roomy window for dialogs; call [applyBar] afterwards to shrink back.
  Future<void> enterBig() async {
    await windowManager.setSize(const ui.Size(780, 640));
    await windowManager.setAlignment(Alignment.center);
    await windowManager.show();
    await windowManager.focus();
  }
}
