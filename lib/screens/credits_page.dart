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
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'MegaWatch is free, open-source software (AGPL-3.0) made by '
              'jjrussellite28-art. If you are credited here and want something '
              'changed or removed, open an issue on GitHub and it will be '
              'handled promptly.',
            ),
          ),
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
          Card(
            child: ListTile(
              title: const Text('Source code'),
              subtitle: const Text(
                'github.com/jjrussellite28-art/megawatch (AGPL-3.0)',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => launchUrl(
                Uri.parse('https://github.com/jjrussellite28-art/megawatch'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Open-source licences'),
              subtitle: const Text('Licences of the libraries MegaWatch uses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'MegaWatch',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
