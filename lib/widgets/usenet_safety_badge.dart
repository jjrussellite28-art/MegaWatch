import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Small status pill shown while an Easynews (Usenet) video plays: tells you
/// whether the connection to Easynews is encrypted (HTTPS).
///
/// Appears with the player controls, and pops up by itself for a few seconds
/// whenever the status changes.
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

enum _Level { secure, bad }

class _UsenetSafetyBadgeState extends State<UsenetSafetyBadge> {
  Timer? _flash;
  bool _flashing = false;
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    _lastKey = _level.name;
  }

  @override
  void didUpdateWidget(UsenetSafetyBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _level.name;
    if (key != _lastKey) {
      _lastKey = key;
      _flash?.cancel();
      setState(() => _flashing = true);
      _flash = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _flashing = false);
      });
    }
  }

  @override
  void dispose() {
    _flash?.cancel();
    super.dispose();
  }

  _Level get _level =>
      (widget.url ?? '').startsWith('https://') ? _Level.secure : _Level.bad;

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
      case _Level.secure:
        color = const Color(0xFF3DDC84);
        title = 'Secure';
        detail = 'Encrypted connection to Easynews';
      case _Level.bad:
        color = const Color(0xFFFF5C6C);
        title = 'Not encrypted';
        detail = 'This link is not secure';
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
