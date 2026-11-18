# Router control from Pulse — feasibility research (Nov 2026)

Branch: `feature/router-control` (not for master until the owner decides).

**Question:** can people sign in to their router from Pulse and do everything they could do in the router's
own admin page, across different brands, layouts and feature sets?

**Short answer:** not as one universal native client. There is no common router-management standard that
consumer routers implement. But a **layered** design gets close:
1. A universal "router admin" browser inside Pulse covers 100% of routers and 100% of their features.
2. Standard protocols (UPnP IGD, TR-064, SNMP) add native read-outs and a few actions on many routers
   with no brand-specific code.
3. Native "drivers" for router families with real APIs add full in-app control for those brands.

Pulse's own screens then show only what a given router supports, and hand everything else to the
router's own page.

---

## 1. How routers can be controlled

| Layer | What it is | Coverage | Control depth | Stability |
| --- | --- | --- | --- | --- |
| **A. Admin page in a WebView** | Open `http(s)://<gateway>` inside Pulse, keep the login, autofill credentials | Every router with a web UI | Everything the vendor UI offers | Always works (it *is* the vendor UI) |
| **B. UPnP IGD** | Standard SOAP service many routers expose without a login (if UPnP is on) | Most consumer routers | WAN IP, uptime, link speed, bytes in/out, list/add/remove port mappings | Very stable, standardised |
| **C. TR-064** | Broadband Forum LAN-side SOAP management (HTTP digest login) | AVM FRITZ!Box (all), some ISP gateways | Hosts, Wi-Fi on/off and guest Wi-Fi, reboot, DSL/WAN stats, logs, port forwards, phone features | Stable, versioned per firmware |
| **D. SNMP** | Read-mostly MIB polling | Business and prosumer gear | Interfaces, traffic, uptime, CPU | Stable |
| **E. Documented vendor APIs** | Official local or controller APIs | OpenWrt (ubus JSON-RPC / LuCI RPC), MikroTik RouterOS (REST in v7, binary API), pfSense/OPNsense REST, Ubiquiti UniFi and TP-Link Omada controllers, Synology SRM | Essentially full control | Stable, documented |
| **F. Reverse-engineered consumer web APIs** | The JSON/SOAP calls the router's own web page makes | TP-Link Archer/Deco/Mercusys (encrypted JSON), ASUS (asuswrt httpd `appGet`/`applyapp`), Netgear (SOAP "Genie" API), Huawei HiLink, Xiaomi MiWiFi, Linksys (JNAP), D-Link (HNAP), Tenda | Partial: status, clients, Wi-Fi, reboot, sometimes block lists and guest Wi-Fi | Breaks with firmware updates; different per model and hardware version |
| **Not reachable** | Cloud-only mesh systems and locked ISP boxes | eero, Google/Nest Wifi, many ISP-locked gateways | Only through the vendor's cloud or app (no public API) | — |

Evidence that layer F works in practice: open-source clients already exist and are maintained, e.g.
`tplinkrouterc6u` (TP-Link and Mercusys, used by the Home Assistant integration; recent releases list the
**Archer AX53 v2**, the office router), asuswrt libraries, `pynetgear`, `huawei-lte-api`, and Home
Assistant's built-in ASUSWRT, Netgear, MikroTik, OpenWrt (LuCI and ubus) and FRITZ!Box integrations.
They also show the limits: most only cover presence and status, plus a handful of actions.

## 2. Why "everything, for every router" natively isn't realistic

- **No common model.** Every vendor names and structures settings differently (Wi-Fi bands, mesh nodes,
  QoS, parental controls, VPN, IPv6, ISP-specific WAN types). Mirroring all of it natively means
  re-implementing every vendor's UI.
- **Moving targets.** Consumer firmware changes its private APIs and encryption (TP-Link has changed its
  login scheme several times). Each driver needs real hardware to test and maintain.
- **Risky operations.** WAN/PPPoE settings, firmware updates, factory reset, VLANs and so on can cut the
  user off their own network. A third-party app getting one of these wrong is far worse than a wrong
  ping graph.
- **Single-session routers.** Many consumer routers allow one admin session at a time, so signing in from
  Pulse logs out the browser (and the reverse). Some lock the account after failed logins.

## 3. What is feasible: a capability-based design

A driver per router family declares the **capabilities** it supports. Pulse renders only those, and
every screen has "Open in router page" (layer A) for the rest.

