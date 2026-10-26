import 'dart:convert';
import 'dart:io';

/// One game in the library.
class LibraryGame {
  LibraryGame({
    required this.id,
    required this.name,
    required this.source,
    required this.launch,
    this.coverUrl,
    this.fallbackCoverUrl,
    this.exePath,
    this.args = '',
    this.lastPlayed = 0,
    this.custom = false,
  });

  /// Unique: `steam:<appid>`, `epic:<appname>`, `custom:<id>`.
  final String id;
  final String name;

  /// 'Steam', 'Epic' or 'My games'.
  final String source;

  /// A link Windows opens (steam://…, com.epicgames.launcher://…) — or '' for
  /// a program started directly from [exePath].
  final String launch;
  final String? coverUrl;
  final String? fallbackCoverUrl;
  final String? exePath;
  final String args;
  final int lastPlayed;
  final bool custom;
}

/// Finds the games installed through Steam and the Epic Games launcher, and
/// keeps a list of programs the user added by hand. Everything is read from
/// files the launchers already keep on disk — no accounts, no network.
class GameLibraryService {
  GameLibraryService._();
  static final GameLibraryService instance = GameLibraryService._();

  static bool get supported => Platform.isWindows;

  static String get _appData => Platform.environment['APPDATA'] ?? '.';
  static File get _customFile => File('$_appData\\Debrify\\custom_games.json');
  static File get _playedFile => File('$_appData\\Debrify\\games_played.json');

  Map<String, int> _played = {};

  Future<void> _loadPlayed() async {
    try {
      if (await _playedFile.exists()) {
        final j = jsonDecode(await _playedFile.readAsString());
        if (j is Map) {
          _played = {for (final e in j.entries) e.key.toString(): (e.value as num).toInt()};
        }
      }
    } catch (_) {}
  }

  Future<void> markPlayed(LibraryGame g) async {
    _played[g.id] = DateTime.now().millisecondsSinceEpoch;
    try {
      await Directory('$_appData\\Debrify').create(recursive: true);
      await _playedFile.writeAsString(jsonEncode(_played));
    } catch (_) {}
  }

  Future<List<LibraryGame>> loadAll() async {
    if (!supported) return const [];
    await _loadPlayed();
    final out = <LibraryGame>[
      ...await _steam(),
      ...await _epic(),
      ...await _custom(),
    ];
    return [
      for (final g in out)
        LibraryGame(
          id: g.id,
          name: g.name,
          source: g.source,
          launch: g.launch,
          coverUrl: g.coverUrl,
          fallbackCoverUrl: g.fallbackCoverUrl,
          exePath: g.exePath,
          args: g.args,
          lastPlayed: _played[g.id] ?? g.lastPlayed,
          custom: g.custom,
        ),
    ];
  }

  // ---- Steam ----------------------------------------------------------------

