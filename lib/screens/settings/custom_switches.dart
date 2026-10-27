import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/safety_gate_service.dart';
import '../../services/watch_order_service.dart';

/// The three MegaWatch switches. Each one loads and saves itself, so the same
/// switch can sit in its natural settings page and on the Custom page.
class _CustomSwitch extends StatefulWidget {
  const _CustomSwitch({
    required this.title,
    required this.subtitle,
    required this.load,
    required this.save,
  });
  final String title, subtitle;
  final Future<bool> Function() load;
  final Future<void> Function(bool) save;

  @override
  State<_CustomSwitch> createState() => _CustomSwitchState();
}

class _CustomSwitchState extends State<_CustomSwitch> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    widget.load().then((v) {
      if (mounted) setState(() => _value = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(widget.title),
      subtitle: Text(widget.subtitle),
      value: _value ?? false,
      onChanged: _value == null
          ? null
          : (v) async {
              setState(() => _value = v);
              await widget.save(v);
            },
    );
  }
}

class SafetyLockSwitch extends StatelessWidget {
  const SafetyLockSwitch({super.key});
  @override
  Widget build(BuildContext context) => _CustomSwitch(
    title: 'Safety lock for search (custom)',
    subtitle:
        'Torrent search engines only run when a debrid service (TorBox, '
        'Real-Debrid, PikPak) is connected or a VPN is detected, so your IP is '
        'not exposed. Raw-torrent add-on results stay hidden until a debrid '
        'service is set up. VPN detection is a best guess.',
    load: SafetyGateService.isEnabled,
    save: SafetyGateService.setEnabled,
  );
}

class StrictModeSwitch extends StatelessWidget {
  const StrictModeSwitch({super.key});
  @override
  Widget build(BuildContext context) => _CustomSwitch(
    title: 'Strict mode (custom)',
    subtitle:
        'If something would expose your IP address, the app shows a warning '
        'and closes right away. Safe links still play. On by default.',
    load: SafetyGateService.strictEnabled,
    save: SafetyGateService.setStrict,
  );
}

class WatchOrderSwitch extends StatelessWidget {
  const WatchOrderSwitch({super.key});
  @override
  Widget build(BuildContext context) => _CustomSwitch(
    title: 'Watch order (custom)',
    subtitle:
        'Shows what to watch before and next in a franchise, its timeline and '
        'the story-order switch. Data from the Watch Order add-on by '
        'u/demon-myth.',
    load: () => WatchOrderService.instance.isEnabled(),
    save: (v) => WatchOrderService.instance.setEnabled(v),
  );
}

class SeekLockSwitch extends StatelessWidget {
  const SeekLockSwitch({super.key});
  @override
  Widget build(BuildContext context) => _CustomSwitch(
    title: 'Player seek lock (custom)',
    subtitle:
        'Ignores stray remote or keyboard fast-forward and swipe-seeks. You '
        'can also press L in the player. Off by default.',
    load: () async {
      try {
        final p = await SharedPreferences.getInstance();
        return p.getBool('player_seek_lock') ?? false;
      } catch (_) {
        return false;
      }
    },
    save: (v) async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setBool('player_seek_lock', v);
      } catch (_) {}
    },
  );
}
