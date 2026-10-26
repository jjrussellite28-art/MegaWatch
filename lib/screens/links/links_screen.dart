import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../services/link_check_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/video_player_launcher.dart';
import '../../widgets/tv_text_field.dart';

/// The Links tab: check a web link before you trust it, play a direct video
/// link in Debrify's own player (no browser, so no ads or pop-ups), and see
/// how much memory the app uses and whether Windows Defender is on.
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  final TextEditingController _url = TextEditingController();
  final FocusNode _urlFocus = FocusNode(debugLabel: 'links-url');
  final FocusNode _pasteFocus = FocusNode(debugLabel: 'links-paste');
  late final VoidCallback _contentFocus;
  Timer? _timer;

  LinkReport? _report;
  bool _checking = false;

  DefenderStatus? _defender;

  bool _downloading = false;
  bool _cancel = false;
  int _received = 0;
  int? _total;
  DownloadScanResult? _scan;

  @override
  void initState() {
    super.initState();
    _contentFocus = () {
      if (mounted) _pasteFocus.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(21, _contentFocus);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
    LinkCheckService.instance.defenderStatus().then((s) {
      if (mounted) setState(() => _defender = s);
    });
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(21, _contentFocus);
    _timer?.cancel();
    _cancel = true;
    _url.dispose();
    _urlFocus.dispose();
    _pasteFocus.dispose();
    super.dispose();
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  static String _size(int? bytes) {
    if (bytes == null || bytes <= 0) return 'unknown size';
    if (bytes > 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return _mb(bytes);
  }

  Future<void> _pasteAndCheck() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) _url.text = text;
    await _check();
  }

  Future<void> _check() async {
    final text = _url.text.trim();
    if (text.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _report = null;
      _scan = null;
    });
    final r = await LinkCheckService.instance.analyze(text);
    if (!mounted) return;
    setState(() {
      _report = r;
      _checking = false;
    });
  }

  Future<void> _play(LinkReport r) async {
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(videoUrl: r.finalUrl.toString(), title: r.fileName),
    );
  }

  Future<void> _downloadAndScan(LinkReport r) async {
    setState(() {
      _downloading = true;
      _cancel = false;
      _received = 0;
      _total = r.size;
      _scan = null;
    });
    final result = await LinkCheckService.instance.downloadAndScan(
      r.finalUrl,
      fileName: r.fileName,
      onProgress: (got, total) {
        if (!mounted) return;
        // Cheap: only repaint a few times a second.
        if (got - _received > 512 * 1024 || (total != null && got == total)) {
          setState(() {
            _received = got;
            _total = total ?? _total;
          });
        }
      },
      isCancelled: () => _cancel,
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _scan = result;
    });
  }

  Color _verdictColor(LinkVerdict v) => switch (v) {
    LinkVerdict.good => const Color(0xFF51CF66),
    LinkVerdict.caution => const Color(0xFFFFC857),
    LinkVerdict.danger => const Color(0xFFFF6B6B),
  };

  String _verdictText(LinkVerdict v) => switch (v) {
    LinkVerdict.good => 'Looks OK',
    LinkVerdict.caution => 'Be careful',
    LinkVerdict.danger => 'Not safe',
  };

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    ),
    child: child,
  );

  Widget _appCard() {
    final ram = ProcessInfo.currentRss;
    final peak = ProcessInfo.maxRss;
    final d = _defender;
    final defenderText = d == null
        ? 'Checking Windows Defender…'
        : !d.available
        ? 'Windows Defender: not found'
        : 'Windows Defender: ${d.realTime == null ? 'installed' : d.realTime! ? 'protection ON' : 'protection OFF'}'
              '${d.signaturesUpdated != null ? ' · definitions ${d.signaturesUpdated}' : ''}';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This app', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Memory in use: ${_mb(ram)}   ·   highest so far: ${_mb(peak)}',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(defenderText, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _reportCard(LinkReport r) {
    if (r.error != null) {
      return _card(
        child: Text(r.error!, style: const TextStyle(color: Color(0xFFFFC857), fontSize: 15)),
      );
    }
    final color = _verdictColor(r.verdict);
    final kind = r.isMedia
        ? 'Video / audio file'
        : r.isHtml
        ? 'Web page'
        : r.isProgram
        ? 'Program / installer'
        : 'Unknown';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(_verdictText(r.verdict),
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r.fileName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            '${r.https ? 'HTTPS (encrypted)' : 'HTTP (NOT encrypted)'}   ·   $kind   ·   ${_size(r.size)}'
            '${r.redirects > 0 ? '   ·   ${r.redirects} redirect${r.redirects == 1 ? '' : 's'}' : ''}',
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          Text('Goes to: ${r.finalUrl.host}', style: const TextStyle(fontSize: 14, color: Colors.white70)),
          for (final w in r.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $w', style: const TextStyle(fontSize: 14, color: Color(0xFFFFC857))),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (r.isMedia)
              FilledButton.icon(
                autofocus: true,
                onPressed: () => _play(r),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play in Debrify (no ads)'),
              ),
            if (!r.isHtml && Platform.isWindows)
              OutlinedButton.icon(
                autofocus: !r.isMedia,
                onPressed: _downloading ? null : () => _downloadAndScan(r),
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Download & scan with Windows Defender'),
              ),
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: r.finalUrl.toString())),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy final link'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _scanCard() {
    if (_downloading) {
      final t = _total;
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Downloading to scan… ${_mb(_received)}${t != null && t > 0 ? ' of ${_mb(t)}' : ''}',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (t != null && t > 0) ? (_received / t).clamp(0, 1).toDouble() : null),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => setState(() => _cancel = true), child: const Text('Stop')),
          ],
        ),
      );
    }
    final s = _scan;
    if (s == null) return const SizedBox.shrink();
    final color = !s.scanned
        ? const Color(0xFFFFC857)
        : s.clean
        ? const Color(0xFF51CF66)
        : const Color(0xFFFF6B6B);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.message, style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w700)),
          if (s.sha256Hex.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('SHA-256: ${s.sha256Hex}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(88, 20, 32, 16),
          child: ListView(
            children: [
              const Text('Links & safety',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 12),
              _appCard(),
              const Text(
                'Found a video link? Paste it here. Debrify checks where it really goes, and plays direct video '
                'links in its own player — no browser, so no ads, pop-ups or redirects.',
                style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 10),
              TvTextField(
                controller: _url,
                focusNode: _urlFocus,
                hintText: 'http:// or https:// link',
                prefixIcon: const Icon(Icons.link_rounded),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  focusNode: _pasteFocus,
                  onPressed: _checking ? null : _pasteAndCheck,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Paste & check'),
                ),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Check'),
                ),
              ]),
              const SizedBox(height: 14),
              if (_checking)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(children: [
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    SizedBox(width: 12),
                    Text('Following the link…'),
                  ]),
                ),
              if (_report != null) _reportCard(_report!),
              _scanCard(),
            ],
          ),
        ),
      ),
    );
  }
}
