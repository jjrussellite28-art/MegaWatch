import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController, TextEditingValue, TextSelection;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Result of probing one IPTV server.
class IptvServerHealth {
  const IptvServerHealth({
    required this.server,
    required this.online,
    this.latencyMs,
    this.error,
  });

  final String server;
  final bool online;
  final int? latencyMs;
  final String? error;

  /// "Fast", "OK", "Slow" or "Down".
  String get label {
    if (!online) return 'Down';
    final ms = latencyMs ?? 0;
    if (ms < 400) return 'Fast';
    if (ms < 1200) return 'OK';
    return 'Slow';
  }
}

/// Where a live channel URL points: which server, and the login inside it.
class IptvStreamAddress {
  const IptvStreamAddress({
    required this.primary,
    required this.server,
    required this.username,
    required this.password,
  });

  /// The server the channel list was built from (the playlist's own server).
  final String primary;

  /// The server currently being used (the primary, or one of its backups).
  final String server;
  final String username;
  final String password;
}

/// Backup ("mirror") servers for Xtream IPTV logins.
///
/// A playlist keeps its main server. Any backup servers are stored here, keyed
/// by that main server. Channel URLs in the catalog always name the main
/// server, so playback calls [rewrite] to swap in whichever server is active.
/// Switching servers therefore never touches the saved channel list.
class IptvMirrors {
  IptvMirrors._();
  static final IptvMirrors instance = IptvMirrors._();

  static const String _prefsKey = 'iptv_backup_servers_v1';

  final Map<String, List<String>> _backups = {};
  final Map<String, int> _active = {};
  bool _loaded = false;
  Future<void>? _loading;

