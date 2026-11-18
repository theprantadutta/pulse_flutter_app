import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../services/net/router/drivers/driver_registry.dart';
import '../services/net/router/drivers/router_driver.dart';
import '../services/net/router/verification.dart';
import 'router_provider.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// The driver that can sign in to the router on this network, found by
/// probing it (see kRouterDrivers). Null when Pulse can't manage it natively.
final routerDriverTypeProvider = FutureProvider<RouterDriverType?>((ref) async {
  final p = await ref.watch(routerProfileProvider.future);
  return p == null ? null : detectRouterDriver(p);
});

final routerVerificationProvider = Provider<RouterVerification>(
  (ref) => RouterVerification(ref.watch(sharedPreferencesProvider)),
);

/// The signed-in router's driver + model + firmware, once its overview is read.
final routerIdentityProvider = Provider.autoDispose<RouterIdentity?>((ref) {
  final type = ref.watch(routerDriverTypeProvider).value;
  final o = ref.watch(
    routerManageProvider.select((m) {
      final o = m.value?.overview;
      return o == null ? null : (o.model, o.hardwareVersion, o.firmware);
    }),
  );
  if (type == null || o == null) return null;
  final (model, hardware, firmware) = o;
  if (model == null || firmware == null) return null;
  return RouterIdentity(driver: type.id, model: model, hardware: hardware ?? '', firmware: firmware);
});

/// Which of the driver's actions are verified, "Try it" or hidden for this
/// router model + firmware. Without an identity (model or firmware unknown)
/// every action is "Try it" and answers can't be shared.
final routerCapabilitiesProvider = FutureProvider.autoDispose<RouterCapabilities?>((ref) async {
  final id = ref.watch(routerIdentityProvider);
  if (id == null) return null;
  return ref.watch(routerVerificationProvider).load(id);
});

/// Everything a signed-in driver read from the router.
@immutable
class RouterManaged {
  const RouterManaged({
    required this.features,
    this.actions = const {},
    this.overview,
    this.clients = const [],
    this.wifi = const [],
    this.forwards = const [],
    this.wan,
    this.at,
  });

  final Set<RouterFeature> features;

  /// The [RouterActions] the driver implements.
  final Set<String> actions;
  final RouterOverview? overview;
  final List<RouterClient> clients;
  final List<WifiNetwork> wifi;
  final List<RouterForward> forwards;

  /// The internet connection (null when the router doesn't expose it).
  final WanConfig? wan;
  final DateTime? at;

  RouterManaged copyWith({
    RouterOverview? overview,
    List<RouterClient>? clients,
    List<WifiNetwork>? wifi,
    List<RouterForward>? forwards,
    WanConfig? wan,
    DateTime? at,
  }) => RouterManaged(
    features: features,
    actions: actions,
    overview: overview ?? this.overview,
    clients: clients ?? this.clients,
    wifi: wifi ?? this.wifi,
    forwards: forwards ?? this.forwards,
    wan: wan ?? this.wan,
    at: at ?? this.at,
  );
}

/// Signs in with the saved login while a Router screen is open, loads the
/// router's status, devices, Wi-Fi and rules, refreshes devices every 15 s,
/// and signs out when the screen closes (routers often allow one admin).
/// Null when there is no driver for this router or no saved login.
final routerManageProvider = AsyncNotifierProvider.autoDispose<RouterManager, RouterManaged?>(RouterManager.new);

class RouterManager extends AsyncNotifier<RouterManaged?> {
  RouterDriver? _driver;
  Timer? _timer;

