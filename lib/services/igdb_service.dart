import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A game as IGDB describes it.
class IgdbGame {
  IgdbGame({
    required this.id,
    required this.name,
    this.summary,
    this.coverId,
    this.year,
    this.releaseTs,
    this.rating,
    this.screenshotIds = const [],
    this.artworkIds = const [],
    this.genres = const [],
    this.platforms = const [],
    this.steamAppId,
    this.storeUrl,
    this.universe = const [],
    this.similar = const [],
  });

  final int id;
  final String name;
  final String? summary;
  final String? coverId;
  final int? year;
  final int? releaseTs;
  final double? rating;
  final List<String> screenshotIds;
  final List<String> artworkIds;
  final List<String> genres;
  final List<String> platforms;
  final String? steamAppId;
  final String? storeUrl;

  /// The rest of the series / franchise, remakes, DLC (the "Universe" row).
  final List<IgdbRelation> universe;
  final List<IgdbGame> similar;

  static const _base = 'https://images.igdb.com/igdb/image/upload';
  String? cover([String size = 't_cover_big']) =>
      coverId == null ? null : '$_base/$size/$coverId.jpg';
  String? screenshot(String imageId, [String size = 't_screenshot_big']) => '$_base/$size/$imageId.jpg';

  /// Wide picture for big cards (a screenshot or artwork).
  String? wide([String size = 't_screenshot_big']) {
    final id = screenshotIds.isNotEmpty
        ? screenshotIds.first
        : (artworkIds.isNotEmpty ? artworkIds.first : null);
    return id == null ? null : '$_base/$size/$id.jpg';
  }
}

class IgdbRelation {
  IgdbRelation(this.game, this.label);
  final IgdbGame game;

  /// FOLLOWED BY, PRECEDED BY, REMAKE, REMASTER, DLC, PART OF…
  final String label;
}

/// Game information from IGDB (free; needs a Twitch developer Client ID and
/// Secret, saved on this PC). Used for descriptions, pictures, and finding the
/// other games in a series.
class IgdbService {
  IgdbService._();
  static final IgdbService instance = IgdbService._();

  static const _idKey = 'igdb_client_id';
  static const _secretKey = 'igdb_client_secret';

  String _clientId = '';
  String _secret = '';
  String? _token;
  DateTime? _expires;
  bool _loaded = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, IgdbGame?> _quick = {};
  final Map<int, IgdbGame> _details = {};

