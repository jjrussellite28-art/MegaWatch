import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

enum LinkVerdict { good, caution, danger }

/// What a link turned out to be, without playing or downloading it.
class LinkReport {
  LinkReport({
    required this.input,
    required this.chain,
    required this.finalUrl,
    required this.verdict,
    required this.warnings,
    this.statusCode,
    this.contentType,
    this.size,
    this.isMedia = false,
    this.isHtml = false,
    this.isProgram = false,
    this.fileName = '',
    this.error,
  });

  final Uri input;

  /// Every address visited, in order (the first is the link itself).
  final List<Uri> chain;
  final Uri finalUrl;
  final LinkVerdict verdict;
  final List<String> warnings;
  final int? statusCode;
  final String? contentType;
  final int? size;
  final bool isMedia;
  final bool isHtml;
  final bool isProgram;
  final String fileName;
  final String? error;

  bool get https => finalUrl.scheme == 'https';
  int get redirects => chain.length - 1;
}

class DownloadScanResult {
  DownloadScanResult({
    required this.path,
    required this.bytes,
    required this.sha256Hex,
    required this.scanned,
    required this.clean,
    required this.message,
  });
  final String path;
  final int bytes;
  final String sha256Hex;

  /// Windows Defender actually ran on the file.
  final bool scanned;

  /// Defender ran and found nothing (only meaningful when [scanned]).
  final bool clean;
  final String message;
}

class DefenderStatus {
  DefenderStatus({required this.available, this.realTime, this.signaturesUpdated});
  final bool available;
  final bool? realTime;
  final String? signaturesUpdated;
}

class LinkCheckService {
  LinkCheckService._();
  static final LinkCheckService instance = LinkCheckService._();

  static const _mediaExt = {
    'mp4', 'mkv', 'avi', 'mov', 'webm', 'm4v', 'ts', 'm2ts', 'wmv', 'flv', 'mpg', 'mpeg',
    'm3u8', 'mpd', 'mp3', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'wav',
  };
  static const _programExt = {
    'exe', 'msi', 'bat', 'cmd', 'scr', 'com', 'pif', 'js', 'jse', 'vbs', 'vbe', 'wsf',
    'ps1', 'jar', 'apk', 'dll', 'lnk', 'hta', 'reg', 'iso', 'img',
  };

