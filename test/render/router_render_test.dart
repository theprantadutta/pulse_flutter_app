@Tags(['render'])
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/data/db/app_database.dart';
import 'package:pulse/presentations/screens/router/router_screen.dart';
import 'package:pulse/providers/database_provider.dart';
import 'package:pulse/providers/router_manage_provider.dart';
import 'package:pulse/providers/router_provider.dart';
import 'package:pulse/services/net/router/drivers/router_driver.dart';
import 'package:pulse/providers/settings_provider.dart';
import 'package:pulse/services/net/lan/ssdp.dart';
import 'package:pulse/services/net/router/router_probe.dart';
import 'package:pulse/services/net/router/upnp_igd.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

final _igd = IgdDevice(
  location: Uri.parse('http://192.168.0.1:1900/rootDesc.xml'),
  info: const UpnpInfo(friendlyName: 'Archer AX53', manufacturer: 'TP-Link', modelName: 'Archer AX53', udn: 'uuid:x'),
  presentation: Uri.parse('http://192.168.0.1/'),
  wanConnection: IgdService('urn:schemas-upnp-org:service:WANIPConnection:1', Uri.parse('http://192.168.0.1:1900/ctl')),
  wanCommon: IgdService(
    'urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1',
    Uri.parse('http://192.168.0.1:1900/c'),
  ),
);

final _profile = RouterProfile(
  gateway: '192.168.0.1',
  adminUrl: Uri.parse('http://192.168.0.1/'),
  brand: RouterBrand.tplink,
  igd: _igd,
  protocols: const {RouterProtocol.upnp},
);

class _Signed extends RouterManager {
  @override
  Future<RouterManaged?> build() async => const RouterManaged(
    features: {RouterFeature.overview, RouterFeature.clients, RouterFeature.wifi, RouterFeature.reboot},
    overview: RouterOverview(
      model: 'Archer AX53',
      hardwareVersion: 'Archer AX53 v1.0',
      firmware: '1.7.1 Build 20260213 rel.87654(5553)',
      wanIp: '203.0.113.7',
      wanUptime: Duration(days: 71, hours: 6),
      lanIp: '192.168.0.1',
      cpu: .23,
      memory: .57,
      dhcpServer: true,
    ),
    clients: [
      RouterClient(
        mac: 'AA:BB:CC:00:00:01',
        ip: '192.168.0.25',
        name: 'Office-PC',
        link: ClientLink.wired,
        downBps: 8.2e6,
        upBps: 4e5,
      ),
      RouterClient(
        mac: 'AA:BB:CC:00:00:02',
        ip: '192.168.0.31',
        name: 'Galaxy-Tab-A9',
        link: ClientLink.wifi5g,
        signal: -52,
      ),
      RouterClient(mac: 'AA:BB:CC:00:00:03', ip: '192.168.0.40', link: ClientLink.wifi2g),
    ],
    wifi: [
      WifiNetwork(id: 'wireless_2g', band: WifiBand.b24, guest: false, enabled: true, ssid: 'Office Wi-Fi'),
      WifiNetwork(id: 'wireless_5g', band: WifiBand.b5, guest: false, enabled: true, ssid: 'Office Wi-Fi'),
      WifiNetwork(id: 'guest_2g', band: WifiBand.b24, guest: true, enabled: false, ssid: 'Guest'),
    ],
  );
}

void main() {
  setUpAll(loadPulseFonts);

  Future<ProviderContainer> container({RouterProfile? profile, bool login = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
        routerProfileProvider.overrideWith((ref) async => profile),
        routerLiveProvider.overrideWith(
          (ref) => Stream.value(
            RouterLive(
              status: const IgdStatus(
                externalIp: '203.0.113.7',
                connectionStatus: 'Connected',
                uptime: Duration(days: 70, hours: 14),
                accessType: 'Cable',
                bytesReceived: 1,
                bytesSent: 1,
              ),
              downBps: 10.3e6,
              upBps: 1.2e6,
              history: [for (var i = 0; i < 30; i++) ((4 + (i * 7 % 9)) * 1e6, 1e6)],
            ),
          ),
        ),
        portMappingsProvider.overrideWith(
          (ref) async => const [
            PortMapping(
              protocol: 'TCP',
              externalPort: 29693,
              internalClient: '192.168.0.25',
              internalPort: 7070,
              description: 'AnyDesk',
            ),
          ],
        ),
        routerCredentialProvider.overrideWith((ref) async => login ? const RouterCredential('admin', 'x') : null),
      ],
    );
  }

  testWidgets('router with UPnP', (tester) async {
    final c = (await tester.runAsync(() => container(profile: _profile)))!;
    await tester.runAsync(() => c.read(routerProfileProvider.future));
    final failures = await renderMatrix(tester, 'router', c, const RouterScreen(), location: '/router');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(failures, isEmpty);
  });

  testWidgets('router without UPnP, no login', (tester) async {
    final p = RouterProfile(
      gateway: '192.168.1.1',
      adminUrl: Uri.parse('http://192.168.1.1/'),
      brand: RouterBrand.unknown,
    );
    final c = (await tester.runAsync(() => container(profile: p, login: false)))!;
    await tester.runAsync(() => c.read(routerProfileProvider.future));
    final failures = await renderMatrix(
      tester,
      'router_basic',
      c,
      const RouterScreen(),
      location: '/router',
      devices: const {'phone': kPhone},
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(failures, isEmpty);
  });

  testWidgets('router signed in (native TP-Link screens)', (tester) async {
    final c = (await tester.runAsync(() => container(profile: _profile)))!;
    final signed = ProviderContainer(parent: c, overrides: [routerManageProvider.overrideWith(_Signed.new)]);
    await tester.runAsync(() => signed.read(routerProfileProvider.future));
    await tester.runAsync(() => signed.read(routerManageProvider.future));
    final failures = await renderMatrix(
      tester,
      'router_signed',
      signed,
      const RouterScreen(),
      location: '/router',
      devices: const {'phone_tall': Size(390, 2600), 'tablet': kTablet},
    );
    await tester.pumpWidget(const SizedBox());
    signed.dispose();
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(failures, isEmpty);
  });
}