| Capability | B UPnP | C TR-064 | E OpenWrt / MikroTik | F TP-Link / ASUS / Netgear (typical) |
| --- | --- | --- | --- | --- |
| Router model, firmware, uptime | partly | ✓ | ✓ | ✓ |
| WAN IP, link, traffic counters | ✓ | ✓ | ✓ | ✓ |
| Connected devices (name, IP, MAC, band, signal) | — | ✓ | ✓ | ✓ |
| Block / unblock a device | — | some | ✓ | most |
| Wi-Fi on/off, SSID, password, guest Wi-Fi | — | ✓ | ✓ | most |
| Reboot | — | ✓ | ✓ | ✓ |
| Port forwarding | ✓ (UPnP mappings) | ✓ | ✓ | some |
| DHCP reservations | — | some | ✓ | some |
| Logs | — | ✓ | ✓ | some |
| Firmware update check | — | ✓ | ✓ | some |

This fits Pulse naturally: the LAN screen already identifies devices, and router client lists would give
it real names and MACs (Android can't read MACs itself). Monitor could alert on WAN drops reported by the
router, and Network could show WAN details straight from the router.

### Detection (no login needed)
- Gateway IP: already known (`gatewayProvider`).
- UPnP description XML: manufacturer, model and firmware (Pulse already parses SSDP).
- Probes: `:49000/tr64desc.xml` (TR-064), `/ubus` or `/cgi-bin/luci` (OpenWrt), RouterOS REST/API ports,
  HTTP `Server` header and page title fingerprints (TP-Link, ASUS, Netgear, Huawei…).
- Result: "TP-Link Archer AX53 · native support: status, devices, Wi-Fi, reboot" or "Unknown router ·
  admin page only".

### Credentials and safety
- Admin passwords stay on the device in the OS keystore (`flutter_secure_storage`: Android Keystore, iOS
  Keychain, Windows DPAPI) and are never sent anywhere but the router. That fits Pulse's privacy policy, but
  the policy text needs a new section, and Play's Data safety form needs an update.
- Talk to the router only on the local network, at the gateway address the OS reports. Trust self-signed
  router certificates per router (pin on first use), never globally.
- Destructive actions (reboot, Wi-Fi changes, blocking) need explicit confirmation and show what will
  disconnect. Out of scope by design: WAN/PPPoE changes, firmware flashing, factory reset; those go to the
  router page.
- Show plainly when Pulse's session will log the person out of the router's web page.

### Platform notes
- **Android 17:** apps targeting API 37 need the runtime `ACCESS_LOCAL_NETWORK` permission for LAN
  connections (permission_handler 13 already knows it; Pulse's compileSdk is 37). This matters for LAN scan
  today too, not just this feature.
- **iOS:** the Local Network prompt (`NSLocalNetworkUsageDescription`) is already in Info.plist; WebView and
  HTTP to the gateway work after consent.
- **Desktop (Windows/macOS):** no restrictions; arguably the best place for an admin-style feature.
- **Play policy:** managing the user's *own* router with their own credentials is fine (TP-Link Tether,
  ASUS Router, Fing and generic "router admin" apps exist). The listing should say clearly that it needs
  the router password and only works on the router you're connected to.

## 4. Suggested phases

1. **Router hub + universal admin page (all routers).** Detect the router, store credentials, in-app
   admin browser with autofill, plus UPnP IGD read-outs and port-mapping management. *About 1–2 weeks.*
2. **Standard and documented drivers:** TR-064 (FRITZ!Box, some ISP gateways), OpenWrt, MikroTik.
   *About 3–5 days each*, testable with emulated OpenWrt/RouterOS (both run in a VM).
3. **Consumer drivers, one family at a time:** TP-Link first (the office Archer AX53 is real test hardware),
   then ASUS and Netgear. *About 1–2 weeks each, then ongoing upkeep as firmware changes.*

## 5. Verdict

- **Feasible:** a Router area that works with every router (admin page inside Pulse) and gives native,
  Pulse-styled status, device lists and common actions on routers with real or well-understood APIs.
- **Not feasible:** "everything a router can do, natively, for every router." No standard exists, consumer
  APIs are private and change, and the long tail of models makes it unmaintainable.
- **Biggest costs:** test hardware for each family and keeping reverse-engineered drivers working across
  firmware updates.

## Sources
- TP-Link/Mercusys client library and supported routers: https://github.com/AlexandrErohin/TP-Link-Archer-C6U ·
  https://pypi.org/project/tplinkrouterc6u/
- AVM TR-064 interfaces: https://fritz.com/en/pages/interfaces · https://fritzconnection.readthedocs.io/en/latest/sources/getting_started.html
- Home Assistant router integrations: https://www.home-assistant.io/integrations/category/computers_network/routers_network/ ·
  https://www.home-assistant.io/integrations/asuswrt/ · https://www.home-assistant.io/integrations/netgear/ ·
  https://www.home-assistant.io/integrations/mikrotik
- Android local network permission: https://developer.android.com/privacy-and-security/local-network-permission ·
  https://docs.flutter.dev/platform-integration/android/local-network-permission