  static String _ext(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static Uri? normalize(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (!t.contains('://')) t = 'https://$t';
    final uri = Uri.tryParse(t);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static String _baseDomain(String host) {
    final parts = host.toLowerCase().split('.');
    return parts.length <= 2 ? host.toLowerCase() : parts.sublist(parts.length - 2).join('.');
  }

  /// Follows the link by hand (up to 8 redirects), reading only the headers
  /// and the first few bytes — nothing is downloaded or played.
  Future<LinkReport> analyze(String text) async {
    final start = normalize(text);
    if (start == null) {
      return LinkReport(
        input: Uri(),
        chain: const [],
        finalUrl: Uri(),
        verdict: LinkVerdict.danger,
        warnings: const [],
        error: 'That is not a web link (it should start with http:// or https://).',
      );
    }
    final client = http.Client();
    final chain = <Uri>[start];
    final warnings = <String>[];
    var current = start;
    http.StreamedResponse? last;
    String? firstChunk;
    try {
      for (var hop = 0; hop < 9; hop++) {
        final req = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Range': 'bytes=0-2047',
            'Accept': '*/*',
          });
        final res = await client.send(req).timeout(const Duration(seconds: 15));
        final code = res.statusCode;
        if ((code == 301 || code == 302 || code == 303 || code == 307 || code == 308) &&
            res.headers['location'] != null) {
          await res.stream.drain<void>().timeout(const Duration(seconds: 5), onTimeout: () {});
          final next = current.resolve(res.headers['location']!);
          if (current.scheme == 'https' && next.scheme == 'http') {
            warnings.add('The link drops from HTTPS to plain HTTP part-way — anyone on the network could see or change it.');
          }
          if (chain.length >= 9) break;
          current = next;
          chain.add(next);
          continue;
        }
        last = res;
        final builder = BytesBuilder();
        await for (final chunk in res.stream.timeout(const Duration(seconds: 10))) {
          builder.add(chunk);
          if (builder.length >= 2048) break;
        }
        firstChunk = utf8.decode(builder.toBytes(), allowMalformed: true).toLowerCase();
        break;
      }
    } on TimeoutException {
      client.close();
      return LinkReport(
        input: start,
        chain: chain,
        finalUrl: current,
        verdict: LinkVerdict.caution,
        warnings: warnings,
        error: 'The site did not answer in time.',
      );
    } catch (e) {
      client.close();
      return LinkReport(
        input: start,
        chain: chain,
        finalUrl: current,
        verdict: LinkVerdict.caution,
        warnings: warnings,
        error: 'Could not reach it ($e).',
      );
    }
    client.close();
    final res = last;
    if (res == null) {
      return LinkReport(
        input: start,
        chain: chain,
        finalUrl: current,
        verdict: LinkVerdict.danger,
        warnings: warnings..add('It redirected too many times — a common sign of ad or scam links.'),
      );
    }

    final type = (res.headers['content-type'] ?? '').toLowerCase();
    int? size;
    final range = res.headers['content-range'];
    if (range != null && range.contains('/')) {
      size = int.tryParse(range.split('/').last.trim());
    }
    size ??= res.contentLength;
    final ext = _ext(current.path);
    final sniffHtml = firstChunk != null &&
        (firstChunk.contains('<!doctype html') || firstChunk.contains('<html') || firstChunk.contains('<head'));
    final isHtml = type.contains('html') || (sniffHtml && !type.startsWith('video/'));
    final isMedia = !isHtml &&
        (type.startsWith('video/') ||
            type.startsWith('audio/') ||
            type.contains('mpegurl') ||
            type.contains('dash+xml') ||
            ((type.isEmpty || type.contains('octet-stream') || type.contains('binary')) &&
                _mediaExt.contains(ext)));
    final isProgram = _programExt.contains(ext) ||
        type.contains('x-msdownload') ||
        type.contains('x-msi') ||
        type.contains('x-dosexec') ||
        type.contains('java-archive') ||
        type.contains('vnd.android.package');

    final code = res.statusCode;
    if (code >= 400) {
      warnings.add('The site answered with an error ($code) — the link may be dead or need a login.');
    }
    if (current.scheme == 'http') {
      warnings.add('Plain HTTP: not encrypted. Your internet provider and anyone on the network can see what you watch, and the file could be swapped on the way.');
    }
    final others = chain.map((u) => _baseDomain(u.host)).toSet();
    if (others.length > 2) {
      warnings.add('It bounces through ${others.length} different sites before the file — typical of ad networks.');
    }
    if (isHtml) {
      warnings.add('This is a web page, not a video file. Pages like this carry ads and pop-ups, and Debrify cannot play them ad-free. Look for the direct video link (.mp4, .mkv or .m3u8).');
    }
    if (isProgram) {
      warnings.add('This is a PROGRAM or installer, not a video. Do not run it.');
    }
    if (!isHtml && !isMedia && !isProgram && code < 400) {
      warnings.add('Debrify could not tell what kind of file this is.');
    }

    var verdict = LinkVerdict.good;
    if (current.scheme == 'http' || others.length > 2 || isHtml || (!isMedia && !isProgram) || code >= 400) {
      verdict = LinkVerdict.caution;
    }
    if (isProgram || res.statusCode == 0) verdict = LinkVerdict.danger;
    if (warnings.any((w) => w.contains('drops from HTTPS'))) verdict = LinkVerdict.danger;

    final name = current.pathSegments.isNotEmpty && current.pathSegments.last.isNotEmpty
        ? Uri.decodeComponent(current.pathSegments.last)
        : current.host;
    return LinkReport(
      input: start,
      chain: chain,
      finalUrl: current,
      verdict: verdict,
      warnings: warnings,
      statusCode: code,
      contentType: type.isEmpty ? null : type,
      size: size,
      isMedia: isMedia,
      isHtml: isHtml,
      isProgram: isProgram,
      fileName: name,
    );
  }

  // ---- Windows Defender ---------------------------------------------------

