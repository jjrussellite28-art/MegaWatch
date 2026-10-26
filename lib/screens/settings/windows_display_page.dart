import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/desktop_remote_mode.dart';
import '../../theme/app_theme_scope.dart';
import 'widgets/settings_widgets.dart';

/// Windows-only display options: full screen on start-up, hiding the mouse
/// pointer when idle, and the TV-style "remote mode".
class WindowsDisplayPage extends StatefulWidget {
  const WindowsDisplayPage({super.key});

  @override
  State<WindowsDisplayPage> createState() => _WindowsDisplayPageState();
}

class _WindowsDisplayPageState extends State<WindowsDisplayPage> {
  bool _loading = true;
  bool _fullScreenOnStart = true;
  bool _hideCursor = true;
  bool _remoteMode = true;
  bool _fullScreenNow = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fullScreen = await DesktopRemoteMode.fullScreenOnStart();
    final hide = await DesktopRemoteMode.hideCursorWhenIdle();
    final remote = await DesktopRemoteMode.remoteModeEnabled();
    var now = false;
    try {
      now = await windowManager.isFullScreen();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _fullScreenOnStart = fullScreen;
      _hideCursor = hide;
      _remoteMode = remote;
      _fullScreenNow = now;
      _loading = false;
    });
  }

  Future<void> _toggleNow(bool value) async {
    setState(() => _fullScreenNow = value);
    try {
      await windowManager.setFullScreen(value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Windows display',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Windows display',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.desktop_windows_rounded,
                  title: 'Windows display',
                  subtitle: 'Full screen, mouse pointer and remote mode',
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: '',
                  children: [
                    SettingsToggleTile(
                      icon: Icons.fullscreen_rounded,
                      title: 'Full screen now',
                      subtitle: 'Turn the window bar on or off',
                      value: _fullScreenNow,
                      onChanged: _toggleNow,
                    ),
                    SettingsToggleTile(
                      icon: Icons.open_in_full_rounded,
                      title: 'Start in full screen',
                      subtitle: 'Open Debrify full screen every time',
                      value: _fullScreenOnStart,
                      onChanged: (v) async {
                        setState(() => _fullScreenOnStart = v);
                        await DesktopRemoteMode.setFullScreenOnStart(v);
                      },
                    ),
                    SettingsToggleTile(
                      icon: Icons.mouse_rounded,
                      title: 'Hide mouse when idle',
                      subtitle: 'In full screen, hide the pointer after 3 seconds',
                      value: _hideCursor,
                      onChanged: (v) async {
                        setState(() => _hideCursor = v);
                        await DesktopRemoteMode.setHideCursorWhenIdle(v);
                      },
                    ),
                    SettingsToggleTile(
                      icon: Icons.sports_esports_rounded,
                      title: 'Remote mode (TV layout)',
                      subtitle: 'Controller and remote friendly. Restart to apply',
                      value: _remoteMode,
                      onChanged: (v) async {
                        setState(() => _remoteMode = v);
                        await DesktopRemoteMode.setRemoteModeEnabled(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'To close Debrify while it is full screen, press Alt+F4, '
                  'or press Back on the main screen twice.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// The same options as [WindowsDisplayPage], as a pane for the Settings rail
/// ("Controller & Screen"). [nodes] are the pane's focus nodes, in row order.
class WindowsDisplayPane extends StatefulWidget {
  const WindowsDisplayPane({super.key, required this.nodes});

  final List<FocusNode> nodes;

  @override
  State<WindowsDisplayPane> createState() => _WindowsDisplayPaneState();
}

class _WindowsDisplayPaneState extends State<WindowsDisplayPane> {
  bool _loading = true;
  bool _fullScreenOnStart = true;
  bool _hideCursor = true;
  bool _remoteMode = true;
  bool _fullScreenNow = false;

  bool get _supported => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_supported) {
      setState(() => _loading = false);
      return;
    }
    final fullScreen = await DesktopRemoteMode.fullScreenOnStart();
    final hide = await DesktopRemoteMode.hideCursorWhenIdle();
    final remote = await DesktopRemoteMode.remoteModeEnabled();
    var now = false;
    try {
      now = await windowManager.isFullScreen();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _fullScreenOnStart = fullScreen;
      _hideCursor = hide;
      _remoteMode = remote;
      _fullScreenNow = now;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (!_supported) {
      return Text(
        'These options are for the Windows app.',
        style: TextStyle(fontSize: 14, color: t.dim),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    FocusNode? node(int i) => i < widget.nodes.length ? widget.nodes[i] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: '',
          children: [
            SettingsToggleTile(
              icon: Icons.fullscreen_rounded,
              title: 'Full screen now',
              subtitle: 'Same as pressing F11',
              value: _fullScreenNow,
              focusNode: node(0),
              onChanged: (v) async {
                setState(() => _fullScreenNow = v);
                try {
                  await windowManager.setFullScreen(v);
                } catch (_) {}
              },
            ),
            SettingsToggleTile(
              icon: Icons.open_in_full_rounded,
              title: 'Start in full screen',
              subtitle: 'Off = open in a normal window',
              value: _fullScreenOnStart,
              focusNode: node(1),
              onChanged: (v) async {
                setState(() => _fullScreenOnStart = v);
                await DesktopRemoteMode.setFullScreenOnStart(v);
              },
            ),
            SettingsToggleTile(
              icon: Icons.mouse_rounded,
              title: 'Hide mouse when idle',
              subtitle: 'In full screen, hide the pointer after 3 seconds',
              value: _hideCursor,
              focusNode: node(2),
              onChanged: (v) async {
                setState(() => _hideCursor = v);
                await DesktopRemoteMode.setHideCursorWhenIdle(v);
              },
            ),
            SettingsToggleTile(
              icon: Icons.sports_esports_rounded,
              title: 'Remote mode (TV layout)',
              subtitle: 'Controller friendly layout. Restart to apply',
              value: _remoteMode,
              focusNode: node(3),
              onChanged: (v) async {
                setState(() => _remoteMode = v);
                await DesktopRemoteMode.setRemoteModeEnabled(v);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'F11 switches full screen on and off anywhere in the app. '
          'The on-screen keyboard only appears when you use a controller; '
          'typing on a real keyboard just types. To close Debrify while it '
          'is full screen, press Alt+F4.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim),
        ),
      ],
    );
  }
}
