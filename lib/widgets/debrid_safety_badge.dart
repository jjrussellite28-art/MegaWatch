import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'usenet_safety_badge.dart';

/// Small status pill on the player (shown with the controls): says whether
/// the video is coming through a debrid service over an encrypted link.
class DebridSafetyBadge extends StatelessWidget {
  const DebridSafetyBadge({
    super.key,
    required this.url,
    required this.controlsVisible,
    this.hidden = false,
  });

  final String? url;
  final ValueListenable<bool> controlsVisible;

  /// True for live TV and anything else the badge doesn't apply to.
  final bool hidden;

  static const _services = <String, List<String>>{
    'Real-Debrid': ['real-debrid', 'rdeb.io', 'rdb.so'],
    'TorBox': ['torbox', 'tb-cdn'],
    'AllDebrid': ['alldebrid', 'debrid.it'],
    'Premiumize': ['premiumize'],
    'PikPak': ['pikpak'],
  };

  static String? serviceFor(String host) {
    for (final e in _services.entries) {
      if (e.value.any(host.contains)) return e.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    if (hidden ||
        uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        UsenetSafetyBadge.isEasynews(url)) {
      return const SizedBox.shrink();
    }
    final host = uri.host.toLowerCase();
    final isLocal =
        host.isEmpty ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host.startsWith('192.168.') ||
        host.startsWith('10.');
    if (isLocal) return const SizedBox.shrink();

    final service = serviceFor(host);
    final secure = uri.scheme == 'https';
    final Color color;
    final String title;
    final String detail;
    if (service != null && secure) {
      color = const Color(0xFF3DDC84);
      title = '$service connected';
      detail = 'Safe: streaming through debrid, encrypted';
    } else if (service != null) {
      color = const Color(0xFFFF5C6C);
      title = '$service connected';
      detail = 'Link is not encrypted: your ISP can see it';
    } else if (secure) {
      color = const Color(0xFFFFB020);
      title = 'Not through debrid';
      detail = 'Direct link, encrypted. The site can see your IP';
    } else {
      color = const Color(0xFFFF5C6C);
      title = 'Not safe';
      detail = 'Not encrypted: your ISP can see what you watch';
    }
    return ValueListenableBuilder<bool>(
      valueListenable: controlsVisible,
      builder: (context, shown, _) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
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
                    Icon(Icons.shield_rounded, size: 15, color: color),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
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
      ),
    );
  }
}
