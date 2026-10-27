import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

/// Plays a YouTube video in YouTube's own player inside an in-app browser.
/// Used when the normal loader is stopped by YouTube's "confirm you're not a
/// bot" check. Windows only (needs the Edge WebView2 runtime).
class YoutubeWebFallbackPage extends StatefulWidget {
  const YoutubeWebFallbackPage({
    super.key,
    required this.videoId,
    this.title,
  });

  final String videoId;
  final String? title;

  static bool get supported => Platform.isWindows;

  static Future<void> open(
    BuildContext context,
    String videoId, {
    String? title,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YoutubeWebFallbackPage(videoId: videoId, title: title),
      ),
    );
  }

  @override
  State<YoutubeWebFallbackPage> createState() => _YoutubeWebFallbackPageState();
}

class _YoutubeWebFallbackPageState extends State<YoutubeWebFallbackPage> {
  static bool _envReady = false;
  final WebviewController _c = WebviewController();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!_envReady) {
        try {
          final dir = await getApplicationSupportDirectory();
          await WebviewController.initializeEnvironment(
            userDataPath: '${dir.path}\\streaming_webview',
          );
        } catch (_) {
          // Already initialised by the Streaming tab.
        }
        _envReady = true;
      }
      await _c.initialize();
      await _c.setBackgroundColor(Colors.black);
      await _c.loadUrl(
        'https://www.youtube.com/watch?v=${Uri.encodeComponent(widget.videoId)}',
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not start the browser view ($e). It needs the Microsoft '
              'Edge WebView2 Runtime (already on Windows 11).',
        );
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title ?? 'YouTube'),
        backgroundColor: Colors.black87,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : Webview(_c),
    );
  }
}
