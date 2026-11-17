@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/services/net/gateway.dart';
import 'package:pulse/services/net/router/router_probe.dart';
import 'package:pulse/services/net/router/upnp_igd.dart';

/// Probes the router of the network this machine is on (read-only: detection,
/// UPnP status and the port-mapping list). Skips when there is no gateway.
void main() {
  test('probe the local router', () async {
    final gw = await Gateway.ipv4();
    if (gw == null) {
      markTestSkipped('No gateway');
      return;
    }
    final p = await RouterProbe.probe(gw);
    stdout.writeln('router: ${p.name} (${p.brand.label}) at ${p.adminUrl}');
    stdout.writeln('title: ${p.pageTitle} · server: ${p.server} · protocols: ${p.protocols.map((e) => e.label)}');
    final igd = p.igd;
    if (igd == null) {
      stdout.writeln('no UPnP IGD');
      return;
    }
    stdout.writeln('igd: ${igd.location} · conn: ${igd.wanConnection?.type} · common: ${igd.wanCommon?.type}');
    final s1 = await UpnpIgd.status(igd);
    await Future<void>.delayed(const Duration(seconds: 3));
    final s2 = await UpnpIgd.status(igd);
    stdout.writeln(
      'status: ${s2.connectionStatus} · up ${s2.uptime} · access ${s2.accessType} · link ${s2.linkStatus} · '
      'max ${s2.maxDownBps}/${s2.maxUpBps} · ip ${s2.externalIp == null ? 'none' : 'reported'}',
    );
    if (s1.bytesReceived != null && s2.bytesReceived != null) {
      stdout.writeln('down ≈ ${((s2.bytesReceived! - s1.bytesReceived!) * 8 / 3 / 1e6).toStringAsFixed(2)} Mbps');
    }
    final maps = await UpnpIgd.mappings(igd);
    stdout.writeln('port mappings: ${maps.length}');
    for (final m in maps.take(5)) {
      stdout.writeln('  ${m.protocol} ${m.externalPort} -> ${m.internalClient}:${m.internalPort} "${m.description}"');
    }
    expect(p.gateway, gw);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
