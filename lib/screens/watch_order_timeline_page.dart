import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/stremio_addon.dart';
import '../services/storage_service.dart';
import '../services/watch_order_service.dart';
import '../services/watched_status_service.dart';

/// The whole universe in order, as the "Watch Order" add-on (u/demon-myth)
/// lists it. Tap a line to open that title. The page remembers the last line
/// you opened so you can pick up where you left off, shows a tick on titles
/// you have finished, and can add the whole universe to My Watchlist.
class WatchOrderTimelinePage extends StatefulWidget {
  const WatchOrderTimelinePage({
    super.key,
    required this.universeId,
    required this.title,
    required this.onOpen,
  });

  final String universeId;
  final String title;
  final void Function(WatchOrderTimelineItem item) onOpen;

  @override
  State<WatchOrderTimelinePage> createState() => _WatchOrderTimelinePageState();
}

class _WatchOrderTimelinePageState extends State<WatchOrderTimelinePage> {
  static const double _rowHeight = 76;
  late Future<List<WatchOrderTimelineItem>> _items;
  final ScrollController _scroll = ScrollController();
  int? _lastOpened;
  bool _jumped = false;
  bool _adding = false;

  String get _prefKey => 'watch_order_last_${widget.universeId}';

  @override
  void initState() {
    super.initState();
    _items = WatchOrderService.instance.timeline(widget.universeId);
    _loadLast();
    WatchedStatusService.instance.addListener(_onWatched);
  }

  @override
  void dispose() {
    WatchedStatusService.instance.removeListener(_onWatched);
    _scroll.dispose();
    super.dispose();
  }

  void _onWatched() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_prefKey);
      if (mounted && v != null) setState(() => _lastOpened = v);
    } catch (_) {}
  }

  Future<void> _saveLast(int index) async {
    setState(() => _lastOpened = index);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, index);
    } catch (_) {}
  }

  bool _watched(WatchOrderTimelineItem item) {
    if (!item.canOpen) return false;
    try {
      return WatchedStatusService.instance.isWatched(item.id!, item.type!);
    } catch (_) {
      return false;
    }
  }

  void _jumpToLast(int count) {
    if (_jumped || _lastOpened == null || !_scroll.hasClients) return;
    _jumped = true;
    final target = ((_lastOpened! - 1) * _rowHeight).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
  }

  Future<void> _addAll(List<WatchOrderTimelineItem> items) async {
    if (_adding) return;
    setState(() => _adding = true);
    var added = 0;
    try {
      // Each title once (seasons of one show share an id), and in reverse so
      // the first title ends up on top of My Watchlist.
      final seen = <String>{};
      final unique = <WatchOrderTimelineItem>[
        for (final i in items)
          if (i.canOpen && seen.add('${i.type}:${i.id}')) i,
      ];
      for (final i in unique.reversed) {
        final meta = StremioMeta(
          id: i.id!,
          imdbId: i.id,
          type: i.type!,
          name: i.title.split(' — ').first,
          year: i.year,
        );
        try {
          await StorageService.setMyWatchlistItem(meta, true);
          added++;
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        setState(() => _adding = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                added == 0
                    ? 'Could not add to My Watchlist'
                    : 'Added $added titles to My Watchlist',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WatchOrderTimelineItem>>(
      future: _items,
      builder: (context, snap) {
        final items = snap.data ?? const <WatchOrderTimelineItem>[];
        final done = snap.connectionState == ConnectionState.done;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              if (items.isNotEmpty)
                TextButton.icon(
                  onPressed: _adding ? null : () => _addAll(items),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(_adding ? 'Adding…' : 'Add all to My Watchlist'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: !done
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? const Center(child: Text('Could not load the timeline.'))
              : Builder(
                  builder: (context) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _jumpToLast(items.length),
                    );
                    final watchedCount = items.where(_watched).length;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: Row(
                            children: [
                              Text(
                                '${items.length} in order · $watchedCount finished',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemExtent: _rowHeight,
                            itemCount: items.length + 1,
                            itemBuilder: (context, i) {
                              if (i == items.length) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Watch order data: the Watch Order add-on by u/demon-myth.',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }
                              final item = items[i];
                              final watched = _watched(item);
                              final last = _lastOpened == i;
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 14,
                                  child: watched
                                      ? const Icon(Icons.check, size: 16)
                                      : Text('${i + 1}'),
                                ),
                                title: Text(item.title),
                                subtitle: Text(
                                  [
                                    if (item.year != null) item.year!,
                                    if (item.type != null)
                                      item.type == 'movie' ? 'Movie' : 'Show',
                                    if (last) 'You left off here',
                                  ].join(' · '),
                                  style: TextStyle(
                                    color: last ? Colors.amberAccent : null,
                                  ),
                                ),
                                tileColor: last
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : null,
                                onTap: item.canOpen
                                    ? () {
                                        _saveLast(i);
                                        widget.onOpen(item);
                                      }
                                    : null,
                                trailing: item.canOpen
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : null,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}
