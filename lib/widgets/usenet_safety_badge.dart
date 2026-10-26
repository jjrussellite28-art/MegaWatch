import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Small status pill shown while an Easynews (Usenet) video plays: tells you
/// whether the connection is encrypted and whether a VPN looks switched on.
///
/// Appears with the player controls, and pops up by itself for a few seconds
/// whenever the status changes (for example when a VPN turns on or off).
class UsenetSafetyBadge extends StatefulWidget {
  const UsenetSafetyBadge({
    super.key,
    required this.url,
    required this.controlsVisible,
  });

  /// Address of the video being played (null when something else plays).
  final String? url;
  final ValueListenable<bool> controlsVisible;

  static bool isEasynews(String? url) {
    final host = Uri.tryParse(url ?? '')?.host.toLowerCase() ?? '';
    return host == 'easynews.com' || host.endsWith('.easynews.com');
  }

  @override
  State<UsenetSafetyBadge> createState() => _UsenetSafetyBadgeState();
}

enum _Level { protected, ok, bad }

class _UsenetSafetyBadgeState extends State<UsenetSafetyBadge> {
  Timer? _poll;
  Timer? _flash;
  bool _vpn = false;
  bool _flashing = false;
  String _lastKey = '';

  static const _vpnWords = [
    'vpn', 'wireguard', 'openvpn', 'nord', 'proton', 'mullvad', 'surfshark',
    'expressvpn', 'express', 'cyberghost', 'windscribe', 'private internet',
    'pia', 'tap-windows', 'wintun', 'ipvanish', 'hotspot shield',
  ];

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _flash?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    var found = false;
    try {
      final interfaces = await NetworkInterface.list();
      for (final i in interfaces) {
        final name = i.name.toLowerCase();
        if (_vpnWords.any(name.contains)) {
          found = true;
          break;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _vpn = found);
    _noteChange();
  }

  _Level get _level {
    final secure = (widget.url ?? '').startsWith('https://');
    if (!secure) return _Level.bad;
    return _vpn ? _Level.protected : _Level.ok;
  }

  void _noteChange() {
    final key = '${_level.name}';
    if (_lastKey.isNotEmpty && key != _lastKey) {
      _flash?.cancel();
      setState(() => _flashing = true);
      _flash = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _flashing = false);
      });
    }
    _lastKey = key;
  }

  @override
  Widget build(BuildContext context) {
    if (!UsenetSafetyBadge.isEasynews(widget.url)) {
      return const SizedBox.shrink();
    }
    final level = _level;
    final Color color;
    final String title;
    final String detail;
    switch (level) {
      case _Level.protected:
        color = const Color(0xFF3DDC84);
        title = 'Protected';
        detail = 'Encrypted connection · VPN detected';
      case _Level.ok:
        color = const Color(0xFFFFC857);
        title = 'Encrypted';
        detail = 'Your provider cannot see the video · no VPN detected';
      case _Level.bad:
        color = const Color(0xFFFF5C6C);
        title = 'Not encrypted';
        detail = 'Your provider could see this connection';
    }
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controlsVisible,
      builder: (context, controlsShown, _) {
        final visible = controlsShown || _flashing;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 72, right: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 15, color: color),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Usenet · $title',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            detail,
                            style: TextStyle(color: color, fontSize: 12),
                          ),
                        ],
                      ),
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
