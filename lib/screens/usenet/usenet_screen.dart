import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../services/easynews_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/video_player_launcher.dart';
import '../../widgets/tv_text_field.dart';
import '../settings/easynews_settings_page.dart';
import '../settings/widgets/settings_widgets.dart' show pushSettingsPage;

enum _UsenetSort { newest, biggest, name }

/// The Usenet tab: search Easynews like its website does and play a result.
class UsenetScreen extends StatefulWidget {
  const UsenetScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  @override
  State<UsenetScreen> createState() => _UsenetScreenState();
}

class _UsenetScreenState extends State<UsenetScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode(debugLabel: 'usenet-query');

  bool _checking = true;
  bool _configured = false;
  bool _searching = false;
  EasynewsType _type = EasynewsType.video;
  int _page = 1;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _opening = false;
  final FocusNode _setupFocus = FocusNode(debugLabel: 'usenet-setup');
  late final VoidCallback _contentFocus;

  /// The result under the mouse or controller focus, shown big on the right.
  final ValueNotifier<EasynewsResult?> _preview = ValueNotifier(null);
  Map<String, String> _imageHeaders = const {};
  String? _error;
  String _lastQuery = '';
  List<EasynewsResult> _results = const [];
  _UsenetSort _sort = _UsenetSort.newest;

  @override
  void initState() {
    super.initState();
    // Controller: when the menu hands focus back to this tab, land on the
    // search box (or the Connect button before a login exists).
    _contentFocus = () {
      if (!mounted) return;
      if (_configured) {
        _queryFocus.requestFocus();
      } else {
        _setupFocus.requestFocus();
      }
    };
    MainPageBridge.registerTvContentFocusHandler(9, _contentFocus);
    EasynewsService.instance.changes.addListener(_refreshConfigured);
    _refreshConfigured();
  }

  @override
  void dispose() {
    EasynewsService.instance.changes.removeListener(_refreshConfigured);
    MainPageBridge.unregisterTvContentFocusHandler(9, _contentFocus);
    _setupFocus.dispose();
    _preview.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshConfigured() async {
    final configured = await EasynewsService.instance.isConfigured();
    final headers = configured
        ? await EasynewsService.instance.imageHeaders()
        : const <String, String>{};
    if (!mounted) return;
    _imageHeaders = headers;
    setState(() {
      _configured = configured;
      _checking = false;
      if (!configured) _results = const [];
    });
  }

  Future<void> _openSettings() async {
    await pushSettingsPage<bool>(context, const EasynewsSettingsPage());
    await _refreshConfigured();
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (text.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
      _lastQuery = text;
      _page = 1;
      _hasMore = false;
    });
    try {
      final found = await EasynewsService.instance.search(text, type: _type);
      if (!mounted) return;
      setState(() {
        _results = _sorted(found, _sort);
        _hasMore = found.isNotEmpty;
        _searching = false;
      });
    } on EasynewsException catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = e.message;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = 'Search failed ($e)';
        _searching = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _searching || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final found = await EasynewsService.instance.search(
        _lastQuery,
        type: _type,
        page: next,
      );
      if (!mounted) return;
      final known = _results.map((r) => r.url).toSet();
      final fresh = found.where((r) => !known.contains(r.url)).toList();
      setState(() {
        _page = next;
        _results = _sorted([..._results, ...fresh], _sort);
        _hasMore = fresh.isNotEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  List<EasynewsResult> _sorted(List<EasynewsResult> list, _UsenetSort sort) {
    final copy = List<EasynewsResult>.of(list);
    switch (sort) {
      case _UsenetSort.newest:
        copy.sort((a, b) {
          final x = a.published?.millisecondsSinceEpoch ?? 0;
          final y = b.published?.millisecondsSinceEpoch ?? 0;
          return y.compareTo(x);
        });
      case _UsenetSort.biggest:
        copy.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case _UsenetSort.name:
        copy.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return copy;
  }

  void _setSort(_UsenetSort sort) {
    setState(() {
      _sort = sort;
      _results = _sorted(_results, sort);
    });
  }

  Future<void> _play(EasynewsResult result) async {
    if (_opening) return;
    setState(() => _opening = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final playback = await EasynewsService.instance.preparePlayback(result);
      if (!mounted) return;
      setState(() => _opening = false);
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: playback.url,
          title: result.title,
          subtitle: result.sizeLabel.isEmpty ? null : result.sizeLabel,
          httpHeaders: playback.headers,
        ),
      );
    } on EasynewsException catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      messenger?.showSnackBar(SnackBar(content: Text('Could not open it ($e)')));
    }
  }

  void _showDetails(EasynewsResult r) {
    final link = r.url.replaceFirst(RegExp(r'//[^/@]*@'), '//');
    final text = 'Name: ${r.title}\nLink: $link\n'
        'Picture tries:\n${r.thumbnailCandidates.join('\n')}';
    final testResult = ValueNotifier<String>('');
    Future<void> runTest() async {
      testResult.value = 'Testing…';
      final out = StringBuffer();
      for (final url in r.thumbnailCandidates) {
        for (final withReferer in [false, true]) {
          try {
            final res = await http
                .get(
                  Uri.parse(url),
                  headers: withReferer ? _imageHeaders : const {},
                )
                .timeout(const Duration(seconds: 10));
            out.writeln(
              '${res.statusCode} ${res.headers['content-type'] ?? ''} '
              '${res.bodyBytes.length}B  ${withReferer ? 'referer' : 'plain'}'
              '  ${url.split('/').last}',
            );
          } catch (e) {
            out.writeln('error $e  ${url.split('/').last}');
          }
        }
      }
      testResult.value = out.toString();
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Result details'),
        content: SingleChildScrollView(
          child: ValueListenableBuilder<String>(
            valueListenable: testResult,
            builder: (_, result, __) =>
                SelectableText(result.isEmpty ? text : '$text\n\n$result'),
          ),
        ),
        actions: [
          TextButton(onPressed: runTest, child: const Text('Test pictures')),
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: testResult.value.isEmpty
                      ? text
                      : '$text\n\n${testResult.value}',
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(88, 20, 32, 16),
          child: _checking
              ? const Center(child: CircularProgressIndicator())
              : !_configured
              ? _buildSetup(scheme)
              : _buildSearch(scheme),
        ),
      ),
    );
  }

  Widget _buildSetup(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.newspaper_rounded, size: 56, color: Colors.white70),
            const SizedBox(height: 16),
            const Text(
              'Usenet',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connect your Easynews account to search it here, like on the '
              'Easynews website, and play what you find.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.45, color: Colors.white70),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              autofocus: true,
              focusNode: _setupFocus,
              onPressed: _openSettings,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Connect Easynews'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Usenet',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TvTextField(
                controller: _query,
                focusNode: _queryFocus,
                hintText: 'Search Easynews (movie, show, S01E02…)',
                prefixIcon: const Icon(Icons.search_rounded),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search_rounded),
              label: Text(_searching ? 'Searching…' : 'Search'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const SizedBox(width: 4),
            const Text('Sort:', style: TextStyle(color: Colors.white70)),
            ChoiceChip(
              label: const Text('Newest'),
              selected: _sort == _UsenetSort.newest,
              onSelected: (_) => _setSort(_UsenetSort.newest),
            ),
            ChoiceChip(
              label: const Text('Biggest'),
              selected: _sort == _UsenetSort.biggest,
              onSelected: (_) => _setSort(_UsenetSort.biggest),
            ),
            ChoiceChip(
              label: const Text('Name'),
              selected: _sort == _UsenetSort.name,
              onSelected: (_) => _setSort(_UsenetSort.name),
            ),
            TextButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Account'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_opening) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 15),
        ),
      );
    }
    if (_lastQuery.isEmpty) {
      return const Center(
        child: Text(
          'Type something and press Search.',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'Nothing found for "$_lastQuery".',
          style: const TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }
    final list = ListView.builder(
      itemCount: _results.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Load more'),
                    ),
            ),
          );
        }
        final r = _results[index];
        final info = [
          if (r.sizeLabel.isNotEmpty) r.sizeLabel,
          if (r.published != null) _dateLabel(r.published),
          if (r.extension.isNotEmpty) r.extension.replaceFirst('.', '').toUpperCase(),
        ].join('  ·  ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: MouseRegion(
            onEnter: (_) => _preview.value = r,
            onExit: (_) {
              if (_preview.value?.url == r.url) _preview.value = null;
            },
            child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            tileColor: Colors.white.withValues(alpha: 0.06),
            focusColor: Colors.white.withValues(alpha: 0.18),
            hoverColor: Colors.white.withValues(alpha: 0.12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 96,
                height: 54,
                child: _ResultThumb(
                  urls: r.thumbnailCandidates,
                  headers: _imageHeaders,
                ),
              ),
            ),
            title: Text(
              r.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            subtitle: Text(
              info,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            onTap: () => unawaited(_play(r)),
            onLongPress: () => _showDetails(r),
            onFocusChange: (focused) {
              if (focused) {
                _preview.value = r;
              } else if (_preview.value?.url == r.url) {
                _preview.value = null;
              }
            },
          ),
          ),
        );
      },
    );
    // Big, clear picture of whatever you hover or focus (mouse or controller).
    return Stack(
      children: [
        list,
        Positioned(
          right: 12,
          top: 4,
          child: IgnorePointer(
            child: ValueListenableBuilder<EasynewsResult?>(
              valueListenable: _preview,
              builder: (context, item, _) {
                if (item == null || MediaQuery.sizeOf(context).width < 900) {
                  return const SizedBox.shrink();
                }
                return Container(
                  width: 480,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xEE0B0F1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 2,
                          child: ColoredBox(
                            color: Colors.black,
                            child: _ResultThumb(
                              key: ValueKey(item.url),
                              urls: item.thumbnailCandidates,
                              headers: _imageHeaders,
                              cacheWidth: 960,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows a result's picture, trying each possible address until one loads.
class _ResultThumb extends StatefulWidget {
  const _ResultThumb({
    super.key,
    required this.urls,
    required this.headers,
    this.cacheWidth = 192,
    this.fit = BoxFit.cover,
  });

  final List<String> urls;
  final Map<String, String> headers;
  final int cacheWidth;
  final BoxFit fit;

  @override
  State<_ResultThumb> createState() => _ResultThumbState();
}

class _ResultThumbState extends State<_ResultThumb> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.play_circle_outline_rounded, size: 30);
    if (_index >= widget.urls.length) return fallback;
    final url = widget.urls[_index];
    return Image.network(
      url,
      key: ValueKey(url),
      headers: widget.headers,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _index++);
        });
        return fallback;
      },
    );
  }
}
