import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/game_library_service.dart';
import '../../services/igdb_service.dart';
import 'game_details_screen.dart';
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
    unawaited(IgdbService.instance.load().then((_) {
      if (mounted) setState(() {});
    }));
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

  Map<String, LibraryGame> get _ownedMap => {for (final g in _games) normGameName(g.name): g};

  Future<void> _details(LibraryGame g) async {
    if (!IgdbService.instance.configured) {
      await _setupKeys();
      return;
    }
    setState(() => _message = 'Looking up ${g.name}...');
    final match = await IgdbService.instance.quick(g.name);
    if (!mounted) return;
    setState(() => _message = null);
    if (match == null) {
      setState(() => _message = 'No game info found for ${g.name}.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GameDetailsScreen(igdbId: match.id, owned: _ownedMap),
    ));
  }

  Future<void> _find() async {
    if (!IgdbService.instance.configured) {
      await _setupKeys();
      if (!IgdbService.instance.configured) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GameFinderScreen(owned: _ownedMap),
    ));
  }

  Future<void> _setupKeys() async {
    final id = TextEditingController(text: IgdbService.instance.clientId);
    final secret = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Game info (IGDB) — one-time setup'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  '1. Go to dev.twitch.tv/console and sign in (turn on two-factor sign-in on your Twitch account if asked).\n'
                  '2. Register Your Application: any name, OAuth Redirect URL http://localhost , Category: Application Integration, Client Type: Confidential.\n'
                  '3. Open the app, copy the Client ID, click New Secret and copy the Client Secret.\n'
                  'The keys stay on this PC and are used only to ask IGDB for game info.',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 14),
                TvTextField(controller: id, labelText: 'Client ID'),
                const SizedBox(height: 10),
                TvTextField(controller: secret, labelText: 'Client Secret'),
                if (result != null) Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(result!, style: const TextStyle(color: Color(0xFFFFC857))),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton(
              onPressed: () async {
                await IgdbService.instance.saveKeys(id.text, secret.text);
                final err = await IgdbService.instance.test();
                if (err == null) {
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setD(() => result = err);
                }
              },
              child: const Text('Save and test'),
            ),
          ],
        ),
      ),
    );
    id.dispose();
    secret.dispose();
    if (mounted) setState(() {});
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
                      const SizedBox(width: 16),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(spacing: 10, runSpacing: 8, children: [
                            OutlinedButton.icon(
                              onPressed: _find,
                              icon: const Icon(Icons.travel_explore_rounded),
                              label: const Text('Find games'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _setupKeys,
                              icon: const Icon(Icons.key_rounded),
                              label: Text(IgdbService.instance.configured ? 'Game info: on' : 'Game info setup'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Refresh'),
                            ),
                            FilledButton.icon(
                              focusNode: _addFocus,
                              onPressed: _add,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add a game'),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                    if (_message != null) ...[
                      const SizedBox(height: 8),
                      Text(_message!, style: const TextStyle(color: Color(0xFFFFC857), fontSize: 14)),
                    ],
                    const SizedBox(height: 6),
                    const Text('A play   ·   Y details & series   ·   X remove (games you added)',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 10),
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
    final showHero = _filter == 'All' && _query.text.trim().isEmpty;
    final hero = [..._games]..sort((a, b) {
        final c = b.lastPlayed.compareTo(a.lastPlayed);
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return CustomScrollView(slivers: [
      if (showHero && hero.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: SizedBox(
              height: 230,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final g in hero.take(8))
                  _HeroCard(game: g, onPlay: () => _play(g), onDetails: () => _details(g)),
              ]),
            ),
          ),
        ),
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _GameCard(
            key: ValueKey(list[i].id),
            game: list[i],
            onPlay: () => _play(list[i]),
            onOptions: () => _remove(list[i]),
            onDetails: () => _details(list[i]),
          ),
          childCount: list.length,
        ),
      ),
    ]);
  }
}

/// Big wide card (like the "Popular Movies" row): picture, title and a short
/// description when game info is set up.
class _HeroCard extends StatefulWidget {
  const _HeroCard({required this.game, required this.onPlay, required this.onDetails});
  final LibraryGame game;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _focused = false;
  IgdbGame? _info;

  @override
  void initState() {
    super.initState();
    if (IgdbService.instance.configured) {
      IgdbService.instance.quick(widget.game.name).then((v) {
        if (mounted) setState(() => _info = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final pic = _info?.wide() ?? g.fallbackCoverUrl ?? g.coverUrl;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Focus(
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 120), alignment: 0.5);
        },
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.gameButtonA) {
            widget.onPlay();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.f3 || k == LogicalKeyboardKey.gameButtonY) {
            widget.onDetails();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onPlay,
          onSecondaryTap: widget.onDetails,
          child: AnimatedScale(
            scale: _focused ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: Container(
              width: 440,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
                color: const Color(0xFF1B2133),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (pic != null) Image.network(pic, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE6000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      _info?.summary ?? (g.lastPlayed > 0 ? 'Played recently — press A to continue' : g.source),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.3, color: Colors.white70),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatefulWidget {
  const _GameCard({super.key, required this.game, required this.onPlay, required this.onOptions, required this.onDetails});
  final LibraryGame game;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final VoidCallback onDetails;

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
        if (k == LogicalKeyboardKey.f3 || k == LogicalKeyboardKey.gameButtonY) {
          widget.onDetails();
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
