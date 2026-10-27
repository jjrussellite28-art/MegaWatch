import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme_scope.dart';

/// "Exit" button for the desktop side menus (Windows only). Closes Debrify,
/// which returns to whatever launched it (for example the Home Shell).
class AppExitButton extends StatefulWidget {
  const AppExitButton({super.key});

  static bool get supported => !kIsWeb && Platform.isWindows;

  static Future<void> exitApp() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  @override
  State<AppExitButton> createState() => _AppExitButtonState();
}

class _AppExitButtonState extends State<AppExitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!AppExitButton.supported) return const SizedBox.shrink();
    final app = AppThemeScope.of(context);
    return Padding(
      key: const ValueKey('app-exit-button'),
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: AppExitButton.exitApp,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.redAccent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: app.shape.br(14),
              border: Border.all(color: app.fade(app.core.tx, 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.power_settings_new_rounded,
                  size: 22,
                  color: _hovered ? Colors.redAccent : app.fade(app.core.tx, 0.7),
                ),
                const SizedBox(height: 2),
                Text(
                  'Exit',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.68),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
