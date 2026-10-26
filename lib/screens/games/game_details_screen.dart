import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/game_library_service.dart';
import '../../services/igdb_service.dart';
import '../../widgets/tv_text_field.dart';

String normGameName(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Closes the page on B / Escape (the controller sends Escape).
Widget _backOnEscape({required Widget child}) {
  return Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, e) {
      if (e is KeyDownEvent &&
          (e.logicalKey == LogicalKeyboardKey.escape ||
              e.logicalKey == LogicalKeyboardKey.goBack ||
              e.logicalKey == LogicalKeyboardKey.gameButtonB)) {
        Navigator.of(node.context!).maybePop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

/// A game's page: description, pictures, where to get it, and the rest of its
/// series ("Universe") so you can play in order or find the next one.
class GameDetailsScreen extends StatefulWidget {
  const GameDetailsScreen({super.key, required this.igdbId, this.owned = const {}});

  final int igdbId;

  /// Games in your library, by normalized name — shows Play instead of Get.
  final Map<String, LibraryGame> owned;

  @override
  State<GameDetailsScreen> createState() => _GameDetailsScreenState();
}

class _GameDetailsScreenState extends State<GameDetailsScreen> {
  IgdbGame? _game;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await IgdbService.instance.details(widget.igdbId);
      if (!mounted) return;
      setState(() {
        _game = g;
        _loading = false;
        if (g == null) _message = 'Could not load this game. Check your IGDB keys in the Games tab.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Could not load this game ($e).';
        });
      }
    }
  }

  void _open(IgdbGame g) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GameDetailsScreen(igdbId: g.id, owned: widget.owned),
    ));
  }

  Future<void> _store(IgdbGame g) async {
    final url = g.steamAppId != null ? 'steam://store/${g.steamAppId}' : g.storeUrl;
    if (url == null) {
      final q = Uri.encodeQueryComponent('${g.name} game');
      await launchUrl(Uri.parse('https://store.steampowered.com/search/?term=$q'),
          mode: LaunchMode.externalApplication);
      return;
    }
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && g.storeUrl != null) {
      await launchUrl(Uri.parse(g.storeUrl!), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _game;
    final bg = g?.wide('t_1080p');
    final owned = g == null ? null : widget.owned[normGameName(g.name)];
    return _backOnEscape(
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: Stack(fit: StackFit.expand, children: [
          if (bg != null)
            Opacity(opacity: 0.25, child: Image.network(bg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : g == null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_message ?? 'Not found.', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                          const SizedBox(height: 16),
                          FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Back')),
                        ]),
                      )
                    : _content(g, owned),
          ),
        ]),
      ),
    );
  }

  Widget _content(IgdbGame g, LibraryGame? owned) {
    final meta = [
      if (g.year != null) '${g.year}',
      if (g.genres.isNotEmpty) g.genres.take(3).join(' · '),
      if (g.rating != null) '★ ${(g.rating! / 10).toStringAsFixed(1)}',
    ].join('   ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(88, 16, 32, 32),
      children: [
        Row(children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (g.cover() != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(g.cover()!, width: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 200, height: 260)),
            ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 6),
              Text(meta, style: const TextStyle(fontSize: 15, color: Colors.white70)),
              const SizedBox(height: 14),
              if (g.summary != null)
                Text(g.summary!, maxLines: 7, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.white)),
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 10, children: [
                if (owned != null)
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () async {
                      final err = await GameLibraryService.instance.play(owned);
                      if (err != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                FilledButton.tonalIcon(
                  autofocus: owned == null,
                  onPressed: () => _store(g),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(owned != null ? 'Store page' : 'Get this game'),
                ),
              ]),
              if (owned != null)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('In your library', style: TextStyle(color: Color(0xFF7BE0A0))),
                ),
            ]),
          ),
        ]),
        if (g.universe.isNotEmpty) ...[
          const SizedBox(height: 32),
          const Text('Universe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          const Text('The rest of the series, in release order — play them in order or pick up where you left off.',
              style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 12),
          _row([
            for (final r in g.universe)
              _Poster(
                game: r.game,
                label: r.label,
                owned: widget.owned.containsKey(normGameName(r.game.name)),
                onOpen: () => _open(r.game),
              ),
          ]),
        ],
        if (g.screenshotIds.isNotEmpty) ...[
          const SizedBox(height: 32),
          const Text('Screenshots', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final id in g.screenshotIds.take(8))
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(g.screenshot(id)!, height: 170, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 300, height: 170)),
                  ),
                ),
            ]),
          ),
        ],
        if (g.similar.isNotEmpty) ...[
          const SizedBox(height: 32),
          const Text('Find similar games', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          _row([
            for (final s in g.similar)
              _Poster(
                game: s,
                label: 'SIMILAR',
                owned: widget.owned.containsKey(normGameName(s.name)),
                onOpen: () => _open(s),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _row(List<Widget> children) => SizedBox(
        height: 330,
        child: ListView(scrollDirection: Axis.horizontal, children: children),
      );
}

/// Poster with a small label, title and year (like picture 2).
class _Poster extends StatefulWidget {
  const _Poster({required this.game, required this.label, required this.onOpen, this.owned = false});
  final IgdbGame game;
  final String label;
  final bool owned;
  final VoidCallback onOpen;

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Focus(
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 120), alignment: 0.5);
        },
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.enter ||
                  e.logicalKey == LogicalKeyboardKey.numpadEnter ||
                  e.logicalKey == LogicalKeyboardKey.select)) {
            widget.onOpen();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onOpen,
          child: SizedBox(
            width: 170,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 164,
                    height: 218,
                    child: g.cover() == null
                        ? Container(color: const Color(0xFF232B3F), alignment: Alignment.center,
                            child: Text(g.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))
                        : Image.network(g.cover()!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF232B3F))),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(widget.owned ? '${widget.label} · OWNED' : widget.label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Colors.white54)),
              Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              if (g.year != null) Text('${g.year}', style: const TextStyle(fontSize: 13, color: Colors.white54)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Search IGDB for any game — to find the next one in a series or something new.
class GameFinderScreen extends StatefulWidget {
  const GameFinderScreen({super.key, this.owned = const {}});
  final Map<String, LibraryGame> owned;

  @override
  State<GameFinderScreen> createState() => _GameFinderScreenState();
}

class _GameFinderScreenState extends State<GameFinderScreen> {
  final _q = TextEditingController();
  List<IgdbGame> _results = const [];
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _q.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final list = await IgdbService.instance.search(text);
      if (!mounted) return;
      setState(() {
        _results = list;
        _busy = false;
        if (list.isEmpty) _message = 'No games found.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Search failed ($e).';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _backOnEscape(
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(88, 16, 32, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                const SizedBox(width: 12),
                const Text('Find games', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
              const SizedBox(height: 12),
              TvTextField(
                controller: _q,
                autofocus: true,
                hintText: 'Search any game, series or franchise',
                prefixIcon: const Icon(Icons.search_rounded),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(onPressed: _busy ? null : _search, child: const Text('Search')),
                const SizedBox(width: 12),
                if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                if (_message != null) Text(_message!, style: const TextStyle(color: Colors.white70)),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.52,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (_, i) => _Poster(
                    game: _results[i],
                    label: _results[i].genres.isNotEmpty ? _results[i].genres.first.toUpperCase() : 'GAME',
                    owned: widget.owned.containsKey(normGameName(_results[i].name)),
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => GameDetailsScreen(igdbId: _results[i].id, owned: widget.owned),
                    )),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
