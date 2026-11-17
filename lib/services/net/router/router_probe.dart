import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'upnp_igd.dart';

/// Router families Pulse can recognise. Native control for a family arrives
/// with its driver; until then every router gets the admin page and UPnP.
enum RouterBrand {
  tplink('TP-Link', ['tp-link*', 'tplink*', 'archer', 'deco', 'mercusys*']),
  asus('ASUS', ['asus*', 'rt-ax*', 'rt-ac*', 'gt-ax*', 'zenwifi*']),
  netgear('NETGEAR', ['netgear*', 'nighthawk*', 'orbi', 'routerlogin*']),
  huawei('Huawei', ['huawei*', 'hilink*', 'honor router']),
  xiaomi('Xiaomi', ['xiaomi*', 'miwifi*', 'redmi router']),
  linksys('Linksys', ['linksys*', 'velop']),
  dlink('D-Link', ['d-link', 'dlink']),
  tenda('Tenda', ['tenda']),
  zte('ZTE', ['zte']),
  mikrotik('MikroTik', ['mikrotik*', 'routeros*', 'webfig']),
  openwrt('OpenWrt', ['openwrt*', 'luci', 'lede']),
  avm('FRITZ!Box', ['fritz*', 'avm']),
  ubiquiti('Ubiquiti', ['ubiquiti*', 'unifi*', 'edgerouter*', 'amplifi*']),
  synology('Synology', ['synology', 'srm']),
  keenetic('Keenetic', ['keenetic']),
  google('Google', ['google wifi', 'nest wifi', 'onhub']),
  eero('eero', ['eero']),
  sagemcom('Sagemcom', ['sagemcom']),
  technicolor('Technicolor', ['technicolor', 'vantiva']),
  arris('ARRIS', ['arris', 'surfboard']),
  nokia('Nokia', ['nokia']),
  unknown('Router', []);

  const RouterBrand(this.label, this.keywords);
  final String label;
  final List<String> keywords;

  static RouterBrand detect(Iterable<String?> texts) {
    final hay = texts.whereType<String>().join(' ').toLowerCase();
    // Whole words, so "deco" doesn't match "decoder"; a trailing * allows a
    // prefix ("asus*" matches "ASUSTeK", "rt-ax*" matches "RT-AX88U").
    bool has(String k) {
      final prefix = k.endsWith('*');
      final word = RegExp.escape(prefix ? k.substring(0, k.length - 1) : k);
      return RegExp('(^|[^a-z0-9])$word${prefix ? '' : r'($|[^a-z0-9])'}').hasMatch(hay);
    }
    for (final b in values) {
      if (b.keywords.any(has)) return b;
    }
    return unknown;
  }

  /// Mesh systems configured only through the vendor's cloud app.
  bool get cloudOnly => this == google || this == eero;
}

/// Ways Pulse can talk to the router (detected without logging in).
enum RouterProtocol {
  upnp('UPnP'),
  tr064('TR-064'),
  luci('OpenWrt LuCI'),
  routerOs('RouterOS'),
  https('HTTPS admin');

  const RouterProtocol(this.label);
  final String label;
}

/// What Pulse knows about the router on this network.
class RouterProfile {
  const RouterProfile({
    required this.gateway,
    required this.adminUrl,
    required this.brand,
    this.igd,
    this.pageTitle,
    this.server,
    this.protocols = const {},
  });

  final String gateway;

  /// Where its admin page lives (after redirects, or its presentation URL).
  final Uri adminUrl;
  final RouterBrand brand;
  final IgdDevice? igd;
  final String? pageTitle;
  final String? server;
  final Set<RouterProtocol> protocols;

  /// Stable per router: its UPnP UDN when it has one, else the gateway address.
  String get id => igd?.info.udn ?? 'gw-$gateway';

  /// "TP-Link Archer AX53", or "TP-Link router", or "Your router".
  String get name {
    final m = igd?.info.model;
    if (m != null && m.isNotEmpty) {
      return brand == RouterBrand.unknown || m.toLowerCase().contains(brand.label.toLowerCase().split(' ').first)
          ? m
          : '${brand.label} $m';
    }
    final title = pageTitle?.trim();
    if (brand != RouterBrand.unknown) return '${brand.label} router';
    if (title != null && title.isNotEmpty && title.length < 40) return title;
    return 'Your router';
  }
}

class RouterProbe {
  RouterProbe._();

