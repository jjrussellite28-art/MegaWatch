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
    this.picture,
  });

  /// File name as shown on the Easynews website.
  final String title;

  /// Direct link to the file. Needs the account login to open.
  final String url;
  final int sizeBytes;
  final DateTime? published;
  final String extension;
  final String details;

  /// The long file id inside the link (about 40 characters), when there is one.
  String? get fileId {
    final m = RegExp(r'/dl/(?:[^/]*/)?([0-9a-fA-F]{38,64})').firstMatch(url) ??
        RegExp(r'([0-9a-fA-F]{38,64})').firstMatch(url);
    return m?.group(1)?.toLowerCase();
  }

  /// Preview picture given by Easynews itself, when the feed has one.
  final String? picture;

  /// Preview picture, like the thumbnails on the Easynews website.
  String? get thumbnailUrl {
    if (picture != null && picture!.isNotEmpty) return picture;
    final id = fileId;
    if (id == null) return null;
    return 'https://th.easynews.com/thumbnails-${id.substring(0, 3)}/th-$id.jpg';
  }

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

/// What kind of files to look for (the Easynews website's file type boxes).
enum EasynewsType {
  video('Video', 'VIDEO'),
  audio('Audio', 'AUDIO'),
  image('Pictures', 'IMAGE'),
  archive('Archives', 'ARCHIVE'),
  everything('Everything', null);

  const EasynewsType(this.label, this.param);
  final String label;
  final String? param;
}

