# Router feature map: what a full router UI offers, and how Pulse reaches it

Captured on 2026-11-18 from the office **Archer AX53** web UI (firmware 1.7.1, web app 1.11) by walking every menu
page and recording the API calls each page makes. This is the reference for Pulse's Router screen: every row below
is a feature a person can use in their router's own page. The **driver** column says how the encrypted LuCI web
driver reaches it. Other drivers (TR-064, OpenWrt, RouterOS…) map their own calls onto the same Pulse features.

All calls are `POST /cgi-bin/luci/;stok=<token>/<module>?form=<form>` with form-encoded bodies
(`operation=read|write|load|insert|update|remove`, plain over HTTPS). Pages always also read `device_config?form=config`.

## Pulse sections ⇄ router features

### Overview
| Feature | Router page | Endpoints |
| --- | --- | --- |
| Internet status: type, IP, gateway, DNS, online time | Network Map / Network › Status | `admin/status?form=internet`, `admin/status?form=all`, `admin/network?form=status_ipv4`, `wan_ipv4_status` |
| Router health (CPU, memory), model, firmware | Network Map, System › About | `admin/status?form=all`, `admin/firmware?form=upgrade` |
| Mesh devices (satellites, their clients) | Network Map › Mesh Devices, EasyMesh | `admin/easymesh?form=easymesh_enable`, `admin/easymesh_network?form=get_mesh_device_list_all`, `mesh_sclient_list_all` |
| Network map summary | Network Map | `admin/status?form=network_map` |

### Devices (clients)
| Feature | Router page | Endpoints |
| --- | --- | --- |
| Online clients: name, MAC, IP, band, live up/down rate | Network Map › Clients | `admin/status?form=all` (access_devices_*), `admin/smart_network?form=game_accelerator` (`loadDevice`) |
| Per-client speed limit | Clients › Speed Limit | `admin/smart_network?form=client_speed_limit` |
| Block / unblock a device (blocklist) | Clients › block icon, Security › Access Control | `admin/access_control?form=enable`, `form=mode`, `form=black_devices`, `form=white_devices` |
| Rename / set device type | Clients › Modify | `admin/smart_network?form=game_accelerator` (device fields) |
| DHCP client list (leases) | Network › DHCP Server | `admin/dhcps?form=client` (`load`) |
| Address reservations | DHCP Server › Address Reservation | `admin/dhcps?form=reservation` (`load`/`insert`/`update`/`remove`) |
| IP & MAC binding, ARP list | Security › IP & MAC Binding | `admin/imb?form=setting`, `arp_list`, `bind_list` |
| Wake-on-LAN | Wake on LAN | `admin/wol?form=device` |

### Wi-Fi
| Feature | Router page | Endpoints |
| --- | --- | --- |
| Main networks per band: on/off, name, password, security, hidden, channel, width, power | Wireless › Wireless Settings | `admin/wireless?form=wireless_2g`, `wireless_5g`, `syspara_2g`, `syspara_5g`, `region` |
| Smart Connect (one name for all bands) | Wireless Settings | `admin/wireless?form=smart_connect` |
| Guest network: on/off, name, password, bandwidth limit, access to local network | Wireless › Guest Network | `admin/wireless?form=guest`, `form=guest_2g&form=guest_5g&form=guest_2g5g`, `guestnetwork_bandwidth_ctrl` |
| IoT network | Wireless › IoT Network | `admin/wireless?form=iot_2g&form=iot_5g&form=iot_5g_2` |
| Wireless schedule (Wi-Fi off at night) | Wireless › Wireless Schedule | `admin/wireless_schedule_v2?form=settings`, `admin/time?form=settings` |
| WPS (push button / PIN) | Wireless › WPS | `admin/wireless?form=syspara_wps`, `wps_connect`, `wps_pin` |
| OFDMA, TWT, airtime, beamforming… | Wireless › Additional Settings | `admin/wireless?form=wireless_addition_setting`, `ofdma`, `twt` |