  /// Looks at the router at [gateway]: UPnP description, admin page title and
  /// server header, and whether TR-064 / LuCI / RouterOS answer. Read-only and
  /// unauthenticated.
  static Future<RouterProfile> probe(String gateway) async {
    final results = await Future.wait<Object?>([
      UpnpIgd.find(gateway),
      _page(Uri.parse('http://$gateway/')),
      _status(Uri.parse('http://$gateway:49000/tr64desc.xml')),
      _page(Uri.parse('http://$gateway/cgi-bin/luci')),
      _status(Uri.parse('http://$gateway/rest/system/resource')),
    ]);
    final igd = results[0] as IgdDevice?;
    var page = results[1] as _Page?;
    final tr064 = results[2] == 200;
    final luci = (results[3] as _Page?)?.body.toLowerCase().contains('luci') ?? false;
    final rest = results[4] as int?;
    final https = page?.finalUrl.scheme == 'https';
    page ??= await _page(Uri.parse('https://$gateway/'));

    final brand = RouterBrand.detect([
      igd?.info.manufacturer,
      igd?.info.modelName,
      igd?.info.modelDescription,
      igd?.info.friendlyName,
      page?.title,
      page?.server,
      if (luci) 'luci',
      if (tr064) 'fritz',
      // RouterOS REST answers 401 with a realm, other routers 404.
      if (rest == 401 && (page?.server ?? '').toLowerCase().contains('mikrotik')) 'mikrotik',
    ]);
    final admin = igd?.presentation?.host == gateway
        ? igd!.presentation!
        : page?.finalUrl ?? Uri.parse('http://$gateway/');
    return RouterProfile(
      gateway: gateway,
      adminUrl: admin,
      brand: brand,
      igd: igd,
      pageTitle: page?.title,
      server: page?.server,
      protocols: {
        if (igd != null) RouterProtocol.upnp,
        if (tr064) RouterProtocol.tr064,
        // TP-Link and other vendor firmware is built on LuCI too; only call it
        // LuCI when it's OpenWrt itself.
        if (luci && brand == RouterBrand.openwrt) RouterProtocol.luci,
        if (brand == RouterBrand.mikrotik) RouterProtocol.routerOs,
        if (https || admin.scheme == 'https') RouterProtocol.https,
      },
    );
  }

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..badCertificateCallback = (_, _, _) => true; // routers use self-signed certificates

  static Future<int?> _status(Uri uri) async {
    final c = _client();
    try {
      final req = await c.getUrl(uri).timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>().timeout(const Duration(seconds: 2), onTimeout: () {});
      return res.statusCode;
    } on Object {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<_Page?> _page(Uri uri) async {
    final c = _client();
    try {
      final req = await c.getUrl(uri).timeout(const Duration(seconds: 3));
      req.followRedirects = true;
      final res = await req.close().timeout(const Duration(seconds: 4));
      final bytes = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 3))) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) break;
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      final title = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(body)?.group(1);
      var finalUrl = uri;
      for (final r in res.redirects) {
        finalUrl = finalUrl.resolveUri(r.location);
      }
      return _Page(finalUrl, title?.replaceAll(RegExp(r'\s+'), ' ').trim(), res.headers.value('server'), body);
    } on Object {
      return null;
    } finally {
      c.close(force: true);
    }
  }
}

class _Page {
  const _Page(this.finalUrl, this.title, this.server, this.body);
  final Uri finalUrl;
  final String? title;
  final String? server;
  final String body;
}

/// A saved router login.
class RouterCredential {
  const RouterCredential(this.username, this.password);
  final String username;
  final String password;

  Map<String, String> toJson() => {'u': username, 'p': password};
}

/// Router logins, kept only on this device in the OS keystore (Android
/// Keystore, iOS/macOS Keychain, Windows DPAPI). Never synced or sent anywhere
/// except to the router itself.
class RouterVault {
  RouterVault._();

  static const _storage = FlutterSecureStorage();
  static String _key(String routerId) => 'router.login.$routerId';

  static Future<RouterCredential?> read(String routerId) async {
    try {
      final raw = await _storage.read(key: _key(routerId));
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return RouterCredential('${j['u'] ?? ''}', '${j['p'] ?? ''}');
    } on Object {
      return null;
    }
  }

  static Future<void> write(String routerId, RouterCredential c) =>
      _storage.write(key: _key(routerId), value: jsonEncode(c.toJson()));

  static Future<void> delete(String routerId) => _storage.delete(key: _key(routerId));
}
