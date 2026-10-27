import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';

/// Safety lock for torrent-style search engines.
///
/// Engines only run when a debrid service (Real-Debrid, TorBox, PikPak) is
/// connected. (VPN detection was removed: it got in the way of debrid.)
/// The switch in Settings can turn the lock off.
class SafetyGateService {
  SafetyGateService._();

  static const _prefKey = 'safety_lock_enabled';

  static const blockedMessage =
      'Search is paused for your safety: no debrid '
      'service (TorBox, Real-Debrid, PikPak) is connected, so your IP address '
      'could be exposed. Connect a debrid service, then '
      'search again.';

  static const torrentAddonMessage =
      'WARNING: This would expose your IP address. Some add-on results are '
      'raw torrents, and they only unlock when a debrid service (TorBox, '
      'Real-Debrid or PikPak) is set up in the app. We are not letting you '
      'proceed with those. Secure (https) direct links still work.';

  /// Set when torrent add-on results were hidden; the app shows a warning.
  static final ValueNotifier<int> blockedNotice = ValueNotifier<int>(0);

  /// True when raw-torrent add-on results must be hidden (no debrid set up).
  static Future<bool> torrentAddonsLocked() async {
    if (!await isEnabled()) return false;
    return !await hasDebrid();
  }

  static const _strictKey = 'safety_strict_enabled';

  /// Strict mode (on by default): the moment something would expose your IP,
  /// the app shows a warning and closes. Safe links still play.
  static Future<bool> strictEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_strictKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setStrict(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_strictKey, value);
  }

  /// Bumped whenever a search that would expose the IP was stopped.
  static final ValueNotifier<int> exposureAttempt = ValueNotifier<int>(0);

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  static Future<bool> hasDebrid() async {
    try {
      return await StorageService.hasRealDebridCredential() ||
          await StorageService.hasTorboxCredential() ||
          await StorageService.hasPikPakCredential();
    } catch (_) {
      return false;
    }
  }

  /// null when searching is allowed, otherwise the message to show.
  static Future<String?> blockReason({bool report = true}) async {
    if (!await isEnabled()) return null;
    if (await hasDebrid()) return null;
    if (report) exposureAttempt.value++;
    return blockedMessage;
  }
}
