@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/services/net/gateway.dart';
import 'package:pulse/services/net/router/drivers/router_driver.dart';
import 'package:pulse/services/net/router/drivers/tplink_driver.dart';
import 'package:pulse/services/net/router/router_probe.dart';

/// Against a real TP-Link router on this network: one sign-in with a wrong
/// password. A "wrong password" answer (with attempts left) proves the router
/// decrypted Pulse's request, i.e. the protocol works, without a real login.
/// With PULSE_ROUTER_PASSWORD set (environment, or a line in the git-ignored
/// `.env` at the project root) it signs in for real and reads everything.
/// The password is never printed.
void main() {
  test('TP-Link protocol check', () async {
    final gw = await Gateway.ipv4();
    if (gw == null || !await TplinkDriver.supports(gw)) {
      markTestSkipped('No TP-Link LuCI router here');
      return;
    }
    final real = _routerPassword();
    final d = TplinkDriver(gw);
    if (real == null) {
      try {
        await d.signIn(const RouterCredential('', 'pulse-protocol-check-not-a-password'));
        fail('A made-up password was accepted?');
      } on RouterDriverException catch (e) {
        stdout.writeln('router answered: ${e.kind} ${e.detail ?? ''}');
        expect(e.kind, isNot(RouterErrorKind.unexpected));
        expect(e.kind, isNot(RouterErrorKind.network));
      }
      return;
    }
    await d.signIn(RouterCredential('', real));
    try {
      final o = await d.overview();
      stdout.writeln(
        'model ${o.model} hw ${o.hardwareVersion} fw ${o.firmware} cpu ${o.cpu} mem ${o.memory} '
        'wan ${o.wanType} up ${o.wanUptime} internet ${o.internet}',
      );
      expect(o.model, isNotNull);
      expect(o.firmware, isNotNull);
      final c = await d.clients();
      stdout.writeln(
        'clients: ${c.length}, with live rates ${c.where((x) => x.downBps != null).length}, '
        'typed ${c.where((x) => x.kind != null).length}',
      );
      for (final w in await d.wifi()) {
        stdout.writeln('wifi ${w.id} (${w.kind.name}): ${w.enabled} ch ${w.channel} security ${w.security}');
      }
      stdout.writeln('forwards: ${(await d.forwards()).length}');
      final w = await d.wan();
      stdout.writeln(
        'internet: ${w.current?.label}, offers ${w.available.map((t) => t.label).join('/')}, '
        'connected ${w.connected}, read ${w.settings.length} types, dns ${w.dns.length}',
      );
      expect(w.current, isNotNull);
      expect(w.settings[w.current], isNotNull);
    } finally {
      await d.signOut();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}

/// PULSE_ROUTER_PASSWORD from the environment, else from `.env` (KEY=VALUE
/// lines; quotes optional). Only that key is read.
String? _routerPassword() {
  final env = Platform.environment['PULSE_ROUTER_PASSWORD'];
  if (env != null && env.isNotEmpty) return env;
  final f = File('.env');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (!t.startsWith('PULSE_ROUTER_PASSWORD=')) continue;
    var v = t.substring('PULSE_ROUTER_PASSWORD='.length).trim();
    if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v.isEmpty ? null : v;
  }
  return null;
}
