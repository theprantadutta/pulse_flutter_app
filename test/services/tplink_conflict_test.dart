@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/services/net/gateway.dart';
import 'package:pulse/services/net/router/drivers/router_driver.dart';
import 'package:pulse/services/net/router/drivers/tplink_driver.dart';
import 'package:pulse/services/net/router/router_probe.dart';

/// With one session signed in, a second normal sign-in must report "busy"
/// instead of signing it out; with force it takes over. Opt-in
/// (PULSE_ROUTER_BUSY=1): it signs out anyone using the router's page.
void main() {
  test('sign-in without force does not take over another session', () async {
    if (Platform.environment['PULSE_ROUTER_BUSY'] != '1') return markTestSkipped('set PULSE_ROUTER_BUSY=1');
    final pw = _password();
    final gw = await Gateway.ipv4();
    if (pw == null || gw == null) return markTestSkipped('needs PULSE_ROUTER_PASSWORD');
    // Another device (e.g. Pulse on a tablet with Router open) holds the session.
    final d = TplinkDriver(gw);
    Object? error;
    try {
      await d.signIn(RouterCredential('', pw));
      await d.signOut();
    } on RouterDriverException catch (e) {
      error = e;
    }
    stdout.writeln('sign-in without force while another device is signed in: $error');
    expect(error, isA<RouterDriverException>().having((e) => e.kind, 'kind', RouterErrorKind.busy));
  });
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