  Future<String?> _steamPath() async {
    try {
      final r = await Process.run('reg', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'SteamPath',
      ]);
      if (r.exitCode == 0) {
        final m = RegExp(r'SteamPath\s+REG_SZ\s+(.+)').firstMatch(r.stdout.toString());
        if (m != null) {
          final p = m.group(1)!.trim().replaceAll('/', '\\');
          if (Directory(p).existsSync()) return p;
        }
      }
    } catch (_) {}
    for (final p in [
      r'C:\Program Files (x86)\Steam',
      r'C:\Program Files\Steam',
    ]) {
      if (Directory(p).existsSync()) return p;
    }
    return null;
  }

  static const _steamSkip = [
    'steamworks common redistributables',
    'steam linux runtime',
    'proton',
    'steamvr',
    'steam controller configs',
  ];

  Future<List<LibraryGame>> _steam() async {
    final root = await _steamPath();
    if (root == null) return const [];
    final libs = <String>{'$root\\steamapps'};
    try {
      final vdf = File('$root\\steamapps\\libraryfolders.vdf');
      if (vdf.existsSync()) {
        for (final m in RegExp(r'"path"\s+"([^"]+)"').allMatches(await vdf.readAsString())) {
          libs.add('${m.group(1)!.replaceAll(r'\\', r'\')}\\steamapps');
        }
      }
    } catch (_) {}
    final games = <LibraryGame>[];
    final seen = <String>{};
    for (final lib in libs) {
      final dir = Directory(lib);
      if (!dir.existsSync()) continue;
      try {
        for (final f in dir.listSync()) {
          if (f is! File) continue;
          final base = f.path.split('\\').last;
          if (!base.startsWith('appmanifest_') || !base.endsWith('.acf')) continue;
          final text = await f.readAsString();
          final id = RegExp(r'"appid"\s+"(\d+)"').firstMatch(text)?.group(1);
          final name = RegExp(r'"name"\s+"([^"]+)"').firstMatch(text)?.group(1);
          if (id == null || name == null || !seen.add(id)) continue;
          if (_steamSkip.any((s) => name.toLowerCase().contains(s))) continue;
          final last = int.tryParse(RegExp(r'"LastPlayed"\s+"(\d+)"').firstMatch(text)?.group(1) ?? '') ?? 0;
          games.add(
            LibraryGame(
              id: 'steam:$id',
              name: name,
              source: 'Steam',
              launch: 'steam://rungameid/$id',
              coverUrl: 'https://cdn.cloudflare.steamstatic.com/steam/apps/$id/library_600x900.jpg',
              fallbackCoverUrl: 'https://cdn.cloudflare.steamstatic.com/steam/apps/$id/header.jpg',
              lastPlayed: last * 1000,
            ),
          );
        }
      } catch (_) {}
    }
    return games;
  }

  // ---- Epic -----------------------------------------------------------------

  Future<List<LibraryGame>> _epic() async {
    final pd = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    final dir = Directory('$pd\\Epic\\EpicGamesLauncher\\Data\\Manifests');
    if (!dir.existsSync()) return const [];
    final games = <LibraryGame>[];
    try {
      for (final f in dir.listSync()) {
        if (f is! File || !f.path.toLowerCase().endsWith('.item')) continue;
        try {
          final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final name = j['DisplayName']?.toString() ?? '';
          final app = j['AppName']?.toString() ?? '';
          final ns = j['CatalogNamespace']?.toString() ?? '';
          final item = j['CatalogItemId']?.toString() ?? '';
          final exe = j['LaunchExecutable']?.toString() ?? '';
          if (name.isEmpty || app.isEmpty || exe.isEmpty) continue;
          final launch = (ns.isNotEmpty && item.isNotEmpty)
              ? 'com.epicgames.launcher://apps/$ns%3A$item%3A$app?action=launch&silent=true'
              : 'com.epicgames.launcher://apps/$app?action=launch&silent=true';
          games.add(LibraryGame(id: 'epic:$app', name: name, source: 'Epic', launch: launch));
        } catch (_) {}
      }
    } catch (_) {}
    return games;
  }

  // ---- My games (added by hand) ---------------------------------------------

  Future<List<LibraryGame>> _custom() async {
    try {
      if (!await _customFile.exists()) return const [];
      final j = jsonDecode(await _customFile.readAsString());
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (e is Map)
            LibraryGame(
              id: 'custom:${e['id']}',
              name: e['name']?.toString() ?? 'Game',
              source: 'My games',
              launch: '',
              exePath: e['exe']?.toString(),
              args: e['args']?.toString() ?? '',
              custom: true,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCustom(List<Map<String, dynamic>> list) async {
    await Directory('$_appData\\Debrify').create(recursive: true);
    await _customFile.writeAsString(const JsonEncoder.withIndent('  ').convert(list));
  }

  Future<List<Map<String, dynamic>>> _customRaw() async {
    try {
      if (await _customFile.exists()) {
        final j = jsonDecode(await _customFile.readAsString());
        if (j is List) return [for (final e in j) if (e is Map) Map<String, dynamic>.from(e)];
      }
    } catch (_) {}
    return [];
  }

  Future<void> addCustom({required String name, required String exe, String args = ''}) async {
    final list = await _customRaw();
    list.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name,
      'exe': exe,
      'args': args,
    });
    await _saveCustom(list);
  }

  Future<void> removeCustom(LibraryGame g) async {
    final id = g.id.substring('custom:'.length);
    final list = await _customRaw()..removeWhere((e) => e['id'].toString() == id);
    await _saveCustom(list);
  }

  /// Programs from the Start menu, for adding a game without typing a path.
  Future<List<MapEntry<String, String>>> installedApps() async {
    final roots = [
      '${Platform.environment['ProgramData'] ?? r'C:\ProgramData'}\\Microsoft\\Windows\\Start Menu\\Programs',
      '${Platform.environment['APPDATA'] ?? ''}\\Microsoft\\Windows\\Start Menu\\Programs',
    ];
    final skip = RegExp(r'uninstall|readme|help|documentation|license|release notes', caseSensitive: false);
    final found = <String, MapEntry<String, String>>{};
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File || !e.path.toLowerCase().endsWith('.lnk')) continue;
          final file = e.path.split('\\').last;
          final name = file.substring(0, file.length - 4);
          if (skip.hasMatch(name)) continue;
          found.putIfAbsent(name.toLowerCase(), () => MapEntry(name, e.path));
        }
      } catch (_) {}
    }
    final list = found.values.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return list;
  }

  /// Starts a game. Returns null on success or a short message.
  Future<String?> play(LibraryGame g) async {
    try {
      if (g.launch.isNotEmpty) {
        await Process.run('cmd', ['/c', 'start', '', g.launch]);
      } else {
        final exe = g.exePath ?? '';
        if (exe.isEmpty || !File(exe).existsSync()) return 'Not found: $exe';
        if (exe.toLowerCase().endsWith('.lnk')) {
          await Process.run('cmd', ['/c', 'start', '', exe]);
        } else {
          await Process.start(
            exe,
            g.args.trim().isEmpty ? <String>[] : g.args.trim().split(RegExp(r'\s+')),
            mode: ProcessStartMode.detached,
            workingDirectory: File(exe).parent.path,
          );
        }
      }
      await markPlayed(g);
      return null;
    } catch (e) {
      return 'Could not start ${g.name} ($e)';
    }
  }
}
