import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../lan/ssdp.dart';

/// A UPnP service of the router: its type URN and SOAP control URL.
class IgdService {
  const IgdService(this.type, this.control);
  final String type;
  final Uri control;
}

/// The router's UPnP Internet Gateway Device: what it says about itself and
/// the WAN services Pulse talks to. No login: UPnP is open to the LAN when the
/// router has it switched on.
class IgdDevice {
  const IgdDevice({required this.location, required this.info, this.presentation, this.wanConnection, this.wanCommon});

  final Uri location;
  final UpnpInfo info;

  /// The admin page the router advertises (`presentationURL`), if any.
  final Uri? presentation;

  /// WANIPConnection or WANPPPConnection: external IP, status, port mappings.
  final IgdService? wanConnection;

  /// WANCommonInterfaceConfig: link type, max rates, byte counters.
  final IgdService? wanCommon;

  bool get canMap => wanConnection != null;
}

/// A UPnP SOAP fault ("714 NoSuchEntryInArray", "718 ConflictInMappingEntry").
class UpnpFault implements Exception {
  const UpnpFault(this.code, this.description);
  final int? code;
  final String description;

  /// A plain-English reason for the common faults.
  String get friendly => switch (code) {
    401 || 606 => 'The router refused this action (it may need UPnP control enabled).',
    402 => 'The router rejected the values.',
    713 || 714 => 'No such port forward.',
    715 || 716 => 'This router only supports forwards for any remote host.',
    718 => 'That external port is already forwarded.',
    724 || 725 => 'The router needs the same internal and external port and no time limit.',
    729 => 'That port is already used by the router.',
    _ => description.isEmpty ? 'The router returned an error${code == null ? '' : ' ($code)'}.' : description,
  };

  @override
  String toString() => 'UpnpFault($code, $description)';
}

/// One UPnP port mapping (a "port forward").
class PortMapping {
  const PortMapping({
    required this.protocol,
    required this.externalPort,
    required this.internalClient,
    required this.internalPort,
    this.description = '',
    this.enabled = true,
    this.leaseSeconds = 0,
    this.remoteHost = '',
  });

  /// "TCP" or "UDP".
  final String protocol;
  final int externalPort;
  final String internalClient;
  final int internalPort;
  final String description;
  final bool enabled;

  /// 0 = permanent.
  final int leaseSeconds;
  final String remoteHost;
}

/// Internet status as the router reports it.
class IgdStatus {
  const IgdStatus({
    this.externalIp,
    this.connectionStatus,
    this.uptime,
    this.accessType,
    this.linkStatus,
    this.maxDownBps,
    this.maxUpBps,
    this.bytesReceived,
    this.bytesSent,
  });

  final String? externalIp;

  /// "Connected", "Disconnected", "Connecting"…
  final String? connectionStatus;
  final Duration? uptime;

  /// "Ethernet", "DSL", "Cable", "POTS"…
  final String? accessType;

  /// "Up", "Down"…
  final String? linkStatus;
  final int? maxDownBps;
  final int? maxUpBps;

  /// Since the router's counters began; many wrap at 4 GiB.
  final int? bytesReceived;
  final int? bytesSent;

  bool get connected => connectionStatus?.toLowerCase() == 'connected';
}

class UpnpIgd {
  UpnpIgd._();

  static const _igdTypes = [
    'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
    'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
  ];

  /// Description paths common routers serve, tried when nothing answers SSDP
  /// (multicast filtered): miniupnpd (ASUS, OpenWrt, Netgear…), TP-Link,
  /// FRITZ!Box, Realtek SDK routers, Broadcom gateways.
  static const _wellKnown = [
    ':1900/gatedesc.xml',
    ':5000/rootDesc.xml',
    ':49000/igddesc.xml',
    ':52869/picsdesc.xml',
    ':49152/IGDdevicedesc_brlan0.xml',
    ':1780/InternetGatewayDevice.xml',
  ];

