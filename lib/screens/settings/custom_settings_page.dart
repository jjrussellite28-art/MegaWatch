import 'package:flutter/material.dart';

import '../credits_page.dart';
import 'custom_switches.dart';

/// Everything MegaWatch adds on top of Debrify, grouped by what it does. Each
/// switch also sits in its natural settings page (Engines, Metadata, Playback).
class CustomSettingsPage extends StatelessWidget {
  const CustomSettingsPage({super.key});

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom (made by the creator)')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Features added in MegaWatch that are not in the original app.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          _heading('SEARCH & SAFETY'),
          const SafetyLockSwitch(),
          _heading('METADATA'),
          const WatchOrderSwitch(),
          _heading('PLAYER'),
          const SeekLockSwitch(),
          _heading('ABOUT'),
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
