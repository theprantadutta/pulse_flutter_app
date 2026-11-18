import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart';

import '../router_probe.dart';
import 'router_driver.dart';

/// TP-Link Archer (LuCI-based web UI, e.g. Archer AX53, AX55, AX73, C6, C80)
/// — the same JSON API the router's own web page uses, behind its login.
///
/// The protocol is TP-Link's: the login password is RSA (PKCS#1 v1.5)
/// encrypted with a key the router publishes at `login?form=keys`; with the
/// AES-session variant every request body is AES-128-CBC encrypted with a
/// per-session key and carries an RSA "sign" (`k`/`i` key material on login,
/// then an MD5 of user+password and a sequence number) made with the
/// `login?form=auth` key. Newer firmware may also accept a plain RSA-only
/// login; both are tried. Implemented from observing the protocol; the
/// open-source tplinkrouterc6u project documents the same endpoints.
class TplinkDriver implements RouterDriver {
  TplinkDriver(this.host, {this.username = 'admin'});

  /// The router's address (the gateway).
  final String host;

  /// The web UI only asks for a password; the signature still hashes "admin".
  final String username;

  Uri? _base;
  String _stok = '';
  String? _sysauth;
  bool _encrypted = true;
  bool _jsonBodies = true;
  bool _sg = false;

  /// Over HTTPS the web UI sends plain form data (TLS protects it); firmware
  /// such as the Archer AX53 1.11 rejects the AES envelope there.
  bool _plain = false;
  TplinkSession? _session;
  RouterCredential? _login;

  static const _wifiForms = [
    'wireless_2g',
    'wireless_5g',
    'wireless_6g',
    'guest_2g',
    'guest_5g',
    'guest_6g',
    'iot_2g',
    'iot_5g',
    'iot_6g',
  ];

  @override
  Set<RouterFeature> get features => const {
    RouterFeature.overview,
    RouterFeature.clients,
    RouterFeature.wifi,
    RouterFeature.guestWifi,
    RouterFeature.reboot,
    RouterFeature.portForwards,
    RouterFeature.dhcpLeases,
  };

  @override
  Set<String> get actions => const {
    RouterActions.wifiToggle,
    RouterActions.wifiEdit,
    RouterActions.guestToggle,
    RouterActions.guestEdit,
    RouterActions.iotToggle,
    RouterActions.iotEdit,
    RouterActions.reboot,
  };

  /// Whether the router at [host] speaks this protocol (no credentials sent).
  static Future<bool> supports(String host) async {
    final d = TplinkDriver(host);
    try {
      await d._findBase();
      return true;
    } on Object {
      return false;
    }
  }

  // ---- HTTP ----

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    // TP-Link routers serve HTTPS with a self-signed certificate; trust it for
    // the router's own address only.
    ..badCertificateCallback = (cert, h, port) => h == host;

  Future<({int status, String body, List<Cookie> cookies})> _post(
    Uri url, {
    String body = '',
    String contentType = 'application/x-www-form-urlencoded',
  }) async {
    final c = _client();
    try {
      final req = await c.postUrl(url).timeout(const Duration(seconds: 8));
      final bytes = utf8.encode(body);
      req.headers
        ..set(HttpHeaders.contentTypeHeader, contentType)
        ..contentLength = bytes.length;
      // Current firmware answers "no such callback" without the web UI's Referer.
      if ((_sg || _plain) && _base != null) {
        req.headers.set(HttpHeaders.refererHeader, '$_base/webpages/index.html');
        if (_stok.isNotEmpty) req.headers.set('Origin', '$_base');
      }
      if (_sysauth != null) req.cookies.add(Cookie('sysauth', _sysauth!));
      req.add(bytes);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      return (status: res.statusCode, body: text, cookies: res.cookies);
    } on TimeoutException {
      throw const RouterDriverException(RouterErrorKind.network, 'timed out');
    } on SocketException catch (e) {
      throw RouterDriverException(RouterErrorKind.network, e.osError?.message ?? e.message);
    } on HandshakeException catch (e) {
      throw RouterDriverException(RouterErrorKind.network, e.message);
    } finally {
      c.close(force: true);
    }
  }

