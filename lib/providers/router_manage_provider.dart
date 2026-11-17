import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../services/net/router/drivers/router_driver.dart';
import '../services/net/router/drivers/tplink_driver.dart';
import '../services/net/router/router_probe.dart';
import 'router_provider.dart';

/// The native driver for this router, when Pulse has one.
RouterDriver? driverFor(RouterProfile? p) {
  if (p == null) return null;
  return switch (p.brand) {
    RouterBrand.tplink => TplinkDriver(p.gateway),
    _ => null,
  };
}

/// Everything a signed-in driver read from the router.
@immutable
class RouterManaged {
  const RouterManaged({
    required this.features,
    this.overview,
    this.clients = const [],
    this.wifi = const [],
    this.forwards = const [],
    this.at,
  });

  final Set<RouterFeature> features;
  final RouterOverview? overview;
  final List<RouterClient> clients;
  final List<WifiNetwork> wifi;
  final List<RouterForward> forwards;
  final DateTime? at;

  RouterManaged copyWith({
    RouterOverview? overview,
    List<RouterClient>? clients,
    List<WifiNetwork>? wifi,
    List<RouterForward>? forwards,
    DateTime? at,
  }) => RouterManaged(
    features: features,
    overview: overview ?? this.overview,
    clients: clients ?? this.clients,
    wifi: wifi ?? this.wifi,
    forwards: forwards ?? this.forwards,
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
    final driver = driverFor(profile);
    if (driver == null || login == null) return null;
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
    ]);
    return RouterManaged(
      features: d.features,
      overview: r[0] as RouterOverview?,
      clients: (r[1] as List<RouterClient>?) ?? const [],
      wifi: (r[2] as List<WifiNetwork>?) ?? const [],
      forwards: (r[3] as List<RouterForward>?) ?? const [],
      at: DateTime.now(),
    );
  }

  Future<void> _refreshClients() async {
    final d = _driver, cur = state.value;
    if (d == null || cur == null) return;
    try {
      final c = await d.clients();
      state = AsyncData(cur.copyWith(clients: c, at: DateTime.now()));
    } on Object {
      // Keep the last list; a full refresh shows errors.
    }
  }

  Future<void> refresh() async {
    final d = _driver;
    if (d == null) return ref.invalidateSelf();
    state = await AsyncValue.guard(() => _loadAll(d));
  }

  /// Applies a Wi-Fi change, then re-reads the networks.
  Future<void> setWifi(WifiNetwork n, {bool? enabled, String? ssid, String? password}) async {
    final d = _driver, cur = state.value;
    if (d == null || cur == null) return;
    await d.setWifi(n, enabled: enabled, ssid: ssid, password: password);
    try {
      final w = await d.wifi();
      state = AsyncData((state.value ?? cur).copyWith(wifi: w));
    } on Object {
      // The change went through; the list refreshes next time.
    }
  }

  Future<void> reboot() async {
    final d = _driver;
    if (d == null) return;
    _timer?.cancel();
    await d.reboot();
  }
}
