import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pulse_api.dart';

/// What Pulse counts. Must match `EVENTS` in pulse-rust-api `src/usage.rs`
/// (the server drops anything else).
enum UsageEvent {
  active('active'),
  pingStart('ping.start'),
  traceRun('trace.run'),
  portsScan('ports.scan'),
  speedRun('speed.run'),
  lossRun('loss.run'),
  lanScan('lan.scan'),
  geoLookup('geo.lookup'),
  monitorAdd('monitor.add'),
  alertAdd('alert.add'),
  wolSend('wol.send'),
  routerSignIn('router.signin'),
  routerWifi('router.wifi'),
  routerWan('router.wan'),
  routerReboot('router.reboot'),
  share('share'),
  export('export');

  const UsageEvent(this.id);

  final String id;
}

/// Anonymous usage counts (Settings › Privacy › "Share anonymous usage
/// counts", on by default).
///
/// Pulse keeps a tally per local day on the device, e.g. `{"2026-11-25":
/// {"trace.run": 2}}`, and once a day sends the finished days to its own
/// server, which only adds them to daily totals. Nothing identifies the
/// device: no install id, no device or advertising id, no hosts, addresses,
/// names or results, and the server neither logs nor stores IP addresses. The
/// daily `active` count carries a coarse "installed how long ago" bucket
/// (worked out here) so the totals show whether people come back.
///
/// Call [UsageCounts.count] from anywhere; it does nothing until [init] ran or
/// while the setting is off.
class UsageCounts {
  UsageCounts(this._prefs, {PulseApi? api, required this.version, String? platform, DateTime Function()? now})
    : _api = api ?? PulseApi(),
      platform = platform ?? Platform.operatingSystem,
      _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final PulseApi _api;
  final String version;
  final String platform;
  final DateTime Function() _now;

  static const _tallyKey = 'usage.tally';
  static const _firstDayKey = 'usage.first_day';

  /// Days kept on the device if sending keeps failing.
  static const _keepDays = 10;

  static UsageCounts? _instance;
  static bool _enabled = false;

  /// Sets up the shared instance and sends finished days.
  static Future<void> init(UsageCounts counts, {required bool enabled, DateTime? installed}) async {
    _instance = counts;
    counts._rememberFirstDay(installed);
    await setEnabled(enabled);
  }

  /// Follows the setting: off clears what's kept and stops counting.
  static Future<void> setEnabled(bool on) async {
    _enabled = on;
    final c = _instance;
    if (c == null) return;
    if (!on) {
      await c._prefs.remove(_tallyKey);
      return;
    }
    c._markActive();
    await c.flush();
  }

  /// Adds one to [event] for today.
  static void count(UsageEvent event) {
    final c = _instance;
    if (!_enabled || c == null || event == UsageEvent.active) return;
    c._add(event.id);
  }

  /// Counts today as active (once a day) and sends finished days; called when
  /// Pulse comes back to the foreground.
  static Future<void> resumed() async {
    final c = _instance;
    if (!_enabled || c == null) return;
    c._markActive();
    await c.flush();
  }

  @visibleForTesting
  static void reset() {
    _instance = null;
    _enabled = false;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _today => _day(_now());

  Map<String, Map<String, int>> get tally {
    final raw = _prefs.getString(_tallyKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (day, events) => MapEntry(day, (events as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt()))),
      );
    } on Object {
      return {};
    }
  }

  void _save(Map<String, Map<String, int>> t) => _prefs.setString(_tallyKey, jsonEncode(t));

  void _add(String id, [int by = 1]) {
    final t = tally;
    final day = t.putIfAbsent(_today, () => {});
    day[id] = (day[id] ?? 0) + by;
    _save(t);
  }

  void _rememberFirstDay(DateTime? installed) {
    if (_prefs.getString(_firstDayKey) != null) return;
    _prefs.setString(_firstDayKey, _day(installed ?? _now()));
  }

  /// `active:<bucket>` once per day; the bucket is fixed when first counted.
  void _markActive() {
    final t = tally;
    final today = t[_today] ?? {};
    if (today.keys.any((k) => k.startsWith('active:'))) return;
    _add('active:${bucket()}');
  }

  /// Installed today, 1-6, 7-29 or 30+ days ago.
  @visibleForTesting
  String bucket() {
    final first = DateTime.tryParse(_prefs.getString(_firstDayKey) ?? '') ?? _now();
    final now = _now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(first.year, first.month, first.day)).inDays;
    return switch (days) {
      <= 0 => 'd0',
      < 7 => 'd1_6',
      < 30 => 'd7_29',
      _ => 'd30',
    };
  }

  /// Sends every finished day (not today, which is still counting). Days the
  /// server took are removed; very old days are dropped.
  Future<bool> flush() async {
    final t = tally;
    final today = _today;
    final oldest = _day(_now().subtract(const Duration(days: _keepDays)));
    t.removeWhere((day, _) => day.compareTo(oldest) < 0);
    final done = t.keys.where((d) => d.compareTo(today) < 0).toList();
    if (done.isEmpty || !_api.configured) {
      _save(t);
      return false;
    }
    final items = [
      for (final day in done)
        for (final e in t[day]!.entries)
          {
            'day': day,
            'event': e.key.startsWith('active:') ? 'active' : e.key,
            'count': e.key.startsWith('active:') ? 1 : e.value,
            'platform': platform,
            'version': version,
            if (e.key.startsWith('active:')) 'bucket': e.key.substring('active:'.length),
          },
    ];
    try {
      await _api.postJson('/api/v1/usage', {'items': items});
      done.forEach(t.remove);
      _save(t);
      return true;
    } on Object {
      _save(t);
      return false;
    }
  }
}