  Map<String, dynamic> _json(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
    } on Object {
      // fall through
    }
    throw RouterDriverException(RouterErrorKind.unexpected, body.length > 80 ? '${body.substring(0, 80)}…' : body);
  }

  /// HTTPS first (current firmware redirects there), then HTTP.
  Future<({BigInt n, BigInt e})> _findBase() async {
    Object? last;
    for (final scheme in const ['https', 'http']) {
      final base = Uri.parse('$scheme://$host');
      try {
        final r = await _post(base.replace(path: '/cgi-bin/luci/;stok=/login', query: 'form=keys&operation=read'));
        final j = _json(r.body);
        final pw = (j['data'] as Map?)?['password'];
        if (j['success'] == true && pw is List && pw.length >= 2) {
          _base = base;
          return (n: BigInt.parse('${pw[0]}', radix: 16), e: BigInt.parse('${pw[1]}', radix: 16));
        }
        last = const RouterDriverException(RouterErrorKind.unsupported);
      } on Object catch (e) {
        last = e;
      }
    }
    if (last is RouterDriverException && last.kind == RouterErrorKind.network) throw last;
    throw const RouterDriverException(RouterErrorKind.unsupported);
  }

  // ---- Sign-in ----

  @override
  Future<void> signIn(RouterCredential login) async {
    _login = login;
    _stok = '';
    _sysauth = null;
    _sg = false;
    _plain = false;
    final pwd = await _findBase();
    final encPwd = TplinkRsa.pkcs1Hex(login.password, pwd.n, pwd.e);

    // HTTPS: plain form login, exactly what the web page sends over TLS.
    if (_base!.scheme == 'https') {
      _plain = true;
      _encrypted = false;
      _jsonBodies = false;
      _session = null;
      final r = await _post(
        _url('login', 'login?form=login', stok: ''),
        body: 'password=$encPwd&operation=login&confirm=true',
      );
      final j = _json(r.body);
      if (_accept(j, r.cookies)) return;
      if (!'${j['errorcode'] ?? ''}'.contains('no such callback')) _loginError(j);
      _plain = false; // this firmware wants the encrypted envelope even over HTTPS
      _jsonBodies = true;
    }

    if (await _isSg()) return _signInSg(login, encPwd);

    // AES-session login (what the web UI does when `form=auth` exists).
    Map<String, dynamic>? auth;
    try {
      final r = await _post(_url('login', 'login?form=auth&operation=read', stok: ''));
      final j = _json(r.body);
      if (j['success'] == true) auth = j['data'] as Map<String, dynamic>?;
    } on RouterDriverException catch (e) {
      if (e.kind == RouterErrorKind.network) rethrow;
    }

    if (auth != null && auth['key'] is List && auth['seq'] != null) {
      final key = auth['key'] as List;
      _session = TplinkSession(
        n: BigInt.parse('${key[0]}', radix: 16),
        e: BigInt.parse('${key[1]}', radix: 16),
        seq: int.parse('${auth['seq']}'),
        hash: md5.convert(utf8.encode(username + login.password)).toString(),
      );
      _encrypted = true;
      final plain = 'operation=login&password=$encPwd&confirm=true';
      final r = await _post(_url('login', 'login?form=login', stok: ''), body: _session!.envelope(plain, login: true));
      if (r.status != 403) {
        final j = _decrypt(_json(r.body));
        if (_accept(j, r.cookies)) return;
        _loginError(j);
      }
    }

    // Plain RSA-only login (newer firmware).
    _encrypted = false;
    _session = null;
    final r = await _post(_url('login', 'login?form=login', stok: ''), body: 'operation=login&password=$encPwd');
    final j = _json(r.body);
    if (_accept(j, r.cookies)) return;
    _loginError(j);
  }

  /// SG-certified firmware ("SG CLS L1 STAGE2" / "EU CE RED") uses the SG
  /// scheme; the device config page says so without a login.
  Future<bool> _isSg() async {
    _sg = true; // send the web UI headers for this probe
    try {
      final r = await _post(_url('login', 'device_config?form=config', stok: ''), body: 'operation=read');
      final certs = ((_json(r.body)['data'] as Map?)?['certification'] as List?)?.map((e) => '$e') ?? const [];
      return certs.any((c) => c.contains('SG CLS L1') || c.contains('CE RED'));
    } on RouterDriverException catch (e) {
      if (e.kind == RouterErrorKind.network) rethrow;
      return false;
    } finally {
      _sg = false;
    }
  }

  Future<void> _signInSg(RouterCredential login, String encPwd) async {
    _sg = true;
    final r0 = await _post(_url('login', 'login?form=auth&operation=read', stok: ''));
    final auth = _json(r0.body)['data'];
    if (auth is! Map || auth['key'] is! List || auth['seq'] == null) {
      throw const RouterDriverException(RouterErrorKind.unsupported);
    }
    final key = auth['key'] as List;
    _session = TplinkSession(
      n: BigInt.parse('${key[0]}', radix: 16),
      e: BigInt.parse('${key[1]}', radix: 16),
      seq: int.parse('${auth['seq']}'),
      hash: sha256.convert(utf8.encode(username + login.password)).toString(),
      sg: true,
    );
    _encrypted = true;
    final r = await _post(
      _url('login', 'login?form=login', stok: ''),
      body: _session!.envelope('operation=login&password=$encPwd&confirm=true', login: true),
    );
    final j = _decrypt(_json(r.body));
    if (_accept(j, r.cookies)) return;
    _loginError(j);
  }

  bool _accept(Map<String, dynamic> j, List<Cookie> cookies) {
    final stok = (j['data'] as Map?)?['stok'];
    if (j['success'] != true || stok == null) return false;
    _stok = '$stok';
    _sysauth = cookies.where((c) => c.name == 'sysauth').firstOrNull?.value ?? _sysauth;
    return true;
  }

  Never _loginError(Map<String, dynamic> j) {
    final data = j['data'] is Map ? j['data'] as Map : const {};
    final code = '${j['errorcode'] ?? data['errorcode'] ?? ''}'.toLowerCase();
    final left = int.tryParse('${data['attemptsAllowed'] ?? ''}');
    if (code.contains('conflict') || code.contains('user')) throw const RouterDriverException(RouterErrorKind.busy);
    if (left == 0 || code.contains('exceed') || code.contains('lock')) {
      throw const RouterDriverException(RouterErrorKind.lockedOut);
    }
    if (code.contains('login') || code.contains('password') || left != null) {
      throw RouterDriverException(
        RouterErrorKind.wrongPassword,
        left == null ? null : '$left attempt${left == 1 ? '' : 's'} left',
      );
    }
    throw RouterDriverException(RouterErrorKind.unexpected, code.isEmpty ? null : code);
  }

  @override
  Future<void> signOut() async {
    if (_stok.isEmpty) return;
    try {
      await _request('admin/system?form=logout', {'operation': 'write'}, ignoreResponse: true);
    } on Object {
      // Best effort: the router also expires idle sessions.
    }
    _stok = '';
    _sysauth = null;
  }

  // ---- Requests ----

  Uri _url(String kind, String pathAndQuery, {String? stok}) {
    final i = pathAndQuery.indexOf('?');
    final path = i < 0 ? pathAndQuery : pathAndQuery.substring(0, i);
    final query = i < 0 ? null : pathAndQuery.substring(i + 1);
    return _base!.replace(path: '/cgi-bin/luci/;stok=${stok ?? _stok}/$path', query: query);
  }

  Map<String, dynamic> _decrypt(Map<String, dynamic> j) {
    if (!_encrypted || _session == null) return j;
    final d = j['data'];
    if (d is! String || d.isEmpty) return j;
    return _json(_session!.decrypt(d));
  }

  /// POSTs [params] to `admin/...`; returns the response's `data`. Re-signs
  /// in once when the session expired.
  Future<dynamic> _request(
    String path,
    Map<String, String> params, {
    bool ignoreResponse = false,
    bool retry = true,
  }) async {
    if (_stok.isEmpty) throw const RouterDriverException(RouterErrorKind.unexpected, 'not signed in');
    // The operation also goes in the URL (some firmware reads it there);
    // other values stay in the (encrypted) body, never in the URL.
    // SG firmware rejects a key present in both the URL and the body, and
    // takes form-encoded bodies.
    final op = params['operation'];
    final full = _sg || _plain || op == null || path.contains('operation=') ? path : '$path&operation=$op';
    final form = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final plain = _jsonBodies && !_sg && !_plain ? jsonEncode(params) : form;
    final body = _encrypted ? _session!.envelope(plain) : plain;
    final r = await _post(
      _url('admin', full),
      body: body,
      contentType: !_encrypted && _jsonBodies ? 'application/json' : 'application/x-www-form-urlencoded',
    );
    if (ignoreResponse) return null;
    if ((r.status == 403 || r.status == 401) && retry && _login != null) {
      await signIn(_login!);
      return _request(path, params, retry: false);
    }
    final j = _decrypt(_json(r.body));
    if (j['success'] == true) return j['data'];
    final code = '${j['errorcode'] ?? ''}'.toLowerCase();
    if ((code.contains('timeout') || code.contains('session') || code.contains('auth')) && retry && _login != null) {
      await signIn(_login!);
      return _request(path, params, retry: false);
    }
    // Older firmware wants form-encoded bodies: switch once and retry.
    if (_jsonBodies && !_sg && !_plain && retry) {
      _jsonBodies = false;
      try {
        return await _request(path, params, retry: false);
      } on RouterDriverException {
        _jsonBodies = true;
        rethrow;
      }
    }
    throw RouterDriverException(RouterErrorKind.unexpected, code.isEmpty ? path : '$path: $code');
  }

  /// One raw call (diagnostics and fixture recording only; the UI never uses it).
  @visibleForTesting
  Future<dynamic> rawCall(String path, String operation) => _request(path, {'operation': operation});

  Future<Map<String, dynamic>> _read(String path) async {
    final d = await _request(path, {'operation': 'read'});
    return d is Map<String, dynamic> ? d : const {};
  }

  Future<List<Map<String, dynamic>>> _load(
    String path, {
    String op = 'load',
    List<String> keys = const ['data', 'list'],
  }) async {
    final d = await _request(path, {'operation': op});
    Iterable<dynamic>? rows;
    if (d is List) {
      rows = d;
    } else if (d is Map) {
      for (final k in keys) {
        if (d[k] is List) rows = d[k] as List;
      }
    }
    return [
      for (final r in rows ?? const [])
        if (r is Map<String, dynamic>) r,
    ];
  }

  // ---- Features ----

  static bool? _bool(Object? v) => v == null ? null : const {'on', 'yes', 'true', '1'}.contains('$v'.toLowerCase());

  static double? _fraction(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    if (d == null) return null;
    return d > 1 ? d / 100 : d;
  }

  static String? _s(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty || s == '0.0.0.0' ? null : s;
  }

  @override
  Future<RouterOverview> overview() async {
    final s = await _read('admin/status?form=all');
    Map<String, dynamic> fw = const {};
    try {
      fw = await _read('admin/firmware?form=upgrade');
    } on RouterDriverException {
      // Some firmware hides this behind another page; the rest still shows.
    }
    var cpu = _fraction(s['cpu_usage']), mem = _fraction(s['mem_usage']);
    if (cpu == null || mem == null) {
      try {
        final p = await _read('admin/status?form=perf');
        cpu ??= _fraction(p['cpu_usage']);
        mem ??= _fraction(p['mem_usage']);
      } on RouterDriverException {
        // optional
      }
    }
    bool? internet;
    try {
      final i = await _read('admin/status?form=internet');
      final st = '${i['internet_status'] ?? i['wan_internet_status'] ?? ''}'.toLowerCase();
      if (st.isNotEmpty) internet = st == 'connected';
    } on RouterDriverException {
      // optional
    }
    final up = int.tryParse('${s['wan_ipv4_uptime'] ?? ''}');
    final v6 = _s('${s['wan_ipv6_ip6addr'] ?? ''}'.split('/').first);
    return RouterOverview(
      model: _s(fw['model']),
      hardwareVersion: _s(fw['hardware_version']),
      firmware: _s(fw['firmware_version']),
      wanIp: _s(s['wan_ipv4_ipaddr']),
      wanGateway: _s(s['wan_ipv4_gateway']),
      // Some firmware reports a numeric code here instead of dhcp/pppoe/…; skip it.
      wanType:
          _s(s['wan_ipv4_conntype']) ?? (int.tryParse('${s['conn_type'] ?? ''}') == null ? _s(s['conn_type']) : null),
      wanUptime: up == null ? null : Duration(seconds: up),
      lanIp: _s(s['lan_ipv4_ipaddr']),
      wanMac: _s(s['wan_macaddr']),
      lanMac: _s(s['lan_macaddr']),
      cpu: cpu,
      memory: mem,
      dhcpServer: _bool(s['lan_ipv4_dhcp_enable']),
      ipv6: v6 == '::' ? null : v6,
      internet: internet,
    );
  }

  static ClientLink _link(Object? wire, {required bool guest}) {
    final w = '${wire ?? ''}'.toLowerCase();
    if (w == 'wired') return ClientLink.wired;
    if (guest) return ClientLink.guest;
    if (w.startsWith('2.4') || w.startsWith('iot_2')) return ClientLink.wifi2g;
    if (w.startsWith('5') || w.startsWith('iot_5')) return ClientLink.wifi5g;
    if (w.startsWith('6') || w.startsWith('iot_6')) return ClientLink.wifi6g;
    return ClientLink.unknown;
  }

  static String _mac(Object? v) => '${v ?? ''}'.replaceAll('-', ':').toUpperCase();

  @override
  Future<List<RouterClient>> clients() async {
    final s = await _read('admin/status?form=all');
    final out = <String, RouterClient>{};
    void add(Object? rows, {required bool guest}) {
      if (rows is! List) return;
      for (final r in rows.whereType<Map>()) {
        final mac = _mac(r['macaddr']);
        if (mac.isEmpty) continue;
        final name = _s(r['hostname']);
        out[mac] = RouterClient(
          mac: mac,
          ip: _s(r['ipaddr']),
          name: name == '--' ? null : name,
          link: _link(r['wire_type'], guest: guest),
          guest: guest,
        );
      }
    }

    add(s['access_devices_wired'], guest: false);
    add(s['access_devices_wireless_host'], guest: false);
    add(s['access_devices_wireless_guest'], guest: true);

    // Live speeds, signal and time online (not every firmware has this page).
    try {
      for (final r in await _load('admin/smart_network?form=game_accelerator', op: 'loadDevice')) {
        final mac = _mac(r['mac']);
        final c = out[mac];
        if (c == null) continue;
        double? rate(Object? v) {
          final d = v is num ? v.toDouble() : double.tryParse('$v');
          return d == null ? null : d * 8; // bytes/s → bits/s
        }

        final online = double.tryParse('${r['onlineTime'] ?? r['online_time'] ?? ''}')?.round();
        out[mac] = RouterClient(
          mac: mac,
          ip: c.ip,
          name: c.name ?? _s(r['deviceName']),
          link: c.link,
          guest: c.guest,
          downBps: rate(r['downloadSpeed'] ?? r['downSpeed']),
          upBps: rate(r['uploadSpeed'] ?? r['upSpeed']),
          signal: int.tryParse('${r['signal'] ?? ''}'),
          online: online == null ? null : Duration(seconds: online),
          trafficBytes: int.tryParse('${r['trafficUsage'] ?? r['trafficUsed'] ?? ''}'),
          kind: _s(r['deviceType'])?.toLowerCase(),
        );
      }
    } on RouterDriverException {
      // optional
    }
    return out.values.toList();
  }

  @override
  Future<List<WifiNetwork>> wifi() async {
    final out = <WifiNetwork>[];
    for (final form in _wifiForms) {
      Map<String, dynamic> d;
      try {
        d = await _read('admin/wireless?form=$form');
      } on RouterDriverException {
        continue; // band or guest network not present on this model
      }
      if (d.isEmpty) continue;
      Object? v(String k) => d['${form}_$k'] ?? d[k];
      // Bands the hardware lacks (6 GHz on a dual-band model) come back empty.
      if (_s(v('ssid')) == null && _bool(v('enable')) != true) continue;
      final band = form.endsWith('2g')
          ? WifiBand.b24
          : form.endsWith('5g')
          ? WifiBand.b5
          : WifiBand.b6;
      out.add(
        WifiNetwork(
          id: form,
          band: band,
          kind: form.startsWith('guest')
              ? WifiKind.guest
              : form.startsWith('iot')
              ? WifiKind.iot
              : WifiKind.main,
          enabled: _bool(v('enable')),
          ssid: _s(v('ssid')),
          password: _s(v('psk_key')),
          hidden: _bool(v('hidden')),
          security: _s(v('encryption')),
          channel: int.tryParse('${v('current_channel') ?? ''}') ?? int.tryParse('${v('channel') ?? ''}'),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> setWifi(WifiNetwork network, {bool? enabled, String? ssid, String? password}) async {
    // One band's own form takes bare keys (enable, ssid, psk_key). The web UI
    // sends band-prefixed keys only to its combined multi-form URL; prefixed
    // keys on a single form are accepted and silently ignored.
    await _request('admin/wireless?form=${network.id}', {
      'operation': 'write',
      if (enabled != null) 'enable': enabled ? 'on' : 'off',
      'ssid': ?ssid,
      'psk_key': ?password,
    });
  }

  @override
  Future<void> reboot() => _request('admin/system?form=reboot', {'operation': 'write'}, ignoreResponse: true);

  @override
  Future<List<RouterForward>> forwards() async {
    final rows = await _load('admin/nat?form=vs');
    return [
      for (final (i, r) in rows.indexed)
        RouterForward(
          id: '${r['__index'] ?? r['id'] ?? i}',
          name: '${r['name'] ?? ''}',
          externalPort: '${r['external_port'] ?? ''}',
          internalIp: '${r['ipaddr'] ?? ''}',
          internalPort: '${r['internal_port'] ?? ''}',
          protocol: '${r['protocol'] ?? 'ALL'}'.toUpperCase(),
          enabled: _bool(r['enable']) ?? true,
        ),
    ];
  }

  @override
  Future<List<DhcpLease>> leases() async {
    final rows = await _load('admin/dhcps?form=client', keys: const ['dhcp_clients', 'data', 'list']);
    return [
      for (final r in rows)
        DhcpLease(
          mac: _mac(r['macaddr']),
          ip: '${r['ipaddr'] ?? ''}',
          name: _s(r['name']),
          expires: _s(r['leasetime']),
        ),
    ];
  }
}

/// AES session of the encrypted variants: random 16-character key and IV,
/// the router's signing key and sequence number.
///
/// Classic: key/IV are hex, the sign is RSA PKCS#1 v1.5 over
/// `k=…&i=…&h=MD5(user+password)&s=seq+len` (login) or `h=…&s=…`.
/// SG (firmware certified "SG CLS L1 STAGE2" / "EU CE RED", e.g. Archer AX53):
/// key/IV are 16 random digits, the hash is SHA-256(user+password), the login
/// sign is RSA-OAEP (SHA-1), and every later request replaces the hash with
/// SHA-256 of its encrypted data and signs `h=…&s=…` with HMAC-SHA256 keyed by
/// `k=…&i=…`. Visible for tests (crypto round-trips).
class TplinkSession {
  TplinkSession({required this.n, required this.e, required this.seq, required this.hash, this.sg = false})
    : key = sg ? _digits16() : _hex16(),
      iv = sg ? _digits16() : _hex16();

  final BigInt n;
  final BigInt e;
  final int seq;
  final bool sg;
  final String key;
  final String iv;

  /// MD5/SHA-256 of user+password; SG replaces it per request.
  String hash;

  static String _hex16() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _digits16() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(10)).join();
  }

  CBCBlockCipher _cipher(bool forEncryption) => CBCBlockCipher(AESEngine())
    ..init(
      forEncryption,
      ParametersWithIV(KeyParameter(Uint8List.fromList(utf8.encode(key))), Uint8List.fromList(utf8.encode(iv))),
    );

  String encrypt(String plain) {
    final data = utf8.encode(plain);
    final pad = 16 - data.length % 16;
    final input = Uint8List.fromList([...data, ...List.filled(pad, pad)]);
    final c = _cipher(true);
    final out = Uint8List(input.length);
    for (var o = 0; o < input.length; o += 16) {
      c.processBlock(input, o, out, o);
    }
    return base64.encode(out);
  }

  String decrypt(String b64) {
    final input = base64.decode(b64);
    final c = _cipher(false);
    final out = Uint8List(input.length);
    for (var o = 0; o + 16 <= input.length; o += 16) {
      c.processBlock(input, o, out, o);
    }
    final pad = out.isEmpty ? 0 : out.last;
    final end = pad > 0 && pad <= 16 && pad <= out.length ? out.length - pad : out.length;
    return utf8.decode(out.sublist(0, end), allowMalformed: true);
  }

  /// `sign=…&data=…` for a request body.
  String envelope(String plain, {bool login = false}) {
    final data = encrypt(plain);
    final sign = StringBuffer();
    if (!sg) {
      final s = login ? 'k=$key&i=$iv&h=$hash&s=${seq + data.length}' : 'h=$hash&s=${seq + data.length}';
      for (var p = 0; p < s.length; p += 53) {
        sign.write(TplinkRsa.pkcs1Hex(s.substring(p, min(p + 53, s.length)), n, e));
      }
    } else if (login) {
      final s = 'k=$key&i=$iv&h=$hash&s=${seq + data.length}';
      // OAEP (SHA-1) carries 42 bytes of overhead; the web UI's 53-character
      // chunks only fit keys of 1024 bits and up.
      final k = (n.bitLength + 7) ~/ 8;
      final step = min(53, k - 42);
      for (var p = 0; p < s.length; p += step) {
        sign.write(TplinkRsa.oaepHex(s.substring(p, min(p + step, s.length)), n, e));
      }
    } else {
      hash = sha256.convert(utf8.encode(data)).toString();
      final s = 'h=$hash&s=${seq + data.length}';
      final mac = Hmac(sha256, utf8.encode('k=$key&i=$iv'));
      for (var p = 0; p < s.length; p += 53) {
        sign.write(mac.convert(utf8.encode(s.substring(p, min(p + 53, s.length)))).toString());
      }
    }
    return 'sign=$sign&data=${Uri.encodeQueryComponent(data)}';
  }
}

/// Visible for tests.
class TplinkRsa {
  /// RSA PKCS#1 v1.5 encryption of [text], as lower-case hex of the key size.
  static String pkcs1Hex(String text, BigInt n, BigInt e) {
    final k = (n.bitLength + 7) ~/ 8;
    final m = utf8.encode(text);
    if (m.length > k - 11) throw const RouterDriverException(RouterErrorKind.unexpected, 'value too long');
    final r = Random.secure();
    final em = Uint8List(k)
      ..[0] = 0
      ..[1] = 2;
    for (var i = 2; i < k - m.length - 1; i++) {
      em[i] = r.nextInt(255) + 1; // non-zero padding
    }
    em[k - m.length - 1] = 0;
    em.setRange(k - m.length, k, m);
    var x = BigInt.zero;
    for (final b in em) {
      x = (x << 8) | BigInt.from(b);
    }
    return x.modPow(e, n).toRadixString(16).padLeft(k * 2, '0');
  }

  /// RSA-OAEP (SHA-1, MGF1-SHA-1) encryption of [text], as hex of the key size.
  static String oaepHex(String text, BigInt n, BigInt e) {
    final k = (n.bitLength + 7) ~/ 8;
    final rnd = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)))));
    final enc = OAEPEncoding(RSAEngine())
      ..init(true, ParametersWithRandom(PublicKeyParameter<RSAPublicKey>(RSAPublicKey(n, e)), rnd));
    final out = enc.process(Uint8List.fromList(utf8.encode(text)));
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join().padLeft(k * 2, '0');
  }
}