  String? _mpCmdRun() {
    final candidates = <String>[];
    final pd = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    final platformDir = Directory('$pd\\Microsoft\\Windows Defender\\Platform');
    if (platformDir.existsSync()) {
      final dirs = platformDir.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
      for (final d in dirs.reversed) {
        candidates.add('$d\\MpCmdRun.exe');
      }
    }
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    candidates.add('$pf\\Windows Defender\\MpCmdRun.exe');
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<DefenderStatus> defenderStatus() async {
    if (!Platform.isWindows) return DefenderStatus(available: false);
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled,AntivirusSignatureLastUpdated | ConvertTo-Json -Compress',
      ]).timeout(const Duration(seconds: 15));
      if (r.exitCode != 0) return DefenderStatus(available: _mpCmdRun() != null);
      final j = jsonDecode(r.stdout.toString().trim()) as Map<String, dynamic>;
      var updated = j['AntivirusSignatureLastUpdated']?.toString();
      final m = RegExp(r'/Date\((\d+)\)/').firstMatch(updated ?? '');
      if (m != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!));
        updated = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      return DefenderStatus(
        available: true,
        realTime: j['RealTimeProtectionEnabled'] as bool?,
        signaturesUpdated: updated,
      );
    } catch (_) {
      return DefenderStatus(available: _mpCmdRun() != null);
    }
  }

  /// Downloads [url] to a temp folder, fingerprints it (SHA-256) and scans it
  /// with Windows Defender. [isCancelled] is polled so a download can be
  /// stopped. The file is deleted afterwards unless [keep] is true.
  Future<DownloadScanResult> downloadAndScan(
    Uri url, {
    required String fileName,
    required void Function(int received, int? total) onProgress,
    required bool Function() isCancelled,
    bool keep = false,
  }) async {
    final dir = Directory('${Platform.environment['TEMP'] ?? '.'}\\DebrifyLinks');
    await dir.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File('${dir.path}\\${safeName.isEmpty ? 'download.bin' : safeName}');
    final client = http.Client();
    final out = file.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      final req = http.Request('GET', url)
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      final res = await client.send(req);
      if (res.statusCode >= 400) {
        throw HttpException('The site answered with error ${res.statusCode}.');
      }
      await for (final chunk in res.stream) {
        if (isCancelled()) {
          throw const _Cancelled();
        }
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress(received, res.contentLength);
      }
      hasher.close();
      await out.close();
    } on _Cancelled {
      await out.close();
      client.close();
      try {
        await file.delete();
      } catch (_) {}
      return DownloadScanResult(
        path: file.path,
        bytes: received,
        sha256Hex: '',
        scanned: false,
        clean: false,
        message: 'Stopped. The partial file was deleted.',
      );
    } catch (e) {
      await out.close();
      client.close();
      try {
        await file.delete();
      } catch (_) {}
      return DownloadScanResult(
        path: file.path,
        bytes: received,
        sha256Hex: '',
        scanned: false,
        clean: false,
        message: 'Download failed ($e).',
      );
    }
    client.close();
    final hash = digestSink.value?.toString() ?? '';

    final mp = _mpCmdRun();
    if (mp == null) {
      return DownloadScanResult(
        path: file.path,
        bytes: received,
        sha256Hex: hash,
        scanned: false,
        clean: false,
        message: 'Windows Defender was not found, so the file was NOT scanned.',
      );
    }
    try {
      final r = await Process.run(mp, [
        '-Scan',
        '-ScanType',
        '3',
        '-File',
        file.path,
        '-DisableRemediation',
      ]).timeout(const Duration(minutes: 10));
      final clean = r.exitCode == 0;
      if (clean && !keep) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return DownloadScanResult(
        path: file.path,
        bytes: received,
        sha256Hex: hash,
        scanned: true,
        clean: clean,
        message: clean
            ? 'Windows Defender found no threats.'
            : 'Windows Defender reported a problem (code ${r.exitCode}). The file was kept in ${dir.path} — do NOT open it.',
      );
    } catch (e) {
      return DownloadScanResult(
        path: file.path,
        bytes: received,
        sha256Hex: hash,
        scanned: false,
        clean: false,
        message: 'The scan did not finish ($e).',
      );
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