  bool get configured => _clientId.isNotEmpty && _secret.isNotEmpty;
  String get clientId => _clientId;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _clientId = p.getString(_idKey) ?? '';
      _secret = p.getString(_secretKey) ?? '';
    } catch (_) {}
  }

  Future<void> saveKeys(String id, String secret) async {
    _clientId = id.trim();
    _secret = secret.trim();
    _token = null;
    _quick.clear();
    _details.clear();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_idKey, _clientId);
      await p.setString(_secretKey, _secret);
    } catch (_) {}
  }

  Future<String?> _auth() async {
    if (_token != null && _expires != null && DateTime.now().isBefore(_expires!)) return _token;
    final r = await http.post(Uri.parse('https://id.twitch.tv/oauth2/token'), body: {
      'client_id': _clientId,
      'client_secret': _secret,
      'grant_type': 'client_credentials',
    });
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    _token = j['access_token'] as String?;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _expires = DateTime.now().add(Duration(seconds: secs - 120));
    return _token;
  }

  /// IGDB allows about 4 requests a second.
  Future<void> _pace() async {
    final wait = _last.add(const Duration(milliseconds: 280)).difference(DateTime.now());
    _last = DateTime.now().add(wait.isNegative ? Duration.zero : wait);
    if (!wait.isNegative) await Future<void>.delayed(wait);
  }

  Future<List<dynamic>> _query(String endpoint, String body, {bool retry = true}) async {
    if (!configured) return const [];
    await _pace();
    final t = await _auth();
    if (t == null) return const [];
    final r = await http.post(
      Uri.parse('https://api.igdb.com/v4/$endpoint'),
      headers: {'Client-ID': _clientId, 'Authorization': 'Bearer $t', 'Accept': 'application/json'},
      body: body,
    );
    if (r.statusCode == 401 && retry) {
      _token = null;
      return _query(endpoint, body, retry: false);
    }
    if (r.statusCode != 200) return const [];
    final j = jsonDecode(r.body);
    return j is List ? j : const [];
  }

  /// Checks the saved keys. Returns null when OK, or a short message.
  Future<String?> test() async {
    if (!configured) return 'Enter the Client ID and Client Secret first.';
    try {
      _token = null;
      final t = await _auth();
      if (t == null) return 'Twitch did not accept these keys. Check them and try again.';
      return null;
    } catch (e) {
      return 'Could not reach Twitch ($e).';
    }
  }

  static String _esc(String s) => s.replaceAll('\\', ' ').replaceAll('"', ' ');

  static const _brief =
      'name,summary,first_release_date,total_rating,cover.image_id,screenshots.image_id,artworks.image_id,genres.name';

  Future<List<IgdbGame>> search(String q) async {
    final rows = await _query('games', 'search "${_esc(q)}"; fields $_brief; where version_parent = null; limit 24;');
    return [for (final m in rows) if (m is Map) _parse(m)];
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Best match for a game name (used for the big cards). Remembered per run.
  Future<IgdbGame?> quick(String name) async {
    if (!configured) return null;
    if (_quick.containsKey(name)) return _quick[name];
    IgdbGame? best;
    try {
      final list = await search(name);
      final n = _norm(name);
      for (final g in list) {
        if (_norm(g.name) == n) {
          best = g;
          break;
        }
      }
      best ??= list.isEmpty ? null : list.first;
    } catch (_) {}
    _quick[name] = best;
    return best;
  }

  Future<IgdbGame?> details(int id) async {
    final cached = _details[id];
    if (cached != null) return cached;
    const rel = 'name,first_release_date,cover.image_id';
    final rows = await _query(
      'games',
      'fields $_brief,platforms.name,websites.category,websites.url,'
      'collections.games.$rel,franchises.games.$rel,'
      'remakes.$rel,remasters.$rel,expansions.$rel,dlcs.$rel,parent_game.$rel,similar_games.$rel; '
      'where id = $id;',
    );
    if (rows.isEmpty || rows.first is! Map) return null;
    final m = rows.first as Map;
    final base = _parse(m);

    final found = <int, IgdbRelation>{};
    void add(dynamic list, String? forced) {
      if (list is! List) return;
      for (final g in list) {
        if (g is! Map || g['id'] is! int || g['id'] == id) continue;
        final other = _parse(g);
        final label = forced ?? _order(base.releaseTs, other.releaseTs);
        found.putIfAbsent(g['id'] as int, () => IgdbRelation(other, label));
      }
    }

    add(m['remakes'], 'REMAKE');
    add(m['remasters'], 'REMASTER');
    add(m['expansions'], 'EXPANSION');
    add(m['dlcs'], 'DLC');
    if (m['parent_game'] is Map) add([m['parent_game']], 'PART OF');
    for (final key in ['collections', 'franchises']) {
      final list = m[key];
      if (list is List) {
        for (final c in list) {
          if (c is Map) add(c['games'], null);
        }
      }
    }
    final universe = found.values.toList()
      ..sort((a, b) => (a.game.releaseTs ?? 1 << 40).compareTo(b.game.releaseTs ?? 1 << 40));

    final similar = <IgdbGame>[];
    final sim = m['similar_games'];
    if (sim is List) {
      for (final g in sim) {
        if (g is Map) similar.add(_parse(g));
      }
    }

    String? steamApp;
    String? store;
    final sites = m['websites'];
    if (sites is List) {
      for (final w in sites) {
        if (w is Map && w['category'] == 13 && w['url'] is String) {
          store = w['url'] as String;
          steamApp = RegExp(r'/app/(\d+)').firstMatch(store)?.group(1);
        }
      }
    }
    final full = IgdbGame(
      id: base.id,
      name: base.name,
      summary: base.summary,
      coverId: base.coverId,
      year: base.year,
      releaseTs: base.releaseTs,
      rating: base.rating,
      screenshotIds: base.screenshotIds,
      artworkIds: base.artworkIds,
      genres: base.genres,
      platforms: _names(m['platforms']),
      steamAppId: steamApp,
      storeUrl: store,
      universe: universe,
      similar: similar,
    );
    _details[id] = full;
    return full;
  }

  static String _order(int? mine, int? other) {
    if (mine == null || other == null) return 'SAME SERIES';
    if (other > mine) return 'FOLLOWED BY';
    if (other < mine) return 'PRECEDED BY';
    return 'SAME SERIES';
  }

  static List<String> _names(dynamic v) =>
      v is List ? [for (final e in v) if (e is Map && e['name'] is String) e['name'] as String] : const [];

  static List<String> _imageIds(dynamic v) => v is List
      ? [for (final e in v) if (e is Map && e['image_id'] is String) e['image_id'] as String]
      : const [];

  static IgdbGame _parse(Map m) {
    final ts = (m['first_release_date'] as num?)?.toInt();
    return IgdbGame(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: (m['name'] as String?) ?? '',
      summary: m['summary'] as String?,
      coverId: m['cover'] is Map ? (m['cover'] as Map)['image_id'] as String? : null,
      year: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).year,
      releaseTs: ts,
      rating: (m['total_rating'] as num?)?.toDouble(),
      screenshotIds: _imageIds(m['screenshots']),
      artworkIds: _imageIds(m['artworks']),
      genres: _names(m['genres']),
    );
  }
}
