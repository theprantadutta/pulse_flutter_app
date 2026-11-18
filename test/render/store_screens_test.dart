@Tags(['render', 'store'])
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/data/db/app_database.dart';
import 'package:pulse/presentations/navigation/tools_catalog.dart';
import 'package:pulse/presentations/screens/router/router_devices_screen.dart';
import 'package:pulse/presentations/screens/router/router_screen.dart';
import 'package:pulse/presentations/screens/router/router_wifi_screen.dart';
import 'package:pulse/presentations/screens/tools/tools_hub_screen.dart';
import 'package:pulse/providers/database_provider.dart';
import 'package:pulse/providers/router_manage_provider.dart';
import 'package:pulse/providers/router_provider.dart';
import 'package:pulse/providers/settings_provider.dart';
import 'package:pulse/services/net/lan/ssdp.dart';
import 'package:pulse/services/net/router/drivers/driver_registry.dart';
import 'package:pulse/services/net/router/drivers/router_driver.dart';
import 'package:pulse/services/net/router/router_probe.dart';
import 'package:pulse/services/net/router/upnp_igd.dart';
import 'package:pulse/services/net/router/verification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

/// Screen captures for the Play Store composites (tools/store_shots.py puts
/// them into the device frames). Light theme, sample data only: no real
/// network's device names, Wi-Fi names or addresses ever go in a listing.
///
/// Sizes are the frames' screen areas: phone = Galaxy A24 (384 x 832 dp) at
/// 824 px wide; tablets = Galaxy Tab A9 landscape (1005 x 600 dp) at the 7"
/// and 10" frames' widths. The top inset leaves room for the frame's status
/// bar, which the compositor keeps from the template.
void main() {
  setUpAll(loadPulseFonts);

  const phone = (Size(384, 832), 824 / 384, EdgeInsets.only(top: 40, bottom: 20));
  const tab7 = (Size(1005, 594), 1270 / 1005, EdgeInsets.only(top: 26));
  const tab10 = (Size(1005, 593), 1420 / 1005, EdgeInsets.only(top: 26));

  final igd = IgdDevice(
    location: Uri.parse('http://192.168.1.1:1900/rootDesc.xml'),
    info: const UpnpInfo(friendlyName: 'Archer AX53', manufacturer: 'TP-Link', modelName: 'Archer AX53', udn: 'uuid:x'),
    presentation: Uri.parse('http://192.168.1.1/'),
    wanConnection: IgdService('urn:schemas-upnp-org:service:WANIPConnection:1', Uri.parse('http://192.168.1.1/ctl')),
    wanCommon: IgdService('urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1', Uri.parse('http://192.168.1.1/c')),
  );
  final profile = RouterProfile(
    gateway: '192.168.1.1',
    adminUrl: Uri.parse('https://192.168.1.1/'),
    brand: RouterBrand.tplink,
    igd: igd,
    protocols: const {RouterProtocol.upnp},
  );

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
        routerProfileProvider.overrideWith((ref) async => profile),
        routerCredentialProvider.overrideWith((ref) async => const RouterCredential('', 'x')),
        routerDriverTypeProvider.overrideWith((ref) async => kRouterDrivers.first),
        routerManageProvider.overrideWith(_Sample.new),
        routerCapabilitiesProvider.overrideWith(
          (ref) async => const RouterCapabilities(
            identity: RouterIdentity(driver: 'luci-encrypted-web', model: 'Archer AX53', firmware: '1.7.1'),
            remote: {
              RouterActions.wifiToggle: ActionTrust.verified,
              RouterActions.guestToggle: ActionTrust.verified,
              RouterActions.guestEdit: ActionTrust.verified,
              RouterActions.iotToggle: ActionTrust.verified,
              RouterActions.reboot: ActionTrust.verified,
            },
            fresh: true,
          ),
        ),
        routerLiveProvider.overrideWith(
          (ref) => Stream.value(
            RouterLive(
              status: const IgdStatus(
                externalIp: '203.0.113.7',
                connectionStatus: 'Connected',
                uptime: Duration(days: 23, hours: 4),
                accessType: 'Ethernet',
                bytesReceived: 1,
                bytesSent: 1,
              ),
              downBps: 48.6e6,
              upBps: 9.2e6,
              history: [for (var i = 0; i < 40; i++) ((22 + (i * 13 % 31)) * 1e6, 6e6)],
            ),
          ),
        ),
        portMappingsProvider.overrideWith((ref) async => const <PortMapping>[]),
        toolStatusProvider.overrideWith(
          (ref) => {
            kPingTool: const ToolStatus('3 hosts', live: true),
            kTools[1]: const ToolStatus('21 hops · BD → SG'),
            kTools[2]: const ToolStatus('4 open · 53, 80, 443, …'),
            kTools[3]: const ToolStatus('94 ↓ · 38 ↑'),
            kTools[4]: const ToolStatus('0.4% · stable'),
            kTools[5]: const ToolStatus('9 devices'),
            kTools[6]: const ToolStatus('Singapore'),
            kMonitorTool: const ToolStatus('1 target · live', live: true),
            kRouterTool: const ToolStatus('Devices, Wi-Fi, internet, restart'),
          },
        ),
      ],
    );
  }

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget screen,
    String location,
    (Size, double, EdgeInsets) device, {
    double scroll = 0,
  }) async {
    final c = (await tester.runAsync(container))!;
    final sub = c.listen(routerManageProvider, (_, _) {});
    await tester.runAsync(() => c.read(routerProfileProvider.future));
    await tester.runAsync(() => c.read(routerDriverTypeProvider.future));
    await tester.runAsync(() => c.read(routerCredentialProvider.future));
    await tester.runAsync(() => c.read(routerManageProvider.future));
    await tester.runAsync(() => c.read(routerCapabilitiesProvider.future));
    final (size, ratio, padding) = device;
    await renderToPng(
      tester,
      '../store/$name',
      pulseTestApp(c, screen, brightness: Brightness.light, size: size, location: location, padding: padding),
      size: size,
      pixelRatio: ratio,
      before: scroll == 0
          ? null
          : () async {
              await tester.drag(find.byType(Scrollable).first, Offset(0, -scroll));
              await tester.pump(const Duration(milliseconds: 500));
            },
    );
    expect(tester.takeException(), isNull, reason: name);
    await tester.pumpWidget(const SizedBox());
    sub.close();
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('phone: tools', (t) => shot(t, 'phone-tools', const ToolsHubScreen(), '/tools', phone, scroll: 330));
  testWidgets('phone: router', (t) => shot(t, 'phone-router', const RouterScreen(), '/router', phone));
  testWidgets('phone: devices', (t) => shot(t, 'phone-devices', const RouterDevicesScreen(), '/router/devices', phone));
  testWidgets('phone: wifi', (t) => shot(t, 'phone-wifi', const RouterWifiScreen(), '/router/wifi', phone));
  testWidgets('7in: tools', (t) => shot(t, 'tab7-tools', const ToolsHubScreen(), '/tools', tab7));
  testWidgets('7in: router', (t) => shot(t, 'tab7-router', const RouterScreen(), '/router', tab7));
  testWidgets('10in: tools', (t) => shot(t, 'tab10-tools', const ToolsHubScreen(), '/tools', tab10));
  testWidgets('10in: router', (t) => shot(t, 'tab10-router', const RouterScreen(), '/router', tab10));
}