/// A link ready for the player: the final address plus the login it needs.
class EasynewsPlayback {
  const EasynewsPlayback({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
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
            _searchUri('test', pageSize: 1),
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

  Uri _searchUri(
    String query, {
    int pageSize = 200,
    int page = 1,
    EasynewsType type = EasynewsType.video,
  }) {
    return Uri.https(_host, '/1.0/global5/search.html', <String, String>{
      'fil': query,
      'submit': 'Search',
      if (type.param != null) 'fty[]': type.param!,
      's1': 'dtime',
      's2': 'nsubject',
      's3': 'nrfile',
      'pby': '$pageSize',
      'pno': '$page',
      'sS': '5',
      'u': '1',
      'fly': '1',
    });
  }

  /// Searches Easynews. Throws [EasynewsException] with a readable message.
  Future<List<EasynewsResult>> search(
    String query, {
    EasynewsType type = EasynewsType.video,
    int page = 1,
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
            _searchUri(text, pageSize: pageSize, page: page, type: type),
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
    final all = _parse(body);
    if (type != EasynewsType.video) return all;
    // Video search: only real, playable video files (no leftovers or tiny clips).
    return all
        .where(
          (r) =>
              videoExtensions.contains(r.extension) &&
              (r.sizeBytes == 0 || r.sizeBytes >= 30 * 1024 * 1024),
        )
        .toList();
  }

  /// Always use the encrypted (https) address, so your internet provider can
  /// see that you connect to Easynews but not what you are watching.
  static String secureUrl(String url) {
    var u = url.trim();
    if (u.startsWith('http://')) u = 'https://${u.substring(7)}';
    return u.replaceFirst(RegExp(r'^(https://[^/:]+):80(?=/)'), r'$1');
  }

  static bool _isEasynewsHost(Uri uri) =>
      uri.host == 'easynews.com' || uri.host.endsWith('.easynews.com');

  /// Headers for loading Easynews pictures.
  Future<Map<String, String>> imageHeaders() => playbackHeaders();

  /// Checks a result's link before playing: follows redirects, makes sure the
  /// login is accepted and the file still exists, and returns the final secure
  /// address. Throws [EasynewsException] with a readable reason otherwise.
  Future<EasynewsPlayback> preparePlayback(EasynewsResult result) async {
    await load();
    if (_username.isEmpty || _password.isEmpty) {
      throw const EasynewsException('Add your Easynews login in Settings.');
    }
    final auth = _authHeaders(_username, _password);
    var uri = Uri.parse(secureUrl(result.url));
    final client = http.Client();
    try {
      for (var hop = 0; hop < 6; hop++) {
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(
            _isEasynewsHost(uri)
                ? auth
                : const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
          )
          ..headers['Range'] = 'bytes=0-0';
        final http.StreamedResponse response;
        try {
          response = await client.send(request).timeout(
            const Duration(seconds: 25),
          );
        } on TimeoutException {
          throw const EasynewsException('Easynews did not answer in time.');
        } catch (e) {
          throw EasynewsException('Could not reach Easynews ($e).');
        }
        // Do not download the file here; only the answer matters.
        final sub = response.stream.listen((_) {}, onError: (_) {});
        await sub.cancel();
        final code = response.statusCode;
        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
          final location = response.headers['location'];
          if (location == null || location.isEmpty) {
            throw const EasynewsException('Easynews sent a broken redirect.');
          }
          uri = Uri.parse(secureUrl(uri.resolve(location).toString()));
          continue;
        }
        if (code == 200 || code == 206) {
          final type = (response.headers['content-type'] ?? '').toLowerCase();
          if (type.startsWith('text/') || type.contains('json')) {
            throw const EasynewsException(
              'Easynews sent a web page instead of the video. Check your '
              'account is active and has not hit its limit.',
            );
          }
          final onEasynews = _isEasynewsHost(uri);
          // The login goes in the address too: the player then sends it on its
          // own for every request, including after redirects.
          final playUri = onEasynews
              ? uri.replace(userInfo: '${Uri.encodeComponent(_username)}:'
                    '${Uri.encodeComponent(_password)}')
              : uri;
          return EasynewsPlayback(
            url: playUri.toString(),
            headers: onEasynews ? auth : const <String, String>{},
          );
        }
        if (code == 401 || code == 403) {
          throw EasynewsException(
            'Easynews refused this file ($code). Check your login, your '
            'account limit, or whether the file needs a different plan.',
          );
        }
        if (code == 404 || code == 410) {
          throw const EasynewsException('That file is no longer on Easynews.');
        }
        throw EasynewsException('Easynews answered with error $code.');
      }
      throw const EasynewsException('Too many redirects from Easynews.');
    } finally {
      client.close();
    }
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
      url = secureUrl(_decode(url));
      if (!url.startsWith('https://')) continue;
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
      final description = _plain(_tag(block, 'description'));
      if (size == 0) size = _sizeFromText('$description ${_tag(block, 'title')}');

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
          details: description,
          picture: _findPicture(block),
        ),
      );
    }
    return results;
  }

  /// Looks for a thumbnail the feed already provides (media:thumbnail, an
  /// image tag in the description, or an image enclosure).
  static String? _findPicture(String block) {
    final media = RegExp(
      r'<media:thumbnail[^>]*?url\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(block);
    if (media != null) return _secureThumb(_decode(media.group(1)!));
    final img = RegExp(
      r'''<img[^>]*?src\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(_decode(_tag(block, 'description')));
    if (img != null) return _secureThumb(img.group(1)!);
    final raw = RegExp(
      r'''https?://[^\s"'<>]*thumbnails[^\s"'<>]*\.(?:jpg|jpeg|png)''',
      caseSensitive: false,
    ).firstMatch(_decode(block));
    if (raw != null) return _secureThumb(raw.group(0)!);
    return null;
  }

  static String _secureThumb(String url) {
    final u = secureUrl(url.trim());
    return u.startsWith('//') ? 'https:$u' : u;
  }

  static int _sizeFromText(String text) {
    final m = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(KB|MB|GB|TB)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    final unit = m.group(2)!.toUpperCase();
    const mult = {'KB': 1024, 'MB': 1048576, 'GB': 1073741824, 'TB': 1099511627776};
    return (n * (mult[unit] ?? 1)).round();
  }

  /// File types the player can really open as a movie or episode.
  static const Set<String> videoExtensions = {
    '.mp4', '.mkv', '.avi', '.wmv', '.flv', '.mov', '.webm', '.m4v',
    '.ts', '.m2ts', '.mts', '.mpg', '.mpeg', '.vob', '.divx', '.ogv', '.3gp',
  };

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

  static String _decode(String input) {
    var s = input.trim();
    if (s.startsWith('<![CDATA[') && s.endsWith(']]>')) {
      s = s.substring(9, s.length - 3);
    }
    // Run twice so double-encoded text (&amp;#58;) also comes out right.
    for (var pass = 0; pass < 2; pass++) {
      s = s.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
        final g = m.group(1)!;
        final code = g.startsWith('x') || g.startsWith('X')
            ? int.tryParse(g.substring(1), radix: 16)
            : int.tryParse(g);
        if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
        return String.fromCharCode(code);
      });
      s = s
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&amp;', '&');
    }
    return s;
  }
}
