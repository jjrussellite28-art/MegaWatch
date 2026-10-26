import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'cursor_hide.dart';
import 'gamepad.dart';
import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Home Shell',
        backgroundColor: Colors.black,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.setFullScreen(true);
        await windowManager.show();
        await windowManager.focus();
      },
    );
    WindowsGamepadService.instance.onGuideClosedApp = () async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
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
