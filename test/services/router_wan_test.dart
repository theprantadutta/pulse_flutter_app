import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/providers/router_manage_provider.dart';
import 'package:pulse/services/net/router/drivers/router_driver.dart';
import 'package:pulse/services/net/router/drivers/tplink_driver.dart';

void main() {
  test('static IP maps to the web UI keys', () {
    expect(
      TplinkDriver.wanFields(
        const WanSettings(
          type: WanType.static,
          ip: '198.51.100.21',
          netmask: '255.255.255.0',
          gateway: '198.51.100.1',
          dns1: '1.1.1.1',
          dns2: '',
          mtu: 1500,
        ),
      ),
      {
        'mtu': '1500',
        'ipaddr': '198.51.100.21',
        'netmask': '255.255.255.0',
        'gateway': '198.51.100.1',
        'pri_dns': '1.1.1.1',
        'snd_dns': '',
      },
    );
  });

  test('dynamic IP: provider DNS unless manual', () {
    expect(TplinkDriver.wanFields(const WanSettings(type: WanType.dhcp, manualDns: false)), {'dns_mode': 'dynamic'});
    expect(TplinkDriver.wanFields(const WanSettings(type: WanType.dhcp, manualDns: true, dns1: '9.9.9.9')), {
      'dns_mode': 'static',
      'manual_pridns': '9.9.9.9',
      'manual_snddns': '',
    });
  });

  test('PPPoE and L2TP logins', () {
    expect(TplinkDriver.wanFields(const WanSettings(type: WanType.pppoe, username: 'u', password: 'p')), {
      'username': 'u',
      'password': 'p',
    });
    expect(
      TplinkDriver.wanFields(
        const WanSettings(type: WanType.l2tp, username: 'u', password: 'p', server: 'vpn.isp', secondaryStatic: false),
      ),
      {'username': 'u', 'password': 'p', 'snd_conn': 'dynamic', 'dyn_server': 'vpn.isp'},
    );
    expect(
      TplinkDriver.wanFields(
        const WanSettings(type: WanType.pptp, server: '10.0.0.1', secondaryStatic: true, ip: '10.0.0.5'),
      ),
      {'snd_conn': 'static', 'static_server': '10.0.0.1', 'static_ip': '10.0.0.5'},
    );
  });

  test('read-back match ignores passwords and unset fields', () {
    const read = WanSettings(type: WanType.pppoe, username: 'u', mtu: 1480);
    expect(wanMatches(read, const WanSettings(type: WanType.pppoe, username: 'u', password: 'secret')), isTrue);
    expect(wanMatches(read, const WanSettings(type: WanType.pppoe, username: 'x')), isFalse);
    expect(wanMatches(null, const WanSettings(type: WanType.pppoe)), isFalse);
  });
}
