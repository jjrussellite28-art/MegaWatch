import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One file found on Easynews.
class EasynewsResult {
  const EasynewsResult({
    required this.title,
    required this.url,
    required this.sizeBytes,
    this.published,
    this.extension = '',
    this.details = '',
  });

  /// File name as shown on the Easynews website.
  final String title;

  /// Direct link to the file. Needs the account login to open.
  final String url;
  final int sizeBytes;
  final DateTime? published;
  final String extension;
  final String details;

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (sizeBytes >= gb) return '${(sizeBytes / gb).toStringAsFixed(2)} GB';
    if (sizeBytes >= mb) return '${(sizeBytes / mb).toStringAsFixed(0)} MB';
    return '${(sizeBytes / kb).toStringAsFixed(0)} KB';
  }
}

class EasynewsException implements Exception {
  const EasynewsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Easynews (Usenet) account + search.
///
/// Uses your own Easynews login. Searching works like the Easynews website's
/// own search (the same search page, asked for its results feed), and playing a
/// result streams the file straight from Easynews with your login.
class EasynewsService {
  EasynewsService._();
  static final EasynewsService instance = EasynewsService._();

  static const String _userKey = 'easynews_username_v1';
  static const String _passKey = 'easynews_password_v1';
  static const String _host = 'members.easynews.com';

  /// Bumps whenever the saved login changes.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  String _username = '';
  String _password = '';
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString(_userKey) ?? '';
      _password = prefs.getString(_passKey) ?? '';
    } catch (e) {
      debugPrint('EasynewsService: load failed: $e');
    }
    _loaded = true;
  }

  Future<bool> isConfigured() async {
    await load();
    return _username.isNotEmpty && _password.isNotEmpty;
  }

  Future<String> savedUsername() async {
    await load();
    return _username;
  }

  Future<void> _store(String username, String password) async {
    _username = username;
    _password = password;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (username.isEmpty) {
        await prefs.remove(_userKey);
        await prefs.remove(_passKey);
      } else {
        await prefs.setString(_userKey, username);
        await prefs.setString(_passKey, password);
      }
    } catch (e) {
      debugPrint('EasynewsService: save failed: $e');
    }
    changes.value++;
  }

  Future<void> clear() => _store('', '');

  Map<String, String> _authHeaders(String username, String password) => {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
  };

  /// Headers the player needs to open a result's link.
  Future<Map<String, String>> playbackHeaders() async {
    await load();
    return _authHeaders(_username, _password);
  }

  /// Checks a login and saves it when it works. Returns null on success,
  /// otherwise a short message saying what went wrong.
  Future<String?> verifyAndSave(String username, String password) async {
    final user = username.trim();
    final pass = password.trim();
    if (user.isEmpty || pass.isEmpty) {
      return 'Enter your Easynews username and password.';
    }
    try {
      final response = await http
          .get(
            _searchUri('test', pageSize: 1, videoOnly: true),
            headers: _authHeaders(user, pass),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return 'Easynews did not accept that username and password.';
      }
      if (response.statusCode != 200) {
        return 'Easynews answered with error ${response.statusCode}.';
      }
    } on TimeoutException {
      return 'Easynews did not answer in time. Try again.';
    } catch (e) {
      return 'Could not reach Easynews ($e).';
    }
    await _store(user, pass);
    return null;
  }

  Uri _searchUri(String query, {int pageSize = 200, bool videoOnly = true}) {
    return Uri.https(_host, '/1.0/global5/search.html', <String, String>{
      'fil': query,
      'submit': 'Search',
      if (videoOnly) 'fty[]': 'VIDEO',
      's1': 'dtime',
      's2': 'nsubject',
      's3': 'nrfile',
      'pby': '$pageSize',
      'pno': '1',
      'sS': '5',
      'u': '1',
      'fly': '1',
    });
  }

  /// Searches Easynews. Throws [EasynewsException] with a readable message.
  Future<List<EasynewsResult>> search(
    String query, {
    bool videoOnly = true,
    int pageSize = 200,
  }) async {
    await load();
    final text = query.trim();
    if (text.isEmpty) return const [];
    if (_username.isEmpty || _password.isEmpty) {
      throw const EasynewsException('Add your Easynews login in Settings.');
    }
    final http.Response response;
    try {
      response = await http
          .get(
            _searchUri(text, pageSize: pageSize, videoOnly: videoOnly),
            headers: _authHeaders(_username, _password),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const EasynewsException('Easynews did not answer in time.');
    } catch (e) {
      throw EasynewsException('Could not reach Easynews ($e).');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const EasynewsException(
        'Easynews rejected the saved login. Check it in Settings.',
      );
    }
    if (response.statusCode != 200) {
      throw EasynewsException(
        'Easynews answered with error ${response.statusCode}.',
      );
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    return _parse(body);
  }

  static List<EasynewsResult> _parse(String body) {
    final itemPattern = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final matches = itemPattern.allMatches(body).toList();
    if (matches.isEmpty) {
      if (body.contains('<rss') || body.contains('<channel')) {
        return const [];
      }
      final snippet = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      throw EasynewsException(
        'Unexpected answer from Easynews: '
        '${snippet.length > 160 ? snippet.substring(0, 160) : snippet}',
      );
    }
    final results = <EasynewsResult>[];
    final seen = <String>{};
    for (final match in matches) {
      final block = match.group(1) ?? '';
      var url = '';
      var size = 0;
      final enclosure = RegExp(r'<enclosure\s+([^>]*?)/?>').firstMatch(block);
      if (enclosure != null) {
        final attrs = enclosure.group(1) ?? '';
        url = _attribute(attrs, 'url') ?? '';
        size = int.tryParse(_attribute(attrs, 'length') ?? '') ?? 0;
      }
      if (url.isEmpty) url = _tag(block, 'link');
      if (url.isEmpty || !seen.add(url)) continue;

      var name = '';
      final path = Uri.tryParse(url)?.pathSegments ?? const <String>[];
      if (path.isNotEmpty) name = Uri.decodeComponent(path.last);
      if (name.isEmpty) name = _tag(block, 'title');
      final extMatch = RegExp(r'(\.[A-Za-z0-9]{2,5})$').firstMatch(name);
      final extension = extMatch?.group(1)?.toLowerCase() ?? '';

      // Samples and tiny clips are noise in a movie/TV search.
      if (name.toLowerCase().contains('sample') && size < 300 * 1024 * 1024) {
        continue;
      }

      DateTime? published;
      final pub = _tag(block, 'pubDate');
      if (pub.isNotEmpty) {
        try {
          published = HttpDate.parse(pub);
        } catch (_) {
          published = DateTime.tryParse(pub);
        }
      }
      results.add(
        EasynewsResult(
          title: name,
          url: url,
          sizeBytes: size,
          published: published,
          extension: extension,
          details: _plain(_tag(block, 'description')),
        ),
      );
    }
    return results;
  }

  static String? _attribute(String attrs, String name) {
    final m = RegExp('$name\\s*=\\s*"([^"]*)"').firstMatch(attrs) ??
        RegExp("$name\\s*=\\s*'([^']*)'").firstMatch(attrs);
    final value = m?.group(1);
    return value == null ? null : _decode(value);
  }

  static String _tag(String block, String tag) {
    final m = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(block);
    var value = m?.group(1) ?? '';
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
    value = value.replaceAllMapped(cdata, (c) => c.group(1) ?? '');
    return _decode(value).trim();
  }

  static String _plain(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _decode(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}
