@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/services/net/gateway.dart';
import 'package:pulse/services/net/router/drivers/tplink_driver.dart';
import 'package:pulse/services/net/router/router_probe.dart';

/// Dumps the *shape* of every router endpoint Pulse may read (values masked)
/// to the path in PULSE_ROUTER_DUMP. For writing parsers; never committed.
/// Needs PULSE_ROUTER_PASSWORD (environment or .env).
void main() {
  test('dump router response shapes', () async {
    final out = Platform.environment['PULSE_ROUTER_DUMP'];
    final pw = _password();
    final gw = await Gateway.ipv4();
    if (out == null || pw == null || gw == null) return markTestSkipped('needs PULSE_ROUTER_DUMP + password');
    final d = TplinkDriver(gw);
    await d.signIn(RouterCredential('', pw));
    const calls = <(String, List<String>)>[
      ('admin/network?form=wan_ipv4_protos', ['read']),
      ('admin/network?form=wan_ipv4_status', ['read']),
      ('admin/network?form=wan_ipv4_dynamic', ['read']),
      ('admin/network?form=wan_ipv4_staticip', ['read']),
      ('admin/network?form=wan_ipv4_bigpond', ['read']),
      ('admin/network?form=wan_ipv4_pppoe', ['read']),
      ('admin/network?form=wan_ipv4_l2tp', ['read']),
      ('admin/network?form=wan_ipv4_pptp', ['read']),
      ('admin/status?form=all', ['read']),
      ('admin/status?form=internet', ['read']),
      ('admin/status?form=network_map', ['read']),
      ('admin/smart_network?form=game_accelerator', ['loadDevice']),
      ('admin/smart_network?form=client_speed_limit', ['read', 'load']),
      ('admin/access_control?form=enable', ['read']),
      ('admin/access_control?form=mode', ['read']),
      ('admin/access_control?form=black_devices', ['load', 'read']),
      ('admin/access_control?form=white_devices', ['load', 'read']),
      ('admin/dhcps?form=setting', ['read']),
      ('admin/dhcps?form=reservation', ['load']),
      ('admin/dhcps?form=client', ['load']),
      ('admin/wireless?form=wireless_2g', ['read']),
      ('admin/wireless?form=syspara_2g', ['read']),
      ('admin/wireless?form=smart_connect', ['read']),
      ('admin/wireless?form=guest', ['read']),
      ('admin/wireless?form=guest_2g', ['read']),
      ('admin/wireless?form=guestnetwork_bandwidth_ctrl', ['read']),
      ('admin/wireless?form=iot_2g', ['read']),
      ('admin/wireless?form=wireless_addition_setting', ['read']),
      ('admin/wireless?form=syspara_wps', ['read']),
      ('admin/wireless_schedule_v2?form=settings', ['read', 'load']),
      ('admin/nat?form=vs', ['load']),
      ('admin/nat?form=pt', ['load']),
      ('admin/nat?form=dmz', ['read']),
      ('admin/nat?form=alg', ['read']),
      ('admin/upnp?form=enable', ['read']),
      ('admin/upnp?form=service', ['load', 'read']),
      ('admin/security_settings?form=new_enable', ['read']),
      ('admin/iot_security?form=enable', ['read']),
      ('admin/imb?form=setting', ['read']),
      ('admin/vpn?form=enable', ['read']),
      ('admin/openvpn?form=config', ['read']),
      ('admin/pptpd?form=config', ['read']),
      ('admin/wireguard?form=config', ['read']),
      ('admin/ddns?form=provider', ['read']),
      ('admin/network?form=lan_ipv4', ['read']),
      ('admin/network?form=status_ipv4', ['read']),
      ('admin/network?form=routes_system', ['load', 'read']),
      ('admin/firmware?form=upgrade', ['read']),
      ('admin/firmware?form=auto_upgrade', ['read']),
      ('admin/reboot?form=set', ['read']),
      ('admin/ledgeneral?form=setting', ['read']),
      ('admin/ledpm?form=setting', ['read']),
      ('admin/eco_mode?form=settings', ['read']),
      ('admin/time?form=settings', ['read']),
      ('admin/easymesh?form=easymesh_enable', ['read']),
      ('admin/easymesh_network?form=get_mesh_device_list_all', ['read', 'load']),
    ];
    final result = <String, Object?>{};
    try {
      for (final (path, ops) in calls) {
        for (final op in ops) {
          try {
            result['$path [$op]'] = _mask(await d.rawCall(path, op));
            break;
          } on Object catch (e) {
            result['$path [$op]'] = 'ERROR: $e';
          }
        }
      }
    } finally {
      await d.signOut();
    }
    File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(result));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final _keep = RegExp(
  r'^(on|off|true|false|yes|no|auto|none|[a-z][a-z0-9_]{0,15}|[A-Za-z0-9 /().-]{1,24}|-?\d{1,6}(\.\d+)?)$',
);

Object? _mask(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': _mask(e.value)};
  if (v is List) return [for (final x in v.take(8)) _mask(x), if (v.length > 8) '…${v.length} items'];
  if (v is String) return _keep.hasMatch(v) ? v : '<str ${v.length}>';
  return v;
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