  @override
  Future<RouterManaged?> build() async {
    final profile = await ref.watch(routerProfileProvider.future);
    final login = await ref.watch(routerCredentialProvider.future);
    final type = await ref.watch(routerDriverTypeProvider.future);
    if (profile == null || type == null || login == null) return null;
    if (ref.watch(routerSignedOutProvider).contains(profile.id)) return null;
    final driver = type.create(profile.gateway);
    _driver = driver;
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(driver.signOut());
    });
    await driver.signIn(login);
    final m = await _loadAll(driver);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshClients());
    return m;
  }

  Future<RouterManaged> _loadAll(RouterDriver d) async {
    Future<T?> opt<T>(RouterFeature f, Future<T> Function() load) async {
      if (!d.features.contains(f)) return null;
      try {
        return await load();
      } on RouterDriverException catch (e) {
        if (e.kind == RouterErrorKind.network) rethrow;
        return null; // this model lacks the page; the rest still shows
      }
    }

    final r = await Future.wait<Object?>([
      opt(RouterFeature.overview, d.overview),
      opt(RouterFeature.clients, d.clients),
      opt(RouterFeature.wifi, d.wifi),
      opt(RouterFeature.portForwards, d.forwards),
      opt(RouterFeature.internet, d.wan),
    ]);
    return RouterManaged(
      features: d.features,
      actions: d.actions,
      overview: r[0] as RouterOverview?,
      clients: (r[1] as List<RouterClient>?) ?? const [],
      wifi: (r[2] as List<WifiNetwork>?) ?? const [],
      forwards: (r[3] as List<RouterForward>?) ?? const [],
      wan: r[4] as WanConfig?,
      at: DateTime.now(),
    );
  }

  Future<void> _refreshClients() async {
    final d = _driver, cur = state.value;
    if (d == null || cur == null) return;
    try {
      final c = await d.clients();
      // Build on the state as it is now: a change made while this ran (Wi-Fi,
      // internet) must not be overwritten with the copy from before it.
      state = AsyncData((state.value ?? cur).copyWith(clients: c, at: DateTime.now()));
    } on Object {
      // Keep the last list; a full refresh shows errors.
    }
  }

  Future<void> refresh() async {
    final d = _driver;
    if (d == null) return ref.invalidateSelf();
    state = await AsyncValue.guard(() => _loadAll(d));
  }

  /// Applies a Wi-Fi change, then reads the network back from the router.
  /// Returns whether the router now reports what was asked (null when the
  /// read-back failed, e.g. this device was on the network just turned off).
  Future<bool?> setWifi(WifiNetwork n, {bool? enabled, String? ssid, String? password}) async {
    final d = _driver, cur = state.value;
    if (d == null || cur == null) throw const RouterDriverException(RouterErrorKind.unexpected, 'not signed in');
    await d.setWifi(n, enabled: enabled, ssid: ssid, password: password);
    // Radios restart after a change; give the router a moment.
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      final w = await d.wifi();
      state = AsyncData((state.value ?? cur).copyWith(wifi: w));
      final now = w.where((x) => x.id == n.id).firstOrNull;
      if (now == null) return false;
      return (enabled == null || now.enabled == enabled) &&
          (ssid == null || now.ssid == ssid) &&
          (password == null || now.password == null || now.password == password);
    } on Object {
      return null;
    }
  }

  /// Saves internet settings, then reads them back until the router reports
  /// the new type and values (it reconnects meanwhile). True when it does,
  /// false when it reports something else, null when it couldn't be read.
  Future<bool?> setWan(WanSettings w) async {
    final d = _driver, cur = state.value;
    if (d == null || cur == null) throw const RouterDriverException(RouterErrorKind.unexpected, 'not signed in');
    await d.setWan(w);
    bool? result;
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final c = await d.wan();
        state = AsyncData((state.value ?? cur).copyWith(wan: c));
        result = c.current == w.type && wanMatches(c.settings[w.type], w);
        if (result) return true;
      } on Object {
        // The router may be busy reconnecting; try again.
      }
    }
    return result;
  }

  Future<void> reboot() async {
    final d = _driver;
    if (d == null) return;
    _timer?.cancel();
    await d.reboot();
  }
}

/// Whether the router's saved [read] has every value [asked] set (passwords
/// are skipped: some firmware never returns them).
bool wanMatches(WanSettings? read, WanSettings asked) {
  if (read == null) return false;
  bool same(Object? want, Object? got) => want == null || want == got;
  return same(asked.ip, read.ip) &&
      same(asked.netmask, read.netmask) &&
      same(asked.gateway, read.gateway) &&
      same(asked.dns1, read.dns1) &&
      same(asked.mtu, read.mtu) &&
      same(asked.hostname, read.hostname) &&
      same(asked.username, read.username) &&
      same(asked.server, read.server) &&
      same(asked.manualDns, read.manualDns) &&
      same(asked.secondaryStatic, read.secondaryStatic);
}
