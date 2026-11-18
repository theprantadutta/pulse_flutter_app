import '../router_probe.dart';

/// What a native driver can do with a router after signing in. The Router
/// screen shows only these; everything else stays in "Full router settings".
enum RouterFeature { overview, clients, wifi, guestWifi, reboot, portForwards, dhcpLeases, internet }

/// Changes a driver can make, as the ids the backend verifies per router
/// model + firmware ("Did it work?" reports). Reads need no verification: a
/// read either parses or the section isn't shown.
abstract final class RouterActions {
  static const wifiToggle = 'wifi.toggle';
  static const wifiEdit = 'wifi.edit';
  static const guestToggle = 'guest.toggle';
  static const guestEdit = 'guest.edit';
  static const iotToggle = 'iot.toggle';
  static const iotEdit = 'iot.edit';
  static const reboot = 'system.reboot';

  /// Switch the internet connection type (Dynamic IP → PPPoE…).
  static const internetType = 'internet.type';

  /// Change the settings of the current connection type.
  static const internetEdit = 'internet.edit';

  static String toggle(WifiNetwork n) => switch (n.kind) {
    WifiKind.main => wifiToggle,
    WifiKind.guest => guestToggle,
    WifiKind.iot => iotToggle,
  };

  static String edit(WifiNetwork n) => switch (n.kind) {
    WifiKind.main => wifiEdit,
    WifiKind.guest => guestEdit,
    WifiKind.iot => iotEdit,
  };

  /// What the person sees in "Did it work?" and in the capability list.
  static String label(String id) => switch (id) {
    wifiToggle => 'Wi-Fi on / off',
    wifiEdit => 'Wi-Fi name and password',
    guestToggle => 'Guest network on / off',
    guestEdit => 'Guest name and password',
    iotToggle => 'Smart-home network on / off',
    iotEdit => 'Smart-home name and password',
    reboot => 'Restart the router',
    internetType => 'Internet connection type',
    internetEdit => 'Internet connection settings',
    _ => id,
  };
}

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
    this.internet,
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

  /// Whether the router says it is online (null when it doesn't say).
  final bool? internet;
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
    this.kind,
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

  /// The router's guess at the device type ("phone", "laptop", "tv"…), lower case.
  final String? kind;
}

enum WifiBand { b24, b5, b6 }

/// The main network, the guest network, or a separate smart-home (IoT) one.
enum WifiKind { main, guest, iot }

/// One Wi-Fi network (a band, main or guest).
class WifiNetwork {
  const WifiNetwork({
    required this.id,
    required this.band,
    this.kind = WifiKind.main,
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
  final WifiKind kind;
  final bool? enabled;
  final String? ssid;
  final String? password;
  final bool? hidden;
  final String? security;
  final int? channel;

  bool get guest => kind == WifiKind.guest;

  String get kindLabel => switch (kind) {
    WifiKind.main => 'Wi-Fi',
    WifiKind.guest => 'Guest network',
    WifiKind.iot => 'Smart-home network',
  };

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

/// How the router connects to the internet provider.
enum WanType {
  dhcp('Dynamic IP', 'The provider hands out an address automatically. Most cable and fibre lines.'),
  static('Static IP', 'A fixed address, mask, gateway and DNS from your provider.'),
  pppoe('PPPoE', 'A username and password from your provider. Common on DSL and fibre.'),
  l2tp('L2TP', 'A username, password and server from your provider.'),
  pptp('PPTP', 'A username, password and server from your provider.');

  const WanType(this.label, this.help);
  final String label;
  final String help;

  bool get usesLogin => this == pppoe || this == l2tp || this == pptp;
  bool get usesServer => this == l2tp || this == pptp;
}

/// One connection type's settings. Null fields are unknown (on read) or
/// unchanged (on write).
class WanSettings {
  const WanSettings({
    required this.type,
    this.ip,
    this.netmask,
    this.gateway,
    this.dns1,
    this.dns2,
    this.manualDns,
    this.mtu,
    this.hostname,
    this.username,
    this.password,
    this.server,
    this.secondaryStatic,
  });

  final WanType type;

  /// Static IP: the address. L2TP/PPTP with a static secondary connection:
  /// the address on the provider's side.
  final String? ip;
  final String? netmask;
  final String? gateway;
  final String? dns1;
  final String? dns2;

  /// Use [dns1]/[dns2] instead of the provider's DNS (Dynamic IP, PPPoE, L2TP, PPTP).
  final bool? manualDns;
  final int? mtu;
  final String? hostname;
  final String? username;
  final String? password;

  /// L2TP/PPTP server address or name.
  final String? server;

  /// L2TP/PPTP: the secondary connection uses a static address.
  final bool? secondaryStatic;
}

/// The router's internet connection: the types it offers, the active one,
/// each type's saved settings, and what it has now.
class WanConfig {
  const WanConfig({
    required this.available,
    required this.current,
    this.settings = const {},
    this.connected,
    this.ip,
    this.gateway,
    this.dns = const [],
  });

  final List<WanType> available;
  final WanType? current;
  final Map<WanType, WanSettings> settings;
  final bool? connected;

  /// The address the router has on the provider's side right now.
  final String? ip;
  final String? gateway;
  final List<String> dns;
}

/// A native client for one router family. One session at a time; call
/// [signIn] first and [signOut] when done (many routers allow a single admin).
abstract class RouterDriver {
  Set<RouterFeature> get features;

  /// The [RouterActions] this driver implements. The UI still offers each
  /// one only as verified or "Try it" (see RouterCapabilities).
  Set<String> get actions;

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

  /// The internet connection (RouterFeature.internet).
  Future<WanConfig> wan();

  /// Saves [settings] and makes its type the active one. Fields left null
  /// keep the router's current values for that type.
  Future<void> setWan(WanSettings settings);
}
