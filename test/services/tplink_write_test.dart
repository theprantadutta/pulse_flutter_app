@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/services/net/gateway.dart';
import 'package:pulse/services/net/router/drivers/router_driver.dart';
import 'package:pulse/services/net/router/drivers/tplink_driver.dart';
import 'package:pulse/services/net/router/router_probe.dart';

/// Write check on a real router: turns the 2.4 GHz guest network on, reads it
/// back, and turns it off again. Only runs with PULSE_ROUTER_WRITE=1 (and the
/// owner's OK), never as part of a normal test run.
void main() {
  test('guest network on/off round trip', () async {
    if (Platform.environment['PULSE_ROUTER_WRITE'] != '1') return markTestSkipped('set PULSE_ROUTER_WRITE=1');
    final pw = _password();
    final gw = await Gateway.ipv4();
    if (pw == null || gw == null) return markTestSkipped('needs PULSE_ROUTER_PASSWORD');
    final d = TplinkDriver(gw);
    await d.signIn(RouterCredential('', pw));
    try {
      Future<WifiNetwork> guest() async => (await d.wifi()).firstWhere((n) => n.id == 'guest_2g');
      final before = await guest();
      stdout.writeln('guest_2g before: ${before.enabled}');
      expect(before.enabled, isFalse, reason: 'only run while the guest network is off');
      await d.setWifi(before, enabled: true);
      await Future<void>.delayed(const Duration(seconds: 3));
      final on = await guest();
      stdout.writeln('guest_2g after on: ${on.enabled}');
      await d.setWifi(on, enabled: false);
      await Future<void>.delayed(const Duration(seconds: 3));
      final off = await guest();
      stdout.writeln('guest_2g after off: ${off.enabled}');
      expect(on.enabled, isTrue);
      expect(off.enabled, isFalse);
    } finally {
      // Never leave it on.
      try {
        final g = (await d.wifi()).firstWhere((n) => n.id == 'guest_2g');
        if (g.enabled == true) await d.setWifi(g, enabled: false);
      } on Object {
        // reported by the assertions above
      }
      await d.signOut();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  _more();
}

void _more() {
  test('guest rename + smart-home on/off, restored', () async {
    if (Platform.environment['PULSE_ROUTER_WRITE'] != '1') return markTestSkipped('set PULSE_ROUTER_WRITE=1');
    final pw = _password();
    final gw = await Gateway.ipv4();
    if (pw == null || gw == null) return markTestSkipped('needs PULSE_ROUTER_PASSWORD');
    final d = TplinkDriver(gw);
    await d.signIn(RouterCredential('', pw));
    Future<WifiNetwork> net(String id) async => (await d.wifi()).firstWhere((n) => n.id == id);
    final g = await net('guest_2g');
    final iot = await net('iot_2g');
    expect(g.enabled, isFalse);
    expect(iot.enabled, isFalse);
    try {
      final name = '${g.ssid}-T';
      await d.setWifi(g, ssid: name);
      await Future<void>.delayed(const Duration(seconds: 3));
      final renamed = await net('guest_2g');
      stdout.writeln('guest rename read back: ${renamed.ssid == name}, still off: ${renamed.enabled == false}');
      expect(renamed.ssid, name);
      expect(renamed.enabled, isFalse);
      await d.setWifi(iot, enabled: true);
      await Future<void>.delayed(const Duration(seconds: 3));
      final iotOn = await net('iot_2g');
      stdout.writeln('iot on: ${iotOn.enabled}');
      expect(iotOn.enabled, isTrue);
      await d.setWifi(iotOn, enabled: false);
      final newPass = '${iot.password}9';
      await d.setWifi(await net('iot_2g'), password: newPass);
      await Future<void>.delayed(const Duration(seconds: 3));
      final iotPass = await net('iot_2g');
      stdout.writeln('iot password read back: ${iotPass.password == newPass}');
      expect(iotPass.password, newPass);
    } finally {
      if ((await net('iot_2g')).password != iot.password) await d.setWifi(await net('iot_2g'), password: iot.password);
      await d.setWifi(await net('guest_2g'), ssid: g.ssid);
      final i = await net('iot_2g');
      if (i.enabled == true) await d.setWifi(i, enabled: false);
      await Future<void>.delayed(const Duration(seconds: 3));
      final g2 = await net('guest_2g'), i2 = await net('iot_2g');
      stdout.writeln(
        'restored: guest name ${g2.ssid == g.ssid}, guest off ${g2.enabled == false}, iot off ${i2.enabled == false}, iot password ${i2.password == iot.password}',
      );
      await d.signOut();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String? _password() {
  final env = Platform.environment['PULSE_ROUTER_PASSWORD'];
  if (env != null && env.isNotEmpty) return env;
  final f = File('.env');
  if (!f.existsSync()) return null;
  for (final l in f.readAsLinesSync()) {
    final t = l.trim();
    if (!t.startsWith('PULSE_ROUTER_PASSWORD=')) continue;
    var v = t.substring('PULSE_ROUTER_PASSWORD='.length).trim();
    if (v.length >= 2 && (v[0] == '"' || v[0] == "'") && v[v.length - 1] == v[0]) v = v.substring(1, v.length - 1);
    return v.isEmpty ? null : v;
  }
  return null;
}
