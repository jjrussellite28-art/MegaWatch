import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/game_library_service.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/tv_text_field.dart';

/// The Games tab: everything installed through Steam and Epic, plus programs
/// you add yourself, in one controller-friendly grid. A starts a game; X (or
/// right-click / long-press) removes one you added by hand.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _addFocus = FocusNode(debugLabel: 'games-add');
  late final VoidCallback _contentFocus;

  bool _loading = true;
  String? _message;
  List<LibraryGame> _games = const [];
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _contentFocus = () {
      if (mounted) _addFocus.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(20, _contentFocus);
    _query.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(20, _contentFocus);
    _addFocus.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final games = await GameLibraryService.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _games = games;
      _loading = false;
    });
  }

  List<LibraryGame> get _shown {
    final q = _query.text.trim().toLowerCase();
    var list = _games.where((g) {
      if (_filter == 'Recent') return g.lastPlayed > 0;
      if (_filter != 'All' && g.source != _filter) return false;
      return true;
    }).toList();
    if (q.isNotEmpty) {
      list = list.where((g) => g.name.toLowerCase().contains(q)).toList();
    }
    if (_filter == 'Recent') {
      list.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    } else {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  Future<void> _play(LibraryGame g) async {
    final err = await GameLibraryService.instance.play(g);
    if (!mounted) return;
    setState(() => _message = err);
  }

  Future<void> _remove(LibraryGame g) async {
    if (!g.custom) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${g.name}?'),
        content: const Text('This only removes it from this list. The game itself is not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await GameLibraryService.instance.removeCustom(g);
    await _load();
  }

  Future<void> _add() async {
    final added = await showDialog<bool>(context: context, builder: (_) => const _AddGameDialog());
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(88, 20, 32, 16),
          child: !GameLibraryService.supported
              ? const Center(
                  child: Text('Games are available in the Windows app.',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Games',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Refresh'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        focusNode: _addFocus,
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add a game'),
                      ),
                    ]),
                    if (_message != null) ...[
                      const SizedBox(height: 8),
                      Text(_message!, style: const TextStyle(color: Color(0xFFFFC857), fontSize: 14)),
                    ],
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in const ['All', 'Recent', 'Steam', 'Epic', 'My games'])
                        ChoiceChip(
                          label: Text(f),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    TvTextField(
                      controller: _query,
                      hintText: 'Search your games',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _grid()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _grid() {
    final list = _shown;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _games.isEmpty
                ? 'No games found yet. Install games with Steam or Epic, or press "Add a game" to add any program.'
                : 'Nothing matches.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
          ),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _GameCard(
        key: ValueKey(list[i].id),
        game: list[i],
        onPlay: () => _play(list[i]),
        onOptions: () => _remove(list[i]),
      ),
    );
  }
}

class _GameCard extends StatefulWidget {
  const _GameCard({super.key, required this.game, required this.onPlay, required this.onOptions});
  final LibraryGame game;
  final VoidCallback onPlay;
  final VoidCallback onOptions;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _focused = false;
  bool _hover = false;
  bool _useFallback = false;

  Widget _initials() {
    final g = widget.game;
    final hue = (g.name.hashCode % 360).abs().toDouble();
    return Container(
      color: HSLColor.fromAHSL(1, hue, 0.4, 0.28).toColor(),
      alignment: Alignment.center,
      child: Text(
        g.name.isEmpty ? '?' : g.name.trim()[0].toUpperCase(),
        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.white70),
      ),
    );
  }

  Widget _cover() {
    final g = widget.game;
    final url = _useFallback ? g.fallbackCoverUrl : g.coverUrl;
    if (url == null) return _initials();
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 400,
      errorBuilder: (_, __, ___) {
        if (!_useFallback && g.fallbackCoverUrl != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useFallback = true);
          });
        }
        return _initials();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final active = _focused || _hover;
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 120), alignment: 0.5);
        }
      },
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.gameButtonA) {
          widget.onPlay();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.contextMenu ||
            k == LogicalKeyboardKey.gameButtonX ||
            k == LogicalKeyboardKey.f2) {
          widget.onOptions();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          onSecondaryTap: widget.onOptions,
          onLongPress: widget.onOptions,
          child: AnimatedScale(
            scale: active ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                _cover(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xDD000000)],
                      ),
                    ),
                    child: Text(g.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text(g.source, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Add a game: pick a program from the Start menu, or type a path.
class _AddGameDialog extends StatefulWidget {
  const _AddGameDialog();

  @override
  State<_AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends State<_AddGameDialog> {
  List<MapEntry<String, String>> _apps = const [];
  bool _loading = true;
  bool _manual = false;
  final _name = TextEditingController();
  final _path = TextEditingController();

  @override
  void initState() {
    super.initState();
    GameLibraryService.instance.installedApps().then((a) {
      if (mounted) {
        setState(() {
          _apps = a;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _addApp(String name, String path) async {
    await GameLibraryService.instance.addCustom(name: name, exe: path);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 620,
        height: 540,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _manual ? _manualForm() : _picker(),
        ),
      ),
    );
  }

  Widget _picker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add a game', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ListTile(
          autofocus: true,
          leading: const Icon(Icons.keyboard_rounded),
          title: const Text('Type a path to the game (.exe)'),
          onTap: () => setState(() => _manual = true),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _apps.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.apps_rounded),
                    title: Text(_apps[i].key),
                    onTap: () => _addApp(_apps[i].key, _apps[i].value),
                  ),
                ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ),
      ],
    );
  }

  Widget _manualForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add a game', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TvTextField(controller: _name, labelText: 'Name'),
        const SizedBox(height: 12),
        TvTextField(controller: _path, labelText: r'Full path (example: C:\Games\MyGame\game.exe)'),
        const Spacer(),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => setState(() => _manual = false), child: const Text('Back')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              final p = _path.text.trim();
              if (p.isEmpty) return;
              final n = _name.text.trim().isEmpty ? p.split('\\').last.replaceAll(RegExp(r'\.\w+$'), '') : _name.text.trim();
              if (!File(p).existsSync()) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That file was not found.')));
                return;
              }
              _addApp(n, p);
            },
            child: const Text('Add'),
          ),
        ]),
      ],
    );
  }
}
