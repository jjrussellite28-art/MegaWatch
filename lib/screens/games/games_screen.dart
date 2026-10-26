import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/main_page_bridge.dart';
import '../../services/playnite_service.dart';
import '../../services/playnite_switcher.dart';
import '../../widgets/tv_text_field.dart';

/// The Games tab: your Playnite library inside Debrify. Pick a game to start
/// it through Playnite, or open Playnite's own fullscreen mode.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode(debugLabel: 'games-query');

  final FocusNode _openFocus = FocusNode(debugLabel: 'games-open');
  late final VoidCallback _contentFocus;
  bool _loading = true;
  String? _message;
  List<PlayniteGame>? _games;

  @override
  void initState() {
    super.initState();
    _contentFocus = () {
      if (mounted) _openFocus.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(20, _contentFocus);
    _query.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(20, _contentFocus);
    _openFocus.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<PlayniteGame>? games;
    String? error;
    try {
      games = await PlayniteService.instance.loadGames();
    } catch (e) {
      error = 'Could not read the Playnite list ($e).';
    }
    if (!mounted) return;
    setState(() {
      _games = games;
      _message = error;
      _loading = false;
    });
  }

  Future<void> _installHelper() async {
    final error = await PlayniteService.instance.installHelper();
    if (!mounted) return;
    setState(() {
      _message = error ??
          'Helper installed. Now close Playnite completely and open it again '
          'once, then press Refresh here.';
    });
  }

  Future<void> _openPlaynite() async {
    final ok = await PlayniteSwitcher.instance.openPlaynite();
    if (!mounted) return;
    if (!ok) {
      setState(() => _message = 'Playnite was not found on this PC.');
    }
  }

  Future<void> _play(PlayniteGame game) async {
    try {
      await PlayniteService.instance.launch(game);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Could not start ${game.name} ($e).');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(88, 20, 32, 16),
          child: !PlayniteService.supported
              ? const Center(
                  child: Text(
                    'Games are available in the Windows app.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final games = _games;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Games',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              focusNode: _openFocus,
              onPressed: _openPlaynite,
              icon: const Icon(Icons.sports_esports_rounded),
              label: const Text('Open Playnite'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: const TextStyle(color: Color(0xFFFFC857), fontSize: 14),
          ),
        ],
        const SizedBox(height: 12),
        if (games == null)
          Expanded(child: _buildSetup())
        else ...[
          TvTextField(
            controller: _query,
            focusNode: _queryFocus,
            hintText: 'Search your games',
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildGrid(games)),
        ],
      ],
    );
  }

  Widget _buildSetup() {
    final installed = PlayniteService.instance.playniteInstalled;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_esports_rounded, size: 56, color: Colors.white70),
            const SizedBox(height: 14),
            Text(
              installed
                  ? 'Connect your Playnite library so your games show up here.'
                  : 'Playnite was not found. Install it from playnite.link, '
                        'then come back here.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.45, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            if (installed)
              FilledButton.icon(
                autofocus: true,
                onPressed: _installHelper,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connect Playnite'),
              ),
            const SizedBox(height: 10),
            const Text(
              'After connecting: close Playnite fully, open it once, then '
              'press Refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<PlayniteGame> games) {
    final q = _query.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? games
        : games.where((g) => g.name.toLowerCase().contains(q)).toList();
    if (shown.isEmpty) {
      return const Center(
        child: Text(
          'No games found.',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.66,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) => _GameCard(
        game: shown[i],
        onPlay: () => unawaited(_play(shown[i])),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.onPlay});

  final PlayniteGame game;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final cover = game.cover;
    final hasCover = cover != null && File(cover).existsSync();
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(12),
      focusColor: Colors.white.withValues(alpha: 0.22),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasCover
                  ? Image.file(
                      File(cover),
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            game.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: game.installed ? Colors.white : Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: Colors.white.withValues(alpha: 0.08),
    child: const Center(
      child: Icon(Icons.sports_esports_rounded, size: 40, color: Colors.white38),
    ),
  );
}
