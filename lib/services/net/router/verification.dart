import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../pulse_api.dart';

/// Which router a verdict is about: the driver plus the model and firmware
/// the router reports. Nothing that identifies the network or its owner.
@immutable
class RouterIdentity {
  const RouterIdentity({required this.driver, required this.model, required this.firmware, this.hardware = ''});

  final String driver;
  final String model;
  final String hardware;
  final String firmware;

  String get key => '$driver|$model|$firmware';

  Map<String, String> toJson() => {'driver': driver, 'model': model, 'hardware': hardware, 'firmware': firmware};

  @override
  bool operator ==(Object other) => other is RouterIdentity && other.key == key && other.hardware == hardware;

  @override
  int get hashCode => Object.hash(key, hardware);
}

/// How far an action is trusted on one router model + firmware.
enum ActionTrust {
  /// Enough people (or the developer) confirmed it works: offered plainly.
  verified,

  /// Nobody confirmed it yet: offered as "Try it", read back, then "Did it work?".
  untested,

  /// Most people said it fails: hidden (Full router settings still has it).
  failing,
}

/// The verdicts for one router, plus this install's own answers.
@immutable
class RouterCapabilities {
  const RouterCapabilities({required this.identity, this.remote = const {}, this.mine = const {}, this.fresh = false});

  final RouterIdentity identity;

  /// Backend verdicts by action id.
  final Map<String, ActionTrust> remote;

  /// This install's latest answers ("worked" true/false) by action id.
  final Map<String, bool> mine;

  /// False when the server couldn't be reached (verdicts come from the cache).
  final bool fresh;

  ActionTrust trust(String action) => remote[action] ?? ActionTrust.untested;

  /// Whether to show [action] at all.
  bool offers(String action) => trust(action) != ActionTrust.failing;

  /// Whether to ask "Did it work?" after running [action].
  bool asks(String action) => trust(action) != ActionTrust.verified && !mine.containsKey(action);
}

/// Crowd-sourced verification through pulse-rust-api (`/api/v1/router/*`).
/// Each install has a random id (stored locally, hashed again on the server)
/// so the server counts people, not taps.
class RouterVerification {
  RouterVerification(this._prefs, {PulseApi? api}) : _api = api ?? PulseApi();

  final SharedPreferences _prefs;
  final PulseApi _api;

  static const _installKey = 'router.verify.install';
  static String _cacheKey(RouterIdentity id) => 'router.verify.cache.${id.key}';
  static String _mineKey(RouterIdentity id) => 'router.verify.mine.${id.key}';

  /// Signs reports from the owner's debug builds so they count immediately.
  /// The key is only read in debug builds, so release builds never contain it.
  static String get _devKey => kDebugMode ? const String.fromEnvironment('PULSE_DEV_KEY') : '';

  String get install {
    final existing = _prefs.getString(_installKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _prefs.setString(_installKey, id);
    return id;
  }

  Map<String, bool> mine(RouterIdentity id) {
    final raw = _prefs.getString(_mineKey(id));
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v == true));
    } on Object {
      return const {};
    }
  }

  /// Cached verdicts first; then the server's, which replace the cache.
  Future<RouterCapabilities> load(RouterIdentity id) async {
    final cached = _decode(_prefs.getString(_cacheKey(id)));
    if (!_api.configured) return RouterCapabilities(identity: id, remote: cached, mine: mine(id));
    try {
      final r = await _api.postJson('/api/v1/router/capabilities', {
        'driver': id.driver,
        'model': id.model,
        'firmware': id.firmware,
      });
      final features = r['features'];
      final map = features is Map ? features.map((k, v) => MapEntry('$k', '$v')) : const <String, String>{};
      await _prefs.setString(_cacheKey(id), jsonEncode(map));
      return RouterCapabilities(identity: id, remote: _decode(jsonEncode(map)), mine: mine(id), fresh: true);
    } on Object {
      return RouterCapabilities(identity: id, remote: cached, mine: mine(id));
    }
  }

  /// Records this install's answer and sends it (best effort; the answer is
  /// kept locally either way so Pulse doesn't ask again).
  Future<bool> report(RouterIdentity id, String action, {required bool worked}) async {
    await _prefs.setString(_mineKey(id), jsonEncode({...mine(id), action: worked}));
    if (!_api.configured) return false;
    final inst = install;
    final dev = _devKey;
    try {
      await _api.postJson(
        '/api/v1/router/report',
        {...id.toJson(), 'feature': action, 'worked': worked, 'install': inst},
        headers: {
          if (dev.isNotEmpty) 'x-pulse-dev': Hmac(sha256, utf8.encode(dev)).convert(utf8.encode(inst)).toString(),
        },
      );
      return true;
    } on Object {
      return false;
    }
  }

  static Map<String, ActionTrust> _decode(String? raw) {
    if (raw == null) return const {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: switch (e.value) {
            'verified' => ActionTrust.verified,
            'failing' => ActionTrust.failing,
            _ => ActionTrust.untested,
          },
      };
    } on Object {
      return const {};
    }
  }
}
