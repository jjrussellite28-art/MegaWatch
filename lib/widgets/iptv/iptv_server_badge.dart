import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../services/iptv_mirrors.dart';

/// Small status pill for live IPTV: which server is playing, how fast it
/// answers, and a one-press button to swap to the next backup server.
///
/// Shown while the player controls are visible, and stays on screen whenever
/// the active server looks slow or down so the problem (and the fix) is
/// never hidden.
class IptvServerBadge extends StatefulWidget {
  const IptvServerBadge({
    super.key,
    required this.channelUrl,
    required this.controlsVisible,
    required this.onSwitched,
  });

  /// URL of the channel being played, or null when nothing live is playing.
  final String? channelUrl;
  final ValueListenable<bool> controlsVisible;

  /// Called after the active server changed, so the player can reopen the
  /// channel on the new server.
  final VoidCallback onSwitched;

  @override
  State<IptvServerBadge> createState() => _IptvServerBadgeState();
}

class _IptvServerBadgeState extends State<IptvServerBadge> {
  IptvServerHealth? _health;
  String? _checkedServer;
  Timer? _timer;
  bool _switching = false;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    IptvMirrors.instance.load();
    IptvMirrors.instance.changes.addListener(_onMirrorsChanged);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _probe());
    _probe();
  }

  @override
  void didUpdateWidget(IptvServerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelUrl != widget.channelUrl) _probe();
  }

  @override
  void dispose() {
    _timer?.cancel();
    IptvMirrors.instance.changes.removeListener(_onMirrorsChanged);
    super.dispose();
  }

  void _onMirrorsChanged() {
    if (mounted) _probe();
  }

  IptvStreamAddress? get _address {
    final url = widget.channelUrl;
    if (url == null || url.isEmpty) return null;
    return IptvMirrors.instance.addressOf(url);
  }

  Future<void> _probe() async {
    final address = _address;
    if (address == null) {
      if (_health != null && mounted) setState(() => _health = null);
      return;
    }
    final ticket = ++_ticket;
    final result = await IptvMirrors.check(
      address.server,
      address.username,
      address.password,
    );
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _health = result;
      _checkedServer = address.server;
    });
  }

  Future<void> _switch(IptvStreamAddress address) async {
    if (_switching) return;
    setState(() => _switching = true);
    await IptvMirrors.instance.switchNext(address.primary);
    if (!mounted) return;
    setState(() {
      _switching = false;
      _health = null;
    });
    widget.onSwitched();
    unawaited(_probe());
  }

  Color _color(IptvServerHealth? health) {
    if (health == null) return Colors.white54;
    if (!health.online) return const Color(0xFFFF5C6C);
    switch (health.label) {
      case 'Fast':
        return const Color(0xFF3DDC84);
      case 'OK':
        return const Color(0xFFFFC857);
      default:
        return const Color(0xFFFF9F43);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = _address;
    if (address == null) return const SizedBox.shrink();
    final mirrors = IptvMirrors.instance;
    final count = mirrors.serverCount(address.primary);
    final position = mirrors.activeIndex(address.primary) + 1;
    final health = _checkedServer == address.server ? _health : null;
    final trouble = health != null && (!health.online || health.label == 'Slow');

    return ValueListenableBuilder<bool>(
      valueListenable: widget.controlsVisible,
      builder: (context, controlsShown, _) {
        final visible = controlsShown || trouble;
        final host = Uri.tryParse(address.server)?.host ?? address.server;
        final String status;
        if (health == null) {
          status = 'Checking…';
        } else if (!health.online) {
          status = 'Down (${health.error ?? 'no answer'})';
        } else {
          status = '${health.latencyMs} ms · ${health.label}';
        }
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 72, right: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 11, color: _color(health)),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            count > 1
                                ? 'Server $position of $count · $host'
                                : host,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            status,
                            style: TextStyle(
                              color: _color(health),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (count > 1) ...[
                        const SizedBox(width: 10),
                        TextButton.icon(
                          onPressed: _switching
                              ? null
                              : () => _switch(address),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Switch (M)'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
