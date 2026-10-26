import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../services/main_page_bridge.dart';
import '../../widgets/tv_text_field.dart';

class _Service {
  const _Service(this.name, this.url, {this.color = 0xFF2B3550, this.userAgent, this.custom = false});
  final String name;
  final String url;
  final int color;
  final String? userAgent;
  final bool custom;
}

// YouTube's TV site is made for controllers and signs in with a short code
// (enter it at youtube.com/activate), which avoids Google blocking sign-in
// inside embedded browsers.
const _tvAgent =
    'Mozilla/5.0 (PlayStation; PlayStation 5/2.26) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0 Safari/605.1.15';

const _defaults = <_Service>[
  _Service('YouTube', 'https://www.youtube.com/tv', color: 0xFFB3261E, userAgent: _tvAgent),
  _Service('Peacock', 'https://www.peacocktv.com', color: 0xFF1F1F1F),
  _Service('Netflix', 'https://www.netflix.com', color: 0xFF8E0F14),
  _Service('Max', 'https://play.max.com', color: 0xFF3B2A8F),
  _Service('Disney+', 'https://www.disneyplus.com', color: 0xFF0D3B8E),
  _Service('Prime Video', 'https://www.primevideo.com', color: 0xFF0B5E8E),
  _Service('Hulu', 'https://www.hulu.com', color: 0xFF1B7F4A),
  _Service('Paramount+', 'https://www.paramountplus.com', color: 0xFF1A4BD6),
  _Service('Apple TV', 'https://tv.apple.com', color: 0xFF333333),
  _Service('Twitch', 'https://www.twitch.tv', color: 0xFF6B3FD1),
];

/// The Streaming tab: your own subscriptions (YouTube, Peacock, Netflix...)
/// opened in an embedded browser, signed in with YOUR accounts. Their video is
/// protected, so it plays on their page, not in Debrify's own player. Press Y
/// (or F3) to go back to this list.
class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key, this.isTelevision = false});
  final bool isTelevision;

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  static const _prefKey = 'streaming_custom_v1';
  final FocusNode _firstFocus = FocusNode(debugLabel: 'streaming-first');
  late final VoidCallback _contentFocus;
  List<_Service> _custom = const [];
  _Service? _open;

  @override
  void initState() {
    super.initState();
    _contentFocus = () {
      if (mounted) _firstFocus.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(22, _contentFocus);
    _loadCustom();
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(22, _contentFocus);
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCustom() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => _Service(e['name'] as String, e['url'] as String, custom: true))
          .toList();
      if (mounted) setState(() => _custom = list);
    } catch (_) {}
  }

  Future<void> _saveCustom() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _prefKey,
        jsonEncode([for (final s in _custom) {'name': s.name, 'url': s.url}]),
      );
    } catch (_) {}
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController(text: 'https://');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a streaming site'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TvTextField(controller: name, labelText: 'Name'),
            const SizedBox(height: 12),
            TvTextField(controller: url, labelText: 'Web address (https://...)'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    var u = url.text.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    final n = name.text.trim().isEmpty ? Uri.tryParse(u)?.host ?? u : name.text.trim();
    setState(() => _custom = [..._custom, _Service(n, u, custom: true)]);
    await _saveCustom();
  }

  Future<void> _remove(_Service s) async {
    if (!s.custom) return;
    setState(() => _custom = _custom.where((e) => e.url != s.url || e.name != s.name).toList());
    await _saveCustom();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return const Center(
        child: Text('Streaming is available in the Windows app.',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      );
    }
    final open = _open;
    if (open != null) {
      return _Viewer(service: open, onExit: () => setState(() => _open = null));
    }
    final all = [..._defaults, ..._custom];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(88, 20, 32, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Streaming',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add a site'),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Sign in with your own accounts. Video plays on the service\'s own page. Press Y to come back here.',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 16 / 10,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: all.length,
                itemBuilder: (_, i) => _Tile(
                  service: all[i],
                  focusNode: i == 0 ? _firstFocus : null,
                  onOpen: () => setState(() => _open = all[i]),
                  onRemove: () => _remove(all[i]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.service, required this.onOpen, required this.onRemove, this.focusNode});
  final _Service service;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final FocusNode? focusNode;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final active = _focused || _hover;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 120), alignment: 0.5);
      },
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.select) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.f2 || k == LogicalKeyboardKey.contextMenu) {
          widget.onRemove();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          onSecondaryTap: widget.onRemove,
          child: AnimatedScale(
            scale: active ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(s.color),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
              ),
              child: Text(s.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.service, required this.onExit});
  final _Service service;
  final VoidCallback onExit;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  static bool _envReady = false;
  final WebviewController _c = WebviewController();
  bool _ready = false;
  String? _error;
  bool _hint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _hintTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _hint = false);
    });
    _start();
  }

  // Y / F3 leaves the page, even while the page itself has the keyboard.
  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f3) {
      widget.onExit();
      return true;
    }
    return false;
  }

  Future<void> _start() async {
    try {
      if (!_envReady) {
        final dir = await getApplicationSupportDirectory();
        await WebviewController.initializeEnvironment(userDataPath: '${dir.path}\\streaming_webview');
        _envReady = true;
      }
      await _c.initialize();
      await _c.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      final ua = widget.service.userAgent;
      if (ua != null) await _c.setUserAgent(ua);
      await _c.setBackgroundColor(Colors.black);
      await _c.loadUrl(widget.service.url);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not start the browser view ($e). '
            'It needs the Microsoft Edge WebView2 Runtime (already on Windows 11).');
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hintTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: _error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              ))
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : Webview(_c),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: AnimatedOpacity(
          opacity: _hint || _error != null ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Material(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.onExit,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Y = back to Streaming list', style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