  /// Bumps whenever the active server or the backup lists change.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _doLoad();
  }

  Future<void> _doLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) {
          data.forEach((key, value) {
            if (value is Map) {
              final list = value['backups'];
              if (list is List) {
                _backups[key.toString()] = [
                  for (final s in list)
                    if (s is String && s.isNotEmpty) s,
                ];
              }
              final active = value['active'];
              if (active is int) _active[key.toString()] = active;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('IptvMirrors: load failed: $e');
    }
    _loaded = true;
    changes.value++;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        for (final entry in _backups.entries)
          if (entry.value.isNotEmpty)
            entry.key: {
              'backups': entry.value,
              'active': _active[entry.key] ?? 0,
            },
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('IptvMirrors: save failed: $e');
    }
  }

  // ── Text helpers ────────────────────────────────────────────────────────

  /// Splits what the user typed in the server field into separate servers.
  /// Commas, semicolons, spaces and new lines all separate servers.
  static List<String> splitServerField(String raw) => [
    for (final part in raw.split(RegExp(r'[,;\s]+')))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// Makes a server box tidy itself: typing (or pasting) a comma moves to the
  /// next line, so every server sits on its own line. Works for the on-screen
  /// TV keyboard too, because it watches the controller, not key presses.
  static void keepOneServerPerLine(TextEditingController controller) {
    var busy = false;
    controller.addListener(() {
      if (busy) return;
      final value = controller.value;
      final text = value.text;
      if (!text.contains(',')) return;
      final cursor = value.selection.isValid
          ? value.selection.extentOffset
          : text.length;
      final buffer = StringBuffer();
      var newCursor = cursor;
      for (var i = 0; i < text.length; i++) {
        final ch = text[i];
        if (ch == ' ' && i > 0 && text[i - 1] == ',') {
          if (i < cursor) newCursor--; // drop the space after a comma
          continue;
        }
        buffer.write(ch);
        if (ch == ',' && !(i + 1 < text.length && text[i + 1] == '\n')) {
          buffer.write('\n');
          if (i + 1 <= cursor) newCursor++;
        }
      }
      final fixed = buffer.toString();
      if (fixed == text) return;
      busy = true;
      controller.value = TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(
          offset: newCursor.clamp(0, fixed.length),
        ),
      );
      busy = false;
    });
  }

  /// Same cleanup the playlist form applies to a single server URL.
  static String? normalizeServer(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last.endsWith('.php')) {
      segments.removeLast();
    }
    url = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments,
    ).toString();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  // ── Backup lists ────────────────────────────────────────────────────────

  List<String> backupsFor(String primary) =>
      List.unmodifiable(_backups[primary] ?? const <String>[]);

  /// Replaces the backup servers for [primary]. An empty list removes them.
  Future<void> setBackups(String primary, List<String> backups) async {
    await load();
    final cleaned = <String>[];
    for (final raw in backups) {
      final s = normalizeServer(raw);
      if (s != null && s != primary && !cleaned.contains(s)) cleaned.add(s);
    }
    if (cleaned.isEmpty) {
      _backups.remove(primary);
      _active.remove(primary);
    } else {
      _backups[primary] = cleaned;
      final active = _active[primary] ?? 0;
      if (active > cleaned.length) _active[primary] = 0;
    }
    await _save();
    changes.value++;
  }

  /// Moves the backups saved under [oldPrimary] to [newPrimary] (used when the
  /// user edits the main server address).
  Future<void> forget(String primary) => setBackups(primary, const []);

  // ── Active server ───────────────────────────────────────────────────────

  /// 0 = the main server, 1.. = a backup.
  int activeIndex(String primary) => _active[primary] ?? 0;

  /// Number of servers available (main + backups).
  int serverCount(String primary) => 1 + (_backups[primary]?.length ?? 0);

  String activeServer(String primary) {
    final index = activeIndex(primary);
    if (index <= 0) return primary;
    final list = _backups[primary];
    if (list == null || index > list.length) return primary;
    return list[index - 1];
  }

  /// Switches to the next server (wrapping back to the main one). Returns the
  /// server now in use.
  Future<String> switchNext(String primary) async {
    await load();
    final count = serverCount(primary);
    if (count < 2) return primary;
    _active[primary] = (activeIndex(primary) + 1) % count;
    await _save();
    changes.value++;
    return activeServer(primary);
  }

  // ── Channel URLs ────────────────────────────────────────────────────────

  /// Swaps the main server in a channel URL for the active backup. URLs for
  /// playlists without backups (or with the main server active) are returned
  /// unchanged.
  String rewrite(String url) {
    if (_backups.isEmpty) return url;
    for (final primary in _backups.keys) {
      if (!url.startsWith('$primary/')) continue;
      final index = activeIndex(primary);
      if (index <= 0) return url;
      final active = activeServer(primary);
      if (active == primary) return url;
      return '$active${url.substring(primary.length)}';
    }
    return url;
  }

  static final RegExp _liveUrl = RegExp(
    r'^(https?://.+?)/(?:live/)?([^/]+)/([^/]+)/\d+\.(?:ts|m3u8)$',
  );

  /// Works out which server and login a live channel URL belongs to, or null
  /// when [url] isn't an Xtream live URL.
  IptvStreamAddress? addressOf(String url) {
    for (final primary in _backups.keys) {
      for (final server in [primary, ...?_backups[primary]]) {
        if (!url.startsWith('$server/')) continue;
        final rest = url.substring(server.length + 1);
        final parts = rest.split('/');
        // live/<user>/<pass>/<id>.<ext>  or  <user>/<pass>/<id>.<ext>
        final creds = parts.first == 'live' ? parts.skip(1) : parts;
        final list = creds.toList();
        if (list.length < 3) continue;
        return IptvStreamAddress(
          primary: primary,
          server: activeServer(primary),
          username: Uri.decodeComponent(list[0]),
          password: Uri.decodeComponent(list[1]),
        );
      }
    }
    final match = _liveUrl.firstMatch(url);
    if (match == null) return null;
    final server = match.group(1)!;
    return IptvStreamAddress(
      primary: server,
      server: server,
      username: Uri.decodeComponent(match.group(2)!),
      password: Uri.decodeComponent(match.group(3)!),
    );
  }

  // ── Health ──────────────────────────────────────────────────────────────

  /// Logs in to [server] and times the answer. Never throws.
  static Future<IptvServerHealth> check(
    String server,
    String username,
    String password, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('$server/player_api.php').replace(
        queryParameters: {'username': username, 'password': password},
      );
      final response = await http.get(uri).timeout(timeout);
      final ms = stopwatch.elapsedMilliseconds;
      if (response.statusCode != 200) {
        return IptvServerHealth(
          server: server,
          online: false,
          error: 'HTTP ${response.statusCode}',
        );
      }
      try {
        final body = jsonDecode(response.body);
        final info = body is Map ? body['user_info'] : null;
        if (info is Map && '${info['auth']}' != '1') {
          return IptvServerHealth(
            server: server,
            online: false,
            latencyMs: ms,
            error: 'Login rejected',
          );
        }
      } catch (_) {
        // A server that answers but isn't JSON is still reachable; the
        // channel list itself will show whether it works.
      }
      return IptvServerHealth(server: server, online: true, latencyMs: ms);
    } on TimeoutException {
      return IptvServerHealth(server: server, online: false, error: 'Timed out');
    } catch (e) {
      return IptvServerHealth(
        server: server,
        online: false,
        error: 'No connection',
      );
    }
  }
}
