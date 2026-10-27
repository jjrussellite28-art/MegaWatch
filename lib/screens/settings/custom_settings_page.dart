import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/safety_gate_service.dart';
import '../../services/watch_order_service.dart';
import '../credits_page.dart';

/// Everything MegaWatch adds on top of Debrify lives here, so the original
/// settings stay as they were.
class CustomSettingsPage extends StatefulWidget {
  const CustomSettingsPage({super.key});

  @override
  State<CustomSettingsPage> createState() => _CustomSettingsPageState();
}

class _CustomSettingsPageState extends State<CustomSettingsPage> {
  bool _safetyOn = true;
  bool _watchOrderOn = true;
  bool _seekLockOn = false;

  @override
  void initState() {
    super.initState();
    SafetyGateService.isEnabled().then((v) {
      if (mounted) setState(() => _safetyOn = v);
    });
    WatchOrderService.instance.isEnabled().then((v) {
      if (mounted) setState(() => _watchOrderOn = v);
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => _seekLockOn = p.getBool('player_seek_lock') ?? false);
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom (made by the creator)')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Features added in MegaWatch that are not in the original app.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          SwitchListTile(
            title: const Text('Safety lock for search'),
            subtitle: const Text(
              'Torrent search engines only run when a debrid service '
              '(TorBox, Real-Debrid, PikPak) is connected or a VPN is detected, '
              'so your IP is not exposed. Raw-torrent add-on results are hidden '
              'until a debrid service is set up. VPN detection is a best guess '
              'from your network adapters.',
            ),
            value: _safetyOn,
            onChanged: (v) async {
              setState(() => _safetyOn = v);
              await SafetyGateService.setEnabled(v);
            },
          ),
          SwitchListTile(
            title: const Text('Watch order'),
            subtitle: const Text(
              'Shows what to watch before and next in a franchise, its full '
              'timeline and the story-order switch. Data from the Watch Order '
              'add-on by u/demon-myth.',
            ),
            value: _watchOrderOn,
            onChanged: (v) async {
              setState(() => _watchOrderOn = v);
              await WatchOrderService.instance.setEnabled(v);
            },
          ),
          SwitchListTile(
            title: const Text('Player seek lock'),
            subtitle: const Text(
              'Ignores stray remote or keyboard fast-forward and swipe-seeks. '
              'You can also press L in the player. Off by default.',
            ),
            value: _seekLockOn,
            onChanged: (v) async {
              setState(() => _seekLockOn = v);
              try {
                final p = await SharedPreferences.getInstance();
                await p.setBool('player_seek_lock', v);
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('Credits'),
            subtitle: const Text('Debrify, u/demon-myth, TMDB and more'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CreditsPage()),
            ),
          ),
        ],
      ),
    );
  }
}