  /// Finds the gateway's IGD: SSDP search sent to [gateway] directly and to
  /// the multicast group (only answers from [gateway] count), then the
  /// well-known description paths.
  static Future<IgdDevice?> find(String gateway) async {
    final locations = await _search(gateway);
    for (final suffix in _wellKnown) {
      locations.add(Uri.parse('http://$gateway$suffix'));
    }
    for (final loc in locations) {
      if (loc.host != gateway) continue;
      final xml = await _get(loc);
      if (xml == null) continue;
      final dev = parse(xml, loc);
      if (dev != null && (dev.wanConnection != null || dev.wanCommon != null)) return dev;
    }
    return null;
  }

  static Future<List<Uri>> _search(String gateway) async {
    final found = <Uri>[];
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.multicastHops = 2;
      final sub = socket.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = socket!.receive();
        if (d == null || d.address.address != gateway) return;
        final loc = Ssdp.parseHeaders(utf8.decode(d.data, allowMalformed: true))['location'];
        final uri = loc == null ? null : Uri.tryParse(loc);
        if (uri != null && !found.contains(uri)) found.add(uri);
      });
      for (final st in _igdTypes) {
        final msg = utf8.encode(
          'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: $st\r\n'
          'USER-AGENT: Pulse UPnP/1.1\r\n\r\n',
        );
        socket.send(msg, InternetAddress(gateway), 1900);
        socket.send(msg, InternetAddress('239.255.255.250'), 1900);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await sub.cancel();
    } on Object {
      // No route for UDP/multicast: fall back to the well-known paths.
    } finally {
      socket?.close();
    }
    return found;
  }

  /// Reads the device description: root device info, presentation URL and
  /// the first WAN connection / common-interface services anywhere in the tree.
  static IgdDevice? parse(String xml, Uri location) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on Object {
      return null;
    }
    String? text(XmlElement e, String name) {
      final v = e.findElements(name).firstOrNull?.innerText.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final root = doc.rootElement;
    final base = Uri.tryParse(text(root, 'URLBase') ?? '') ?? location;
    Uri resolve(String u) => (base.hasScheme ? base : location).resolve(u);

    IgdService? conn, common;
    for (final s in root.findAllElements('service')) {
      final type = text(s, 'serviceType') ?? '';
      final ctl = text(s, 'controlURL');
      if (ctl == null) continue;
      if (type.contains(':WANIPConnection:') || type.contains(':WANPPPConnection:')) {
        // Prefer IP over PPP when both are listed (PPP is often unused).
        if (conn == null || (conn.type.contains('PPP') && type.contains(':WANIPConnection:'))) {
          conn = IgdService(type, resolve(ctl));
        }
      } else if (type.contains(':WANCommonInterfaceConfig:')) {
        common ??= IgdService(type, resolve(ctl));
      }
    }
    final device = root.findElements('device').firstOrNull;
    final pres = device == null ? null : text(device, 'presentationURL');
    return IgdDevice(
      location: location,
      info: Ssdp.parseDescription(xml),
      presentation: pres == null ? null : resolve(pres),
      wanConnection: conn,
      wanCommon: common,
    );
  }

  /// Calls [action] and returns its out-arguments by name.
  static Future<Map<String, String>> call(IgdService s, String action, [Map<String, Object> args = const {}]) async {
    final body = StringBuffer()
      ..write('<?xml version="1.0"?>')
      ..write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>',
      )
      ..write('<u:$action xmlns:u="${s.type}">');
    args.forEach((k, v) => body.write('<$k>${_escape('$v')}</$k>'));
    body.write('</u:$action></s:Body></s:Envelope>');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final req = await client.postUrl(s.control).timeout(const Duration(seconds: 3));
      final bytes = utf8.encode(body.toString());
      req.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPAction', '"${s.type}#$action"')
        ..contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(const Duration(seconds: 5));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      final doc = XmlDocument.parse(text);
      final fault = doc.findAllElements('UPnPError', namespaceUri: '*').firstOrNull;
      if (fault != null || res.statusCode >= 400) {
        final code = int.tryParse(fault?.findAllElements('errorCode', namespaceUri: '*').firstOrNull?.innerText ?? '');
        final desc = fault?.findAllElements('errorDescription', namespaceUri: '*').firstOrNull?.innerText ?? '';
        throw UpnpFault(code, desc.trim());
      }
      final resp = doc.descendantElements.where((e) => e.name.local == '${action}Response').firstOrNull;
      return {for (final e in resp?.childElements ?? const <XmlElement>[]) e.name.local: e.innerText.trim()};
    } finally {
      client.close(force: true);
    }
  }

  /// Internet status in one go; any call the router doesn't support is skipped.
  static Future<IgdStatus> status(IgdDevice d) async {
    Future<Map<String, String>> safe(IgdService? s, String a) async {
      if (s == null) return const {};
      try {
        return await call(s, a);
      } on Object {
        return const {};
      }
    }

    final c = d.wanConnection, w = d.wanCommon;
    final r = await Future.wait([
      safe(c, 'GetExternalIPAddress'),
      safe(c, 'GetStatusInfo'),
      safe(w, 'GetCommonLinkProperties'),
      safe(w, 'GetTotalBytesReceived'),
      safe(w, 'GetTotalBytesSent'),
    ]);
    String? v(Map<String, String> m, String k) => (m[k]?.isEmpty ?? true) ? null : m[k];
    final ip = v(r[0], 'NewExternalIPAddress');
    final up = int.tryParse(v(r[1], 'NewUptime') ?? '');
    return IgdStatus(
      externalIp: ip == '0.0.0.0' ? null : ip,
      connectionStatus: v(r[1], 'NewConnectionStatus'),
      uptime: up == null ? null : Duration(seconds: up),
      accessType: v(r[2], 'NewWANAccessType'),
      linkStatus: v(r[2], 'NewPhysicalLinkStatus'),
      maxDownBps: int.tryParse(v(r[2], 'NewLayer1DownstreamMaxBitRate') ?? ''),
      maxUpBps: int.tryParse(v(r[2], 'NewLayer1UpstreamMaxBitRate') ?? ''),
      bytesReceived: int.tryParse(v(r[3], 'NewTotalBytesReceived') ?? ''),
      bytesSent: int.tryParse(v(r[4], 'NewTotalBytesSent') ?? ''),
    );
  }

  /// Every port mapping (index walk until the router says there are no more).
  static Future<List<PortMapping>> mappings(IgdDevice d, {int max = 128}) async {
    final s = d.wanConnection;
    if (s == null) return const [];
    final out = <PortMapping>[];
    for (var i = 0; i < max; i++) {
      final Map<String, String> m;
      try {
        m = await call(s, 'GetGenericPortMappingEntry', {'NewPortMappingIndex': i});
      } on UpnpFault {
        break; // 713 SpecifiedArrayIndexInvalid (or 714/402 on some routers): end of the list
      }
      if (m.isEmpty) break;
      out.add(
        PortMapping(
          protocol: (m['NewProtocol'] ?? 'TCP').toUpperCase(),
          externalPort: int.tryParse(m['NewExternalPort'] ?? '') ?? 0,
          internalClient: m['NewInternalClient'] ?? '',
          internalPort: int.tryParse(m['NewInternalPort'] ?? '') ?? 0,
          description: m['NewPortMappingDescription'] ?? '',
          enabled: m['NewEnabled'] != '0',
          leaseSeconds: int.tryParse(m['NewLeaseDuration'] ?? '') ?? 0,
          remoteHost: m['NewRemoteHost'] ?? '',
        ),
      );
    }
    return out;
  }

  static Future<void> addMapping(IgdDevice d, PortMapping m) => call(d.wanConnection!, 'AddPortMapping', {
    'NewRemoteHost': m.remoteHost,
    'NewExternalPort': m.externalPort,
    'NewProtocol': m.protocol,
    'NewInternalPort': m.internalPort,
    'NewInternalClient': m.internalClient,
    'NewEnabled': m.enabled ? 1 : 0,
    'NewPortMappingDescription': m.description,
    'NewLeaseDuration': m.leaseSeconds,
  });

  static Future<void> deleteMapping(IgdDevice d, PortMapping m) => call(d.wanConnection!, 'DeletePortMapping', {
    'NewRemoteHost': m.remoteHost,
    'NewExternalPort': m.externalPort,
    'NewProtocol': m.protocol,
  });

  static Future<String?> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 2));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}
