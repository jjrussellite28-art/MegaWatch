import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One neighbour in a franchise: the title to watch before / after.
class WatchOrderEntry {
  const WatchOrderEntry({
    required this.title,
    this.detail,
    this.type,
    this.id,
  });

  /// "John Wick: Chapter 2 (2017)".
  final String title;

  /// Quiet second line, e.g. "122 min · ★ 7.3".
  final String? detail;

  /// 'movie' or 'series' when the entry can be opened.
  final String? type;

  /// IMDb id when the entry can be opened.
  final String? id;

  bool get canOpen => type != null && id != null && id!.startsWith('tt');
}

/// Where one title sits in its universe.
class WatchOrderInfo {
  const WatchOrderInfo({
    this.position,
    this.universe,
    this.before,
    this.next,
    this.timelineId,
    this.timelineLabel,
  });

  /// "Story 2 of 6 · Release 1 of 6".
  final String? position;
  final String? universe;
  final WatchOrderEntry? before;
  final WatchOrderEntry? next;

  /// Id of the full timeline (opened with [WatchOrderService.timeline]).
  final String? timelineId;
  final String? timelineLabel;

  bool get isEmpty =>
      before == null && next == null && timelineId == null && position == null;
}

/// One line of a full universe timeline.
class WatchOrderTimelineItem {
  const WatchOrderTimelineItem({
    required this.title,
    this.year,
    this.type,
    this.id,
  });
  final String title;
  final String? year;
  final String? type;
  final String? id;
  bool get canOpen => type != null && id != null && id!.startsWith('tt');
}

/// Franchise watch order, read from the public "Watch Order" Stremio add-on
/// made by u/demon-myth (https://www.reddit.com/user/demon-myth/). Debrify only
/// asks it questions; none of its code or data is bundled here, and the
/// feature can be switched off in Settings › Metadata.
class WatchOrderService {
  WatchOrderService._();
  static final instance = WatchOrderService._();

  static const baseUrl = 'https://099757617587-watch-order.baby-beamup.club';
  static const _prefKey = 'watch_order_enabled';
  static const _ttl = Duration(hours: 6);
  static const _timeout = Duration(seconds: 8);

  final _cache = <String, ({DateTime at, WatchOrderInfo? info})>{};

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  /// Null when the title is in no universe, the feature is off, or the add-on
  /// can't be reached right now. Never throws.
  Future<WatchOrderInfo?> forTitle(String type, String imdbId) async {
    if (!imdbId.startsWith('tt')) return null;
    if (type != 'movie' && type != 'series') return null;
    if (!await isEnabled()) return null;
    final key = '$type/$imdbId';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return hit.info;
    }
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/stream/$type/$imdbId.json'))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final info = _parse(jsonDecode(res.body));
      if (_cache.length > 64) _cache.remove(_cache.keys.first);
      _cache[key] = (at: DateTime.now(), info: info);
      return info;
    } catch (_) {
      return null;
    }
  }

  final Map<String, String> _typeCache = {};

  /// The timeline lists films and episodes alike, so ask Cinemeta which one
  /// an IMDb id really is. Falls back to [guess] when it can't be reached.
  Future<String> resolveType(String imdbId, String? guess) async {
    final cached = _typeCache[imdbId];
    if (cached != null) return cached;
    try {
      final res = await http
          .get(Uri.parse('https://v3-cinemeta.strem.io/meta/movie/$imdbId.json'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final meta = (jsonDecode(res.body) as Map?)?['meta'];
        final isMovie = meta is Map && (meta['name'] ?? '').toString().isNotEmpty;
        return _typeCache[imdbId] = isMovie ? 'movie' : 'series';
      }
      if (res.statusCode == 404) return _typeCache[imdbId] = 'series';
    } catch (_) {}
    return guess ?? 'movie';
  }

  /// The full timeline for a universe id such as "wo:john-wick".
  Future<List<WatchOrderTimelineItem>> timeline(String universeId) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/meta/series/$universeId.json'))
          .timeout(_timeout);
      if (res.statusCode != 200) return const [];
      final meta = (jsonDecode(res.body) as Map?)?['meta'];
      final videos = meta is Map ? meta['videos'] : null;
      if (videos is! List) return const [];
      final out = <WatchOrderTimelineItem>[];
      for (final v in videos) {
        if (v is! Map) continue;
        final title = (v['title'] ?? v['name'])?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        final rawId = v['id']?.toString() ?? '';
        final imdb = RegExp(r'tt\d+').firstMatch(rawId)?.group(0);
        final released = v['released']?.toString() ?? '';
        out.add(
          WatchOrderTimelineItem(
            title: title,
            year: released.length >= 4 ? released.substring(0, 4) : null,
            // Episodes carry a season; a plain id is a film.
            type: imdb == null
                ? null
                : (v['season'] != null || rawId.contains(':') ? 'series' : 'movie'),
            id: imdb,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static WatchOrderInfo? _parse(Object? body) {
    final streams = body is Map ? body['streams'] : null;
    if (streams is! List || streams.isEmpty) return null;
    String? position, universe, timelineId, timelineLabel;
    WatchOrderEntry? before, next;
    for (final s in streams) {
      if (s is! Map) continue;
      final lines = (s['description'] ?? s['title'] ?? '')
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;
      final head = lines.first.toLowerCase();
      final url = s['externalUrl']?.toString() ?? '';
      final m = RegExp(r'detail/(movie|series)/([^/?#]+)').firstMatch(url);
      final type = m?.group(1);
      final id = m?.group(2);
      if (head.contains('you are here')) {
        if (lines.length > 1) position = lines[1];
        if (lines.length > 2) universe = lines[2];
      } else if (head.contains('watch before') || head.contains('watch next')) {
        if (lines.length < 2) continue;
        final parts = lines[1].split(' · ');
        final entry = WatchOrderEntry(
          title: parts.first,
          detail: parts.length > 1 ? parts.sublist(1).join(' · ') : null,
          type: type,
          id: id,
        );
        if (head.contains('before')) {
          before ??= entry;
        } else {
          next ??= entry;
        }
      } else if (head.contains('timeline')) {
        if (id != null && id.startsWith('wo:') && timelineId == null) {
          timelineId = id;
          final label = lines.first.split(':');
          timelineLabel = label.length > 1
              ? label.sublist(1).join(':').trim()
              : universe;
        }
      }
    }
    final info = WatchOrderInfo(
      position: position,
      universe: universe,
      before: before,
      next: next,
      timelineId: timelineId,
      timelineLabel: timelineLabel,
    );
    return info.isEmpty ? null : info;
  }
}
