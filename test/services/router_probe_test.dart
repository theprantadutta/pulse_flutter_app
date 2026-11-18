import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/services/net/router/router_probe.dart';
import 'package:pulse/services/net/router/upnp_igd.dart';

const _desc = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
 <specVersion><major>1</major><minor>0</minor></specVersion>
 <device>
  <deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>
  <friendlyName>Archer AX53</friendlyName>
  <manufacturer>TP-Link</manufacturer>
  <modelName>Archer AX53</modelName>
  <modelNumber>1.0</modelNumber>
  <UDN>uuid:abc-123</UDN>
  <deviceList><device>
   <deviceType>urn:schemas-upnp-org:device:WANDevice:1</deviceType>
   <serviceList><service>
    <serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
    <controlURL>/ctl/CmnIfCfg</controlURL>
   </service></serviceList>
   <deviceList><device>
    <deviceType>urn:schemas-upnp-org:device:WANConnectionDevice:1</deviceType>
    <serviceList>
     <service><serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType><controlURL>/ctl/PPP</controlURL></service>
     <service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType><controlURL>/ctl/IPConn</controlURL></service>
    </serviceList>
   </device></deviceList>
  </device></deviceList>
  <presentationURL>http://192.168.0.1/</presentationURL>
 </device>
</root>''';

void main() {
  test('parses an IGD description: root info, services, presentation URL', () {
    final d = UpnpIgd.parse(_desc, Uri.parse('http://192.168.0.1:1900/vwnhd/rootDesc.xml'))!;
    expect(d.info.manufacturer, 'TP-Link');
    expect(d.info.udn, 'uuid:abc-123');
    expect(d.wanConnection!.type, contains('WANIPConnection')); // IP preferred over PPP
    expect(d.wanConnection!.control.toString(), 'http://192.168.0.1:1900/ctl/IPConn');
    expect(d.wanCommon!.control.path, '/ctl/CmnIfCfg');
    expect(d.presentation.toString(), 'http://192.168.0.1/');
  });

  test('brand detection matches whole words only', () {
    expect(RouterBrand.detect(['TP-Link', 'Archer AX53']), RouterBrand.tplink);
    expect(RouterBrand.detect(['FRITZ!Box 7590']), RouterBrand.avm);
    expect(RouterBrand.detect(['RT-AX88U', 'ASUSTeK']), RouterBrand.asus);
    expect(RouterBrand.detect(['MP4 decoder box']), RouterBrand.unknown); // not "deco"
    expect(RouterBrand.detect([null, 'LuCI - OpenWrt']), RouterBrand.openwrt);
  });

  test('UPnP faults read as plain English', () {
    expect(const UpnpFault(718, 'ConflictInMappingEntry').friendly, 'That external port is already forwarded.');
    expect(const UpnpFault(null, '').friendly, 'The router returned an error.');
  });
}