### Ports & NAT
| Feature | Router page | Endpoints |
| --- | --- | --- |
| Port forwarding (virtual servers) | NAT Forwarding › Port Forwarding | `admin/nat?form=vs` (`load`/`insert`/`update`/`remove`) |
| Port triggering | NAT Forwarding › Port Triggering | `admin/nat?form=pt` |
| UPnP on/off and its current mappings | NAT Forwarding › UPnP | `admin/upnp?form=enable`, `admin/upnp?form=service`, `admin/nat?form=setting` |
| DMZ host | NAT Forwarding › DMZ | `admin/nat?form=dmz` |
| ALG (SIP, FTP, PPTP, IPsec passthrough) | Security › ALG | `admin/nat?form=alg` |

### Security
| Feature | Router page | Endpoints |
| --- | --- | --- |
| Firewall (SPI) and DoS protection | Security › Firewall | `admin/security_settings?form=new_enable` |
| Device isolation (IoT/main isolation lists) | Security › Device Isolation | `admin/iot_security?form=enable`, `isolated_list`, `isolated_devices_main`, `isolated_devices_iot` |
| HomeShield (parental controls, QoS, security scans) | HomeShield | App/cloud feature on this model: the web page only links to the Tether app |

### Network
| Feature | Router page | Endpoints |
| --- | --- | --- |
| LAN IP / subnet | Network › LAN | `admin/network?form=lan_ipv4`, `lan_ipv6` |
| DHCP server settings (pool, lease, DNS) | Network › DHCP Server | `admin/dhcps?form=setting` |
| Dynamic DNS | Network › Dynamic DNS | `admin/ddns?form=provider`, `admin/ddns?form=tplink` |
| Static routes, routing table | Network › Routing | `admin/network?form=routes_static`, `routes_system` |
| IPv6 | IPv6 | `admin/network?form=wan_ipv6_*`, `lan_ipv6` |
| Internet connection type (read only in Pulse) | Network › Internet | `admin/network?form=wan_ipv4_protos`, `wan_ipv6_protos`, `wan_dohdot` |

### VPN
| Feature | Router page | Endpoints |
| --- | --- | --- |
| VPN client (route chosen devices through a VPN) | VPN Client | `admin/vpn?form=enable`, `admin/vpn?form=thirdvpn` |
| VPN servers: OpenVPN, PPTP, WireGuard (+ accounts) | VPN Server | `admin/openvpn?form=config`, `admin/pptpd?form=config`, `admin/wireguard?form=config`, `admin/wireguard?form=account` |
| Who's connected over VPN | VPN Server › Connections | `admin/vpnconn?form=config` |

### System
| Feature | Router page | Endpoints |
| --- | --- | --- |
| Firmware version and update check | System › Firmware Update | `admin/firmware?form=upgrade`, `auto_upgrade`, `admin/cloud_account?form=cloud_upgrade` |
| Reboot now / reboot schedule | System › Reboot | `admin/system?form=reboot`, `admin/reboot?form=set` |
| LED on/off, night mode | System › LED Control | `admin/ledgeneral?form=setting`, `admin/ledpm?form=setting` |
| ECO mode | System › ECO Mode | `admin/eco_mode?form=settings` |
| System log | System › System Log | `admin/syslog?form=…`, `admin/time?form=settings` |
| Diagnostics (ping/traceroute from the router) | System › Diagnostics | `admin/diag?form=diag` |
| Time settings | System › Time Settings | `admin/time?form=settings` |
| Backup / restore, admin password, operation mode | System › … | **router page only** (Pulse never changes these) |

## Read vs write policy for this driver
- **Read** everything above (except backup, admin password and operation mode) through the per-feature probe.
- **Write**, once verified on hardware or by users' "it worked" reports through the backend: Wi-Fi on/off, name and
  password; guest on/off; block/unblock; speed limit; reservations; port forwards; UPnP on/off; DMZ; LED; ECO;
  Wi-Fi schedule; reboot and reboot schedule; WPS push.
- **Never** from Pulse: internet connection type, LAN subnet, firmware flashing, backup/restore, admin password,
  operation mode, factory reset.
