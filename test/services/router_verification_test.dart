import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/presentations/screens/router/router_actions.dart';
import 'package:pulse/services/net/router/verification.dart';
import 'package:pulse/services/pulse_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const id = RouterIdentity(driver: 'luci-encrypted-web', model: 'Archer AX53', firmware: '1.7.1', hardware: 'v1.0');

  Future<(RouterVerification, List<http.Request>)> make(http.Response Function(http.Request) reply) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final seen = <http.Request>[];
    final api = PulseApi(
      key: 'k',
      baseUrl: 'https://api.test',
      client: MockClient((r) async {
        seen.add(r);
        return reply(r);
      }),
    );
    return (RouterVerification(prefs, api: api), seen);
  }

  test('verdicts map to trust, unknown actions are "Try it", failing ones are hidden', () async {
    final (v, seen) = await make(
      (_) => http.Response(
        jsonEncode({
          'features': {'wifi.toggle': 'verified', 'guest.toggle': 'failing', 'wifi.edit': 'try'},
        }),
        200,
      ),
    );
    final caps = await v.load(id);
    expect(seen.single.url.path, '/api/v1/router/capabilities');
    expect(jsonDecode(seen.single.body), {'driver': 'luci-encrypted-web', 'model': 'Archer AX53', 'firmware': '1.7.1'});
    expect(seen.single.headers['x-pulse-signature'], isNotEmpty);
    expect(caps.fresh, isTrue);
    expect(caps.trust('wifi.toggle'), ActionTrust.verified);
    expect(caps.trust('wifi.edit'), ActionTrust.untested);
    expect(caps.trust('system.reboot'), ActionTrust.untested);
    expect(caps.offers('guest.toggle'), isFalse);
    expect(caps.asks('wifi.toggle'), isFalse);
    expect(caps.asks('wifi.edit'), isTrue);
  });

  test('offline: cached verdicts are used', () async {
    var up = true;
    final (v, _) = await make(
      (_) => up
          ? http.Response(
              jsonEncode({
                'features': {'system.reboot': 'verified'},
              }),
              200,
            )
          : http.Response('down', 503),
    );
    await v.load(id);
    up = false;
    final caps = await v.load(id);
    expect(caps.fresh, isFalse);
    expect(caps.trust('system.reboot'), ActionTrust.verified);
  });

  test('a report carries no network data, uses a stable install id and stops further questions', () async {
    final (v, seen) = await make((_) => http.Response('{"ok":true}', 201));
    expect(await v.report(id, 'guest.toggle', worked: true), isTrue);
    expect(await v.report(id, 'wifi.edit', worked: false), isTrue);
    final a = jsonDecode(seen[0].body) as Map<String, dynamic>;
    final b = jsonDecode(seen[1].body) as Map<String, dynamic>;
    expect(a.keys.toSet(), {'driver', 'model', 'hardware', 'firmware', 'feature', 'worked', 'install'});
    expect(a['feature'], 'guest.toggle');
    expect(a['worked'], isTrue);
    expect(a['install'], hasLength(32));
    expect(b['install'], a['install']);
    expect(v.mine(id), {'guest.toggle': true, 'wifi.edit': false});
  });

  test('Wi-Fi QR payload escapes special characters', () {
    expect(const WifiQr(ssid: 'Cafe;1', password: r'p:a"ss\').payload, r'WIFI:T:WPA;S:Cafe\;1;P:p\:a\"ss\\;;');
    expect(const WifiQr(ssid: 'Guest').payload, 'WIFI:T:nopass;S:Guest;;');
    expect(
      const WifiQr(ssid: 'Hide', password: '12345678', hidden: true).payload,
      'WIFI:T:WPA;S:Hide;P:12345678;H:true;;',
    );
  });
}
