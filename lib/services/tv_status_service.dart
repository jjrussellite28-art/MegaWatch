import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../models/stremio_addon.dart';
import 'tmdb_metadata_repository.dart';

/// Live production status of a TV show (Returning Series, Canceled, Ended,
/// In Production, Planned) from TMDB. Cached for a few hours, so a show that
/// gets revived shows its new status the next time its row loads.
class TvStatusService {
  TvStatusService._();
  static final instance = TvStatusService._();

  static const _ttl = Duration(hours: 6);
  final Map<String, ({String? status, DateTime at})> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};

  Future<String?> statusFor(String imdbId) {
    final hit = _cache[imdbId];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return Future.value(hit.status);
    }
    return _inFlight[imdbId] ??= _load(imdbId).whenComplete(
      () => _inFlight.remove(imdbId),
    );
  }

  Future<String?> _load(String imdbId) async {
    final repo = TmdbMetadataRepository.instance;
    if (!repo.configured) return null;
    try {
      final identity = await repo.identify(
        StremioMeta(id: imdbId, imdbId: imdbId, type: 'series', name: ''),
      );
      if (identity == null) return null;
      final data = await repo.details(
        identity,
        language: 'en-US',
        append: '',
      );
      final status = data['status']?.toString();
      _cache[imdbId] = (status: status, at: DateTime.now());
      return status;
    } catch (e) {
      debugPrint('TvStatusService: could not load status');
      return null;
    }
  }

  /// Badge text and colour for a TMDB status, or null when there is none.
  static ({String label, Color color})? badge(String? status) {
    switch (status) {
      case 'Returning Series':
        return (label: 'RUNNING', color: const Color(0xFF2E9E5B));
      case 'Canceled':
        return (label: 'CANCELED', color: const Color(0xFFD64545));
      case 'Ended':
        return (label: 'ENDED', color: const Color(0xFF6B7280));
      case 'In Production':
      case 'Planned':
      case 'Pilot':
        return (label: 'IN DEVELOPMENT', color: const Color(0xFFF08A24));
    }
    return null;
  }
}
