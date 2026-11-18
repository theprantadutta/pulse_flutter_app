import 'dart:async';

import '../router_probe.dart';
import 'router_driver.dart';
import 'tplink_driver.dart';

/// One way Pulse can sign in to and manage a router. Drivers are chosen by
/// probing the router (no credentials sent), not by its brand: the same web
/// API often ships on several brands, and brand detection can miss. The brand
/// hint only decides which drivers are probed first.
class RouterDriverType {
  const RouterDriverType({required this.id, required this.probe, required this.create, this.hints = const {}});

  /// Stable id (stored nowhere user-visible).
  final String id;

  /// True when the router at the host answers this driver's protocol.
  final Future<bool> Function(String host) probe;
  final RouterDriver Function(String host) create;

  /// Brands that usually speak this protocol: probed first for them.
  final Set<RouterBrand> hints;
}

/// Every driver Pulse has. Add new protocols here; the Router screen picks
/// them up automatically and shows only the features each one declares.
final kRouterDrivers = <RouterDriverType>[
  RouterDriverType(
    id: 'luci-encrypted-web',
    probe: TplinkDriver.supports,
    create: TplinkDriver.new,
    hints: const {RouterBrand.tplink},
  ),
];

/// The first driver whose probe the router at [p] answers, brand hints first.
/// Null when Pulse can't manage this router natively (it still gets UPnP and
/// the router's own page).
Future<RouterDriverType?> detectRouterDriver(RouterProfile p) async {
  if (p.brand.cloudOnly) return null;
  final ordered = [
    ...kRouterDrivers.where((d) => d.hints.contains(p.brand)),
    ...kRouterDrivers.where((d) => !d.hints.contains(p.brand)),
  ];
  for (final d in ordered) {
    try {
      if (await d.probe(p.gateway).timeout(const Duration(seconds: 8))) return d;
    } on Object {
      // Not this protocol (or no answer): try the next one.
    }
  }
  return null;
}
