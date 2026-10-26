import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'cursor_hide.dart';
import 'gamepad.dart';
import 'home_screen.dart';
import 'shell_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Home Shell',
        size: Size(640, 156),
        backgroundColor: Color(0xFF11151F),
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
        skipTaskbar: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    // Hold Guide from any app: show the small bar on top of it.
    WindowsGamepadService.instance.onHomeRequested = () {
      ShellMode.instance.showBar();
    };
    WindowsGamepadService.instance.start();
    CursorAutoHide.instance.start();
  }
  runApp(const HomeShellApp());
}

class HomeShellApp extends StatelessWidget {
  const HomeShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Shell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3B5BDB),
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
      ),
      home: const HomeScreen(),
    );
  }
}
