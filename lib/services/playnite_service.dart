import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One game from the Playnite library.
class PlayniteGame {
  const PlayniteGame({
    required this.id,
    required this.name,
    this.cover,
    this.platform = '',
    this.installed = true,
    this.favorite = false,
    this.lastActivity,
  });

  final String id;
  final String name;
  final String? cover;
  final String platform;
  final bool installed;
  final bool favorite;
  final DateTime? lastActivity;
}

/// Reads the Playnite library (through a small Playnite helper that writes a
/// list of games) and starts games or Playnite itself.
class PlayniteService {
  PlayniteService._();
  static final PlayniteService instance = PlayniteService._();

  static bool get supported => !kIsWeb && Platform.isWindows;

  static String get _appData => Platform.environment['APPDATA'] ?? '';
  static String get _localAppData => Platform.environment['LOCALAPPDATA'] ?? '';

  static String get libraryFile => '$_appData\\Debrify\\playnite_games.json';
  static String get extensionDir =>
      '$_appData\\Playnite\\Extensions\\DebrifyExport';

  /// True when Playnite's data folder exists on this PC.
  bool get playniteInstalled =>
      supported && Directory('$_appData\\Playnite').existsSync();

  bool get helperInstalled =>
      supported && File('$extensionDir\\extension.yaml').existsSync();

  /// Loads the exported library, or null when it does not exist yet.
  Future<List<PlayniteGame>?> loadGames() async {
    if (!supported) return null;
    final file = File(libraryFile);
    if (!await file.exists()) return null;
    var text = await file.readAsString();
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    final decoded = jsonDecode(text);
    final list = decoded is List ? decoded : <dynamic>[decoded];
    final games = <PlayniteGame>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString() ?? '';
      final name = raw['name']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final cover = raw['cover']?.toString();
      games.add(
        PlayniteGame(
          id: id,
          name: name,
          cover: (cover == null || cover.isEmpty) ? null : cover,
          platform: raw['platform']?.toString() ?? '',
          installed: raw['installed'] != false,
          favorite: raw['favorite'] == true,
          lastActivity: DateTime.tryParse(raw['lastActivity']?.toString() ?? ''),
        ),
      );
    }
    games.sort((a, b) {
      final x = a.lastActivity?.millisecondsSinceEpoch ?? 0;
      final y = b.lastActivity?.millisecondsSinceEpoch ?? 0;
      if (x != y) return y.compareTo(x);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return games;
  }

  /// Starts a game through Playnite.
  Future<void> launch(PlayniteGame game) async {
    await Process.run('cmd', [
      '/c',
      'start',
      '',
      'playnite://playnite/start/${game.id}',
    ]);
  }

  /// Opens Playnite's own fullscreen (controller) mode, or the desktop mode.
  Future<bool> openPlaynite() async {
    final candidates = <String>[
      '$_localAppData\\Playnite\\Playnite.FullscreenApp.exe',
      'C:\\Program Files\\Playnite\\Playnite.FullscreenApp.exe',
      'C:\\Program Files (x86)\\Playnite\\Playnite.FullscreenApp.exe',
      '$_localAppData\\Playnite\\Playnite.DesktopApp.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        await Process.start(path, const [], mode: ProcessStartMode.detached);
        return true;
      }
    }
    return false;
  }

  /// Installs the small Playnite helper that exports the library for Debrify.
  /// Returns null on success, otherwise a message.
  Future<String?> installHelper() async {
    if (!supported) return 'This is only for Windows.';
    if (!Directory('$_appData\\Playnite').existsSync()) {
      return 'Playnite was not found. Install it from playnite.link first.';
    }
    try {
      final dir = Directory(extensionDir);
      await dir.create(recursive: true);
      await File('$extensionDir\\extension.yaml').writeAsString(_manifest);
      await File('$extensionDir\\DebrifyExport.psm1').writeAsString(_script);
      return null;
    } catch (e) {
      return 'Could not install the helper ($e).';
    }
  }

  static const String _manifest = '''Id: DebrifyExport_Library
Name: Debrify Export
Author: Debrify
Version: 1.0
Module: DebrifyExport.psm1
Type: Script
''';

  static const String _script = r'''
function Export-DebrifyGames {
    try {
        $dir = Join-Path $env:APPDATA 'Debrify'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $items = @()
        foreach ($g in $PlayniteApi.Database.Games) {
            if ($g.Hidden) { continue }
            $cover = $null
            if ($g.CoverImage) { $cover = $PlayniteApi.Database.GetFullFilePath($g.CoverImage) }
            $platform = ''
            if ($g.Platforms) { $platform = (($g.Platforms | ForEach-Object { $_.Name }) -join ', ') }
            $last = $null
            if ($g.LastActivity) { $last = $g.LastActivity.ToString('o') }
            $items += [pscustomobject]@{
                id = $g.Id.ToString()
                name = $g.Name
                cover = $cover
                platform = $platform
                installed = [bool]$g.IsInstalled
                favorite = [bool]$g.Favorite
                lastActivity = $last
            }
        }
        $json = ConvertTo-Json -InputObject @($items) -Depth 4
        $path = Join-Path $dir 'playnite_games.json'
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        try {
            $log = Join-Path (Join-Path $env:APPDATA 'Debrify') 'playnite_export_error.txt'
            [System.IO.File]::WriteAllText($log, $_.ToString())
        } catch { }
    }
}

function OnApplicationStarted() { Export-DebrifyGames }
function OnLibraryUpdated() { Export-DebrifyGames }
''';
}
