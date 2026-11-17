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
/// With PULSE_ROUTER_PASSWORD set it signs in for real and reads everything.
void main() {
  test('TP-Link protocol check', () async {
    final gw = await Gateway.ipv4();
    if (gw == null || !await TplinkDriver.supports(gw)) {
      markTestSkipped('No TP-Link LuCI router here');
      return;
    }
    final real = Platform.environment['PULSE_ROUTER_PASSWORD'];
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
      stdout.writeln('model ${o.model} hw ${o.hardwareVersion} fw ${o.firmware} cpu ${o.cpu} mem ${o.memory} '
          'wan ${o.wanType} up ${o.wanUptime}');
      final c = await d.clients();
      stdout.writeln('clients: ${c.length}');
      for (final w in await d.wifi()) {
        stdout.writeln('wifi ${w.id}: ${w.enabled} "${w.ssid}" ch ${w.channel}');
      }
      stdout.writeln('forwards: ${(await d.forwards()).length}');
    } finally {
      await d.signOut();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