/// A home router with typical devices and networks (sample data).
class _Sample extends RouterManager {
  @override
  Future<RouterManaged?> build() async => const RouterManaged(
    features: {RouterFeature.overview, RouterFeature.clients, RouterFeature.wifi, RouterFeature.internet},
    actions: {
      RouterActions.wifiToggle,
      RouterActions.wifiEdit,
      RouterActions.guestToggle,
      RouterActions.guestEdit,
      RouterActions.iotToggle,
      RouterActions.iotEdit,
      RouterActions.reboot,
      RouterActions.internetType,
      RouterActions.internetEdit,
    },
    overview: RouterOverview(
      model: 'Archer AX53',
      hardwareVersion: 'Archer AX53 v1.0',
      firmware: '1.7.1 Build 20260213',
      wanIp: '203.0.113.7',
      wanType: 'dhcp',
      wanUptime: Duration(days: 23, hours: 4),
      lanIp: '192.168.1.1',
      cpu: .18,
      memory: .46,
      dhcpServer: true,
      internet: true,
    ),
    wan: WanConfig(
      available: WanType.values,
      current: WanType.dhcp,
      connected: true,
      ip: '203.0.113.7',
      gateway: '203.0.113.1',
      dns: ['1.1.1.1', '8.8.8.8'],
      settings: {WanType.dhcp: WanSettings(type: WanType.dhcp, hostname: 'Archer_AX53', mtu: 1500, manualDns: false)},
    ),
    clients: [
      RouterClient(
        mac: '02:00:00:00:00:01',
        ip: '192.168.1.20',
        name: 'Living-room TV',
        link: ClientLink.wifi5g,
        kind: 'tv',
        signal: -48,
        downBps: 24.8e6,
        upBps: 0.4e6,
        online: Duration(hours: 5, minutes: 12),
        trafficBytes: 18400000000,
      ),
      RouterClient(
        mac: '02:00:00:00:00:02',
        ip: '192.168.1.21',
        name: 'Work laptop',
        link: ClientLink.wired,
        kind: 'pc',
        downBps: 12.1e6,
        upBps: 6.3e6,
        online: Duration(hours: 7, minutes: 40),
        trafficBytes: 9200000000,
      ),
      RouterClient(
        mac: '02:00:00:00:00:03',
        ip: '192.168.1.22',
        name: 'Pixel 9',
        link: ClientLink.wifi5g,
        kind: 'mobile',
        signal: -55,
        downBps: 3.2e6,
        upBps: 0.9e6,
        online: Duration(hours: 2, minutes: 5),
        trafficBytes: 2100000000,
      ),
      RouterClient(
        mac: '02:00:00:00:00:04',
        ip: '192.168.1.23',
        name: 'Galaxy Tab',
        link: ClientLink.wifi5g,
        kind: 'tablet',
        signal: -61,
        downBps: 1.1e6,
        upBps: 0.2e6,
        online: Duration(hours: 1, minutes: 30),
        trafficBytes: 1300000000,
      ),
      RouterClient(
        mac: '02:00:00:00:00:05',
        ip: '192.168.1.24',
        name: 'Kitchen speaker',
        link: ClientLink.wifi2g,
        kind: 'speaker',
        signal: -66,
        online: Duration(days: 3),
        trafficBytes: 640000000,
      ),
      RouterClient(
        mac: '02:00:00:00:00:06',
        ip: '192.168.1.25',
        name: 'Printer',
        link: ClientLink.wifi2g,
        kind: 'printer',
        signal: -70,
        online: Duration(days: 12),
        trafficBytes: 52000000,
      ),
      RouterClient(
        mac: '02:00:00:00:00:07',
        ip: '192.168.1.40',
        name: "Guest's phone",
        link: ClientLink.wifi5g,
        guest: true,
        kind: 'mobile',
        signal: -58,
        online: Duration(minutes: 35),
        trafficBytes: 310000000,
      ),
    ],
    wifi: [
      WifiNetwork(
        id: 'wireless_2g',
        band: WifiBand.b24,
        enabled: true,
        ssid: 'Home Wi-Fi',
        password: 'sample-password',
        security: 'psk_sae',
        channel: 6,
      ),
      WifiNetwork(
        id: 'wireless_5g',
        band: WifiBand.b5,
        enabled: true,
        ssid: 'Home Wi-Fi',
        password: 'sample-password',
        security: 'psk_sae',
        channel: 44,
      ),
      WifiNetwork(
        id: 'guest_2g',
        band: WifiBand.b24,
        kind: WifiKind.guest,
        enabled: true,
        ssid: 'Home Guest',
        security: 'psk',
        password: 'welcome2026',
      ),
      WifiNetwork(
        id: 'iot_2g',
        band: WifiBand.b24,
        kind: WifiKind.iot,
        enabled: false,
        ssid: 'Home IoT',
        security: 'psk',
      ),
    ],
  );
}
