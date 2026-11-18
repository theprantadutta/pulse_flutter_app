import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../presentations/screens/ping/ping_configure.dart' show gatewayProvider;
import '../services/net/router/router_probe.dart';
import '../services/net/router/upnp_igd.dart';

/// The router on the current network, re-detected when the gateway changes.
/// Null when there is no router (offline, mobile data).
final routerProfileProvider = FutureProvider<RouterProfile?>((ref) async {
  final gateway = await ref.watch(gatewayProvider.future);
  if (gateway == null || gateway.isEmpty) return null;
  return RouterProbe.probe(gateway);
});

/// One reading of the router's internet status, with throughput worked out
/// from the change in its byte counters since the previous reading.
@immutable
class RouterLive {
  const RouterLive({required this.status, this.downBps, this.upBps, this.history = const []});
  final IgdStatus status;

  /// Bits per second since the previous poll; null on the first reading or
  /// when the router has no byte counters.
  final double? downBps;
  final double? upBps;

  /// Recent (down, up) bit rates, oldest first.
  final List<(double, double)> history;
}

/// Polls the router's UPnP status every 3 s while a Router screen listens.
final routerLiveProvider = StreamProvider.autoDispose<RouterLive>((ref) async* {
  final profile = await ref.watch(routerProfileProvider.future);
  final igd = profile?.igd;
  if (igd == null) return;
  IgdStatus? prev;
  DateTime? prevAt;
  final history = <(double, double)>[];
  const period = Duration(seconds: 3);
  // 32-bit counters wrap at 4 GiB; a drop smaller than that is a wrap, a
  // bigger one is a counter reset (router reboot).
  double? rate(int? now, int? before, double secs) {
    if (now == null || before == null || secs <= 0) return null;
    var delta = now - before;
    if (delta < 0) delta += 0x100000000;
    if (delta < 0 || delta > 0x100000000) return null;
    return delta * 8 / secs;
  }

  while (true) {
    final now = DateTime.now();
    IgdStatus s;
    try {
      s = await UpnpIgd.status(igd);
    } on Object {
      s = const IgdStatus();
    }
    double? down, up;
    if (prev != null && prevAt != null) {
      final secs = now.difference(prevAt).inMilliseconds / 1000;
      down = rate(s.bytesReceived, prev.bytesReceived, secs);
      up = rate(s.bytesSent, prev.bytesSent, secs);
      if (down != null || up != null) {
        history.add((down ?? 0, up ?? 0));
        if (history.length > 40) history.removeAt(0);
      }
    }
    prev = s;
    prevAt = now;
    yield RouterLive(status: s, downBps: down, upBps: up, history: List.of(history));
    await Future<void>.delayed(period);
  }
});

/// The router's UPnP port mappings; refresh with `ref.invalidate`.
final portMappingsProvider = FutureProvider.autoDispose<List<PortMapping>>((ref) async {
  final igd = (await ref.watch(routerProfileProvider.future))?.igd;
  if (igd == null || !igd.canMap) return const [];
  return UpnpIgd.mappings(igd);
});

/// Logins used without saving ("Remember on this device" off): kept in memory
/// until Pulse closes, by router id.
final sessionRouterLoginProvider = NotifierProvider<SessionRouterLogins, Map<String, RouterCredential>>(
  SessionRouterLogins.new,
);

class SessionRouterLogins extends Notifier<Map<String, RouterCredential>> {
  @override
  Map<String, RouterCredential> build() => const {};

  void put(String routerId, RouterCredential c) => state = {...state, routerId: c};

  void remove(String routerId) => state = {...state}..remove(routerId);
}

/// The login for the current router: this session's, else the saved one.
final routerCredentialProvider = FutureProvider.autoDispose<RouterCredential?>((ref) async {
  final p = await ref.watch(routerProfileProvider.future);
  if (p == null) return null;
  return ref.watch(sessionRouterLoginProvider)[p.id] ?? await RouterVault.read(p.id);
});

/// Whether the current router's login is saved in the keystore (vs this session only).
final routerLoginSavedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final p = await ref.watch(routerProfileProvider.future);
  ref.watch(routerCredentialProvider);
  return p != null && await RouterVault.read(p.id) != null;
});
