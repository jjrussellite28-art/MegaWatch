import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';

/// Safety lock for torrent-style search engines.
///
/// Engines only run when a VPN looks active OR a debrid service
/// (Real-Debrid, TorBox, PikPak) is connected. VPN detection is a best-effort
/// check of the network adapters, so the switch in Settings can turn it off.
class SafetyGateService {
  SafetyGateService._();

  static const _prefKey = 'safety_lock_enabled';

  static const blockedMessage =
      'Search is paused for your safety: no VPN was detected and no debrid '
      'service (TorBox, Real-Debrid, PikPak) is connected, so your IP address '
      'could be exposed. Turn on your VPN or connect a debrid service, then '
      'search again.';

  static const torrentAddonMessage =
      'WARNING: This would expose your IP address. Some add-on results are '
      'raw torrents, and they only unlock when a debrid service (TorBox, '
      'Real-Debrid or PikPak) is set up in the app. We are not letting you '
      'proceed with those. Direct links and protected streams still work.';

  /// Set when torrent add-on results were hidden; the app shows a warning.
  static final ValueNotifier<int> blockedNotice = ValueNotifier<int>(0);

  /// True when raw-torrent add-on results must be hidden (no debrid set up).
  static Future<bool> torrentAddonsLocked() async {
    if (!await isEnabled()) return false;
    return !await hasDebrid();
  }

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

  static final _vpnNames = RegExp(
    r'(vpn|tun\d|tap\d|wg\d|wireguard|nord|proton|mullvad|express|surfshark|'
    r'cyberghost|pia|private internet|windscribe|ipvanish|openvpn|ppp|'
    r'wintun|tailscale-exit|hotspot shield|tunnelbear|hide\.me)',
    caseSensitive: false,
  );

  static Future<bool> vpnDetected() async {
    try {
      final list = await NetworkInterface.list(includeLoopback: false);
      for (final i in list) {
        if (_vpnNames.hasMatch(i.name) && i.addresses.isNotEmpty) return true;
      }
    } catch (_) {}
    return false;
  }

  /// null when searching is allowed, otherwise the message to show.
  static Future<String?> blockReason() async {
    if (!await isEnabled()) return null;
    if (await hasDebrid()) return null;
    if (await vpnDetected()) return null;
    return blockedMessage;
  }
}
