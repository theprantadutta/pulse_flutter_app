import '../router_probe.dart';

/// What a native driver can do with a router after signing in. The Router
/// screen shows only these; everything else stays in "Full router settings".
enum RouterFeature { overview, clients, wifi, guestWifi, reboot, portForwards, dhcpLeases }

/// Why a driver call failed, in terms the person can act on.
enum RouterErrorKind { wrongPassword, lockedOut, busy, unsupported, network, unexpected }

class RouterDriverException implements Exception {
  const RouterDriverException(this.kind, [this.detail]);
  final RouterErrorKind kind;
  final String? detail;

  String get message => switch (kind) {
    RouterErrorKind.wrongPassword => 'The router said the password is wrong.',
    RouterErrorKind.lockedOut => 'The router locked sign-in after failed attempts. Wait a few minutes and try again.',
    RouterErrorKind.busy =>
      'Someone else is signed in to the router (maybe its web page in a browser). Sign out there, or try again.',
    RouterErrorKind.unsupported => "Pulse can't sign in to this router model yet.",
    RouterErrorKind.network => "Couldn't reach the router${detail == null ? '' : ': $detail'}.",
    RouterErrorKind.unexpected =>
      'The router answered in a way Pulse did not expect${detail == null ? '' : ' ($detail)'}.',
  };

  @override
  String toString() => 'RouterDriverException($kind, $detail)';
}

/// The router's own view of itself.
class RouterOverview {
  const RouterOverview({
    this.model,
    this.hardwareVersion,
    this.firmware,
    this.wanIp,
    this.wanGateway,
    this.wanType,
    this.wanUptime,
    this.lanIp,
    this.wanMac,
    this.lanMac,
    this.cpu,
    this.memory,
    this.dhcpServer,
    this.ipv6,
  });

  final String? model;
  final String? hardwareVersion;
  final String? firmware;
  final String? wanIp;
  final String? wanGateway;

  /// "dhcp", "pppoe", "static"…
  final String? wanType;
  final Duration? wanUptime;
  final String? lanIp;
  final String? wanMac;
  final String? lanMac;

  /// 0–1.
  final double? cpu;
  final double? memory;
  final bool? dhcpServer;
  final String? ipv6;
}

enum ClientLink { wired, wifi2g, wifi5g, wifi6g, guest, unknown }

/// A device the router sees.
class RouterClient {
  const RouterClient({
    required this.mac,
    this.ip,
    this.name,
    this.link = ClientLink.unknown,
    this.guest = false,
    this.downBps,
    this.upBps,
    this.signal,
    this.online,
    this.trafficBytes,
  });

  final String mac;
  final String? ip;
  final String? name;
  final ClientLink link;
  final bool guest;
  final double? downBps;
  final double? upBps;

  /// dBm.
  final int? signal;
  final Duration? online;
  final int? trafficBytes;
}

enum WifiBand { b24, b5, b6 }

/// One Wi-Fi network (a band, main or guest).
class WifiNetwork {
  const WifiNetwork({
    required this.id,
    required this.band,
    required this.guest,
    this.enabled,
    this.ssid,
    this.password,
    this.hidden,
    this.security,
    this.channel,
  });

  /// Driver-specific id (TP-Link form name: wireless_2g, guest_5g…).
  final String id;
  final WifiBand band;
  final bool guest;
  final bool? enabled;
  final String? ssid;
  final String? password;
  final bool? hidden;
  final String? security;
  final int? channel;

  String get bandLabel => switch (band) {
    WifiBand.b24 => '2.4 GHz',
    WifiBand.b5 => '5 GHz',
    WifiBand.b6 => '6 GHz',
  };
}

/// A port forward ("virtual server") configured on the router.
class RouterForward {
  const RouterForward({
    required this.id,
    required this.name,
    required this.externalPort,
    required this.internalIp,
    required this.internalPort,
    required this.protocol,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String externalPort;
  final String internalIp;
  final String internalPort;

  /// "TCP", "UDP" or "ALL".
  final String protocol;
  final bool enabled;
}

class DhcpLease {
  const DhcpLease({required this.mac, required this.ip, this.name, this.expires});
  final String mac;
  final String ip;
  final String? name;
  final String? expires;
}

/// A native client for one router family. One session at a time; call
/// [signIn] first and [signOut] when done (many routers allow a single admin).
abstract class RouterDriver {
  Set<RouterFeature> get features;

  Future<void> signIn(RouterCredential login);
  Future<void> signOut();

  Future<RouterOverview> overview();
  Future<List<RouterClient>> clients();
  Future<List<WifiNetwork>> wifi();

  /// Changes only the given fields of [network].
  Future<void> setWifi(WifiNetwork network, {bool? enabled, String? ssid, String? password});
  Future<void> reboot();
  Future<List<RouterForward>> forwards();
  Future<List<DhcpLease>> leases();
}
