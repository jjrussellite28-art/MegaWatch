import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Thank-yous and licences for the people and projects MegaWatch builds on.
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  static const _entries = <(String, String, String?)>[
    (
      'Debrify',
      'MegaWatch is based on Debrify, created by Varun Salian and contributors, '
          'used under the AGPL-3.0 licence. MegaWatch is an independent fork and is '
          'not made or endorsed by the Debrify project.',
      'https://github.com/varunsalian/debrify',
    ),
    (
      'u/demon-myth',
      'Watch order and franchise timelines come from the public "Watch Order" '
          'Stremio add-on by u/demon-myth. MegaWatch only asks the add-on questions; '
          'none of its code or data is bundled.',
      'https://www.reddit.com/user/demon-myth/',
    ),
    (
      'RobbdeezeNutz',
      'Ideas for live sports, IPTV portals, direct-link streaming and other features, from the RobbdeezeNutz fork of Debrify.',
      null,
    ),
    (
      'TMDB',
      'This product uses the TMDB API but is not endorsed or certified by TMDB.',
      'https://www.themoviedb.org',
    ),
    (
      'Cinemeta / Stremio',
      'Movie and show details come from the public Stremio Cinemeta catalogue.',
      'https://www.stremio.com',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credits')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final e in _entries)
            Card(
              child: ListTile(
                title: Text(e.$1),
                subtitle: Text(e.$2),
                trailing: e.$3 == null ? null : const Icon(Icons.open_in_new),
                onTap: e.$3 == null
                    ? null
                    : () => launchUrl(
                          Uri.parse(e.$3!),
                          mode: LaunchMode.externalApplication,
                        ),
              ),
            ),
        ],
      ),
    );
  }
}
