@Tags(['render'])
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/data/db/app_database.dart';
import 'package:pulse/presentations/screens/router/router_devices_screen.dart';
import 'package:pulse/presentations/screens/router/router_internet_screen.dart';
import 'package:pulse/presentations/screens/router/router_screen.dart';
import 'package:pulse/presentations/screens/router/router_wifi_screen.dart';
import 'package:pulse/services/net/router/verification.dart';
import 'package:pulse/providers/database_provider.dart';
import 'package:pulse/providers/router_manage_provider.dart';
import 'package:pulse/providers/router_provider.dart';
import 'package:pulse/services/net/router/drivers/driver_registry.dart';
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
      firmware: '1.7.1 Build 20260213 rel.87654(5553)',
      wanIp: '203.0.113.7',
      wanUptime: Duration(days: 71, hours: 6),
      lanIp: '192.168.0.1',
      cpu: .23,
      memory: .57,
      dhcpServer: true,
      internet: true,
      wanType: 'static',
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
        online: Duration(hours: 2, minutes: 40),
        trafficBytes: 1834000000,
        kind: 'tablet',
        downBps: 1.6e6,
        upBps: 2e5,
      ),
      RouterClient(
        mac: 'AA:BB:CC:00:00:04',
        ip: '192.168.0.52',
        name: 'Visitor-Phone',
        link: ClientLink.wifi2g,
        guest: true,
        signal: -71,
        kind: 'phone',
      ),
      RouterClient(mac: 'AA:BB:CC:00:00:03', ip: '192.168.0.40', link: ClientLink.wifi2g),
    ],
    wan: WanConfig(
      available: WanType.values,
      current: WanType.static,
      connected: true,
      ip: '198.51.100.21',
      gateway: '198.51.100.1',
      dns: ['198.51.100.5', '198.51.100.6'],
      settings: {
        WanType.static: WanSettings(
          type: WanType.static,
          ip: '198.51.100.21',
          netmask: '255.255.255.0',
          gateway: '198.51.100.1',
          dns1: '198.51.100.5',
          dns2: '198.51.100.6',
          mtu: 1500,
        ),
        WanType.dhcp: WanSettings(type: WanType.dhcp, hostname: 'Archer_AX53', mtu: 1500, manualDns: false),
        WanType.pppoe: WanSettings(type: WanType.pppoe, mtu: 1480, manualDns: false),
      },
    ),
    wifi: [
      WifiNetwork(
        id: 'wireless_2g',
        band: WifiBand.b24,
        enabled: true,
        ssid: 'Office Wi-Fi',
        password: 'correct-horse-battery',
        security: 'psk_sae',
        channel: 9,
      ),
      WifiNetwork(
        id: 'wireless_5g',
        band: WifiBand.b5,
        enabled: true,
        ssid: 'Office Wi-Fi',
        password: 'correct-horse-battery',
        security: 'psk_sae',
        channel: 149,
      ),
      WifiNetwork(
        id: 'guest_2g',
        band: WifiBand.b24,
        kind: WifiKind.guest,
        enabled: false,
        ssid: 'Guest',
        security: 'none',
      ),
      WifiNetwork(
        id: 'iot_2g',
        band: WifiBand.b24,
        kind: WifiKind.iot,
        enabled: false,
        ssid: 'Office_IoT_2.4G',
        password: 'iotpass12',
        security: 'psk',
      ),
    ],
  );
}

class _WrongPassword extends RouterManager {
  @override
  Future<RouterManaged?> build() async =>
      throw const RouterDriverException(RouterErrorKind.wrongPassword, 'login failed');
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
        // A driver for the full profile, none for the basic one (no network probes in tests).
        routerDriverTypeProvider.overrideWith((ref) async => profile?.igd == null ? null : kRouterDrivers.first),
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

  testWidgets('login dialog fits a phone with the keyboard up', (tester) async {
    final c = (await tester.runAsync(() => container(profile: _profile, login: false)))!;
    await tester.runAsync(() => c.read(routerProfileProvider.future));
    await tester.runAsync(() => c.read(routerDriverTypeProvider.future));
    // A24 width with about half the height taken by the keyboard.
    const size = Size(390, 470);
    await renderToPng(
      tester,
      'router_login_keyboard',
      pulseTestApp(c, const RouterScreen(), size: size, location: '/router'),
      size: size,
    );
    FlutterSecureStorage.setMockInitialValues({});
    await tester.ensureVisible(find.text('Sign in to router'));
    await tester.pump();
    await tester.tap(find.text('Sign in to router'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Remember on this device'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('wrong password: "Enter again" reopens the password form', (tester) async {
    final c = (await tester.runAsync(() => container(profile: _profile)))!;
    final failed = ProviderContainer(parent: c, overrides: [routerManageProvider.overrideWith(_WrongPassword.new)]);
    await tester.runAsync(() => failed.read(routerProfileProvider.future));
    await tester.runAsync(() => failed.read(routerDriverTypeProvider.future));
    await tester.runAsync(() => failed.read(routerCredentialProvider.future));
    final sub = failed.listen(routerManageProvider, (_, _) {});
    await tester.runAsync(() => failed.read(routerManageProvider.future).then<void>((_) {}, onError: (_) {}));
    FlutterSecureStorage.setMockInitialValues({});
    await renderToPng(
      tester,
      'router_wrong_password',
      pulseTestApp(failed, const RouterScreen(), size: kPhone, location: '/router'),
      size: kPhone,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Wrong password'), findsOneWidget);
    await tester.ensureVisible(find.text('Enter again'));
    await tester.tap(find.text('Enter again'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Remember on this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    sub.close();
    failed.dispose();
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
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

  const id = RouterIdentity(driver: 'luci-encrypted-web', model: 'Archer AX53', firmware: '1.7.1');

  for (final (name, screen, location, devices) in [
    (
      'router_signed',
      const RouterScreen() as Widget,
      '/router',
      const {
        'phone_tall': Size(390, 2400),
        'phone_small': Size(360, 2400),
        'tablet': kTablet,
        'desktop': Size(1440, 1100),
      },
    ),
    ('router_devices', const RouterDevicesScreen(), '/router/devices', const {'phone': kPhone, 'tablet': kTablet}),
    ('router_wifi', const RouterWifiScreen(), '/router/wifi', const {'phone_tall': Size(390, 1900), 'tablet': kTablet}),
    (
      'router_internet',
      const RouterInternetScreen(),
      '/router/internet',
      const {'phone_tall': Size(390, 1700), 'tablet': kTablet, 'desktop': Size(1440, 1000)},
    ),
  ]) {
    testWidgets('signed in: $name', (tester) async {
      final c = (await tester.runAsync(() => container(profile: _profile)))!;
      final signed = ProviderContainer(
        parent: c,
        overrides: [
          routerManageProvider.overrideWith(_Signed.new),
          routerCapabilitiesProvider.overrideWith(
            (ref) async => const RouterCapabilities(
              identity: id,
              remote: {RouterActions.wifiToggle: ActionTrust.verified, RouterActions.reboot: ActionTrust.verified},
              fresh: true,
            ),
          ),
        ],
      );
      await tester.runAsync(() => signed.read(routerProfileProvider.future));
      await tester.runAsync(() => signed.read(routerManageProvider.future));
      await tester.runAsync(() => signed.read(routerCapabilitiesProvider.future));
      final failures = await renderMatrix(tester, name, signed, screen, location: location, devices: devices);
      await tester.pumpWidget(const SizedBox());
      signed.dispose();
      c.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(failures, isEmpty);
    });
  }
}
