# Any router in Pulse — the plan (Nov 2026)

Branch: `feature/router-control`. Builds on `docs/ROUTER_CONTROL_RESEARCH.md` (feasibility) and what already
works: detection, UPnP, the in-app router page, and a signed-in driver for one encrypted LuCI web API (verified on
the office Archer AX53).

## The promise to users

1. **Every router works in Pulse at some level**, and the level is decided by what Pulse can actually verify on
   *that* router, never by guessing from the brand.
2. **Pulse only shows what it has proven it can do on this router right now.** A feature appears only after Pulse has
   read it successfully from the router. A change (write) is offered only where Pulse has verified writes for that
   router family, and every change is read back to confirm it took effect.
3. **There is always a way to do everything:** the router's own page inside Pulse ("Full router settings"), with the
   login filled in.
4. **Pulse never risks cutting someone off:** no internet/WAN settings, firmware flashing or factory reset from Pulse;
   clear warnings before anything that disconnects devices; and no retrying a wrong password.

## 1. Support ladder (every router lands on the highest rung it proves)

| Rung | What it gives | Needs | How Pulse proves it |
| --- | --- | --- | --- |
| 0 | Explanation ("no router on mobile data") | — | No gateway |
| 1 | **Router page in Pulse** + saved login autofill | Router has a web page | Gateway answers HTTP(S) |
| 2 | **UPnP IGD**: internet status, live traffic, UPnP port forwards | UPnP on | Description XML + a successful SOAP read |
| 3 | **TR-064** (no login for some reads, digest login for the rest): devices, Wi-Fi, guest Wi-Fi, reboot, logs | FRITZ!Box and some ISP gateways | `tr64desc.xml` + each service's actions listed in its SCPD |
| 4 | **Native driver, signed in**: whatever that driver's verified features are | Router password | Driver probe (no credentials) → sign-in → per-feature read |

Rungs stack: a signed-in router still shows UPnP data, and Full router settings is always there.

## 2. Capability model (what makes "only show what works" real)

Each driver declares features as **read** and **write** separately, e.g. `devices.read`, `devices.block`,
`wifi.read`, `wifi.toggle`, `wifi.edit`, `guest.toggle`, `reboot`, `forwards.read`, `forwards.edit`,
`dhcp.leases`, `reservations.edit`, `system.health`, `wan.status`.

At runtime, after sign-in:
- **Read features:** Pulse calls each read once. A section appears only if the call succeeds **and** the response
  parses into sane values (non-empty model, valid MACs/IPs). Missing pages or odd data are hidden, never shown as
  errors. Results are cached per router + firmware version, so the screen opens instantly next time and the probe is
  re-run when the firmware changes.
- **Write features** are offered only when all of these hold:
  1. the driver's **verified matrix** lists that write for this firmware family (recorded from real hardware or an
     official emulator, see §5);
  2. the matching read worked in this session (so Pulse knows the current value);
  3. the change is not on the deny list (WAN, firmware, reset, admin password, VLANs).
- **Every write is read back.** If the router's value didn't change, Pulse says so plainly and offers Full router
  settings. It never claims success it didn't see.
- **Unverified firmware of a known family** (same API, new version): reads still go through the probe; writes stay
  hidden until verified, with a note: "Changes for this firmware open in the router page."

The "What Pulse can do with this router" list is generated from these results, so it can't promise more than the
screen delivers.

## 3. Drivers: what to build, in order

Ranked by **(users covered) × (how stable the API is) ÷ (how hard it is to test)**.

### Tier A — documented or standard APIs, testable without buying hardware
| Driver | Covers | API | Test plan |
| --- | --- | --- | --- |
| **TR-064** | FRITZ!Box (official, fully documented services), some ISP gateways (spec'd by the Broadband Forum) | SOAP + HTTP digest, service list self-described | Recorded FRITZ!Box responses (AVM publishes the service docs); real device later |
| **OpenWrt (ubus/rpcd)** | OpenWrt and its many derivatives (GL.iNet, Turris, Teltonika-style UIs) | JSON-RPC 2.0 at `/ubus`, `session.login`, ACL-checked | **OpenWrt x86 VM** (QEMU/VirtualBox, official images) |
| **MikroTik RouterOS** | All MikroTik on v7.1+ | Official REST at `/rest/...` (HTTPS) | **CHR VM**: free licence, all features (1 Mbps cap irrelevant here) |
| **OPNsense / pfSense** | Prosumer firewalls | Official REST APIs (API key) | VMs |
| **UniFi Network** | UniFi gateways/consoles | Official local API with `X-API-KEY` (Network 9.1+) | Needs a UniFi console; fixtures from the published docs |
| **Omada controller** | TP-Link business gear | Official Open API (client credentials) | Software controller in a VM/Docker |

### Tier B — reverse-engineered consumer web APIs (real hardware needed for writes)
| Driver | Covers | Notes |
| --- | --- | --- |
| **Encrypted LuCI web** (done) | TP-Link Archer/Deco family, Mercusys | Plain over HTTPS, AES/SG over HTTP; verified read on AX53 |
| **ASUSWRT** | ASUS stock + Merlin | `login.cgi` then `appGet.cgi` hooks; `applyapp.cgi` for changes. Mature community client (asusrouter) |
| **Netgear SOAP** | Most Nighthawk/Orbi | SOAP API the Genie/Nighthawk app uses; device list includes allow/block state |
| **Linksys JNAP** | Linksys EA/Velop | POST `/JNAP/` with `X-JNAP-Action`; Basic auth header |
| **Xiaomi MiWiFi** | Xiaomi/Redmi routers | LuCI token login (nonce + SHA-1); `;stok=` URLs |
| **Huawei HiLink** | Huawei home/LTE routers (B-series) | Well-documented community API (huawei-lte-api) |
| **Keenetic RCI** | Keenetic | `/rci/` REST mirroring their CLI; `/auth` session |
| **Synology SRM** | Synology routers | DSM-style web API |

### Not reachable (they stay on rungs 1–2)
- **Cloud-only mesh:** eero, Google/Nest Wifi. No local API.
- **ISP-locked boxes** with no local API (many ONTs and gateways vary per ISP firmware).
- **D-Link HNAP:** a legacy SOAP API with a long history of security problems. Pulse shouldn't depend on it; it gets
  rungs 1–2.

## 4. Detection (no credentials, ever)

`RouterProbe` already gathers the UPnP description, admin page title and server header, and TR-064/LuCI hints. Each
driver adds a **cheap probe**, a single request that only its protocol answers in a recognisable way, for example:
- `/login?form=keys` returns a JSON RSA key (encrypted LuCI web);
- `/ubus` answers JSON-RPC (OpenWrt);
- `/rest/system/resource` gives a 401 with a RouterOS realm;
- `/JNAP/` with `X-JNAP-Action: core/GetDeviceInfo`;
- `/appGet.cgi` + ASUS markers; `/soap/server_sa/` (Netgear); `/rci/` (Keenetic); `/api/webserver/SesTokInfo`
  (HiLink); `tr64desc.xml` (TR-064).

Brand only decides the probe **order**. The first driver that answers is used. If none answers, the router stays on
rungs 1–2 and the screen says "Pulse doesn't manage this router natively yet".

## 5. Verification program (how a driver earns "verified")

- **Recorded fixtures:** for each driver and firmware family, real request/response transcripts with addresses, names
  and keys scrubbed, replayed in unit tests. A parser change can't silently break a router we already support.
- **Emulators in CI-style local runs:** OpenWrt and RouterOS CHR VMs, plus OPNsense, running the full
  read + write + read-back suite.
- **Real hardware:** the office AX53 now. Any other router the owner can borrow gets the same suite, and its family
  joins the write matrix only after a full pass.
- **Verified matrix in code:** `driver × firmware family × feature → verified on <model/firmware>`. The UI reads this,
  so nothing unverified can appear.
- **Optional, later:** a "Help Pulse support this router" button that emails the model, firmware and which probes
  answered (never passwords, device lists or addresses), only with the user's consent.

## 6. Safety rules (enforced in the driver layer)

- **Login:** one attempt per user action. Never auto-retry a wrong password, and show "N attempts left" when the router
  reports it. Stop at lockout and show how long to wait.
- **One admin session:** say up front that signing in may sign the router page out elsewhere, and sign out when the
  screen closes.
- **Changes:** confirm anything that disconnects devices. If the phone is on the network being changed, warn that Pulse
  will lose the router until it reconnects. Read back after every write.
- **Never from Pulse:** WAN/PPPoE, firmware, factory reset, admin password, VLANs. These go to the router page.
- **Privacy:** router passwords stay in the OS keystore and go only to the router. The privacy policy (1.3) and Play
  Data safety need a "router login stored on device" line before release.

## 7. UX

- The Router screen is built only from proven capabilities: router health, devices, Wi-Fi, guest network, port
  forwards, DHCP and restart, each appearing when verified.
- Unknown router: "Pulse can show internet status and open your router's page. Native management isn't available
  for this router yet." Plus Full router settings.
- Partial support: sections that work, plus "Other settings: Full router settings".
- Never a dead button: if a write isn't verified, there's no button. Instead there's a link to the router page.

## 8. Roadmap

| Phase | Work | Estimate |
| --- | --- | --- |
| **1. Capability core** | Read/write capability model, per-feature probing, verified matrix, read-back writes, cached results, UI driven by capabilities; port the existing LuCI driver onto it | 3–4 days |
| **2. Tier A drivers** | TR-064, OpenWrt, RouterOS (VM-tested end to end) | ~1 week |
| **3. Office AX53 writes** | With the owner's OK: guest Wi-Fi on/off as the first verified write, then Wi-Fi edit and restart at a quiet time | 1 day |
| **4. Tier B drivers** | ASUSWRT, Netgear, Linksys, Xiaomi, HiLink, Keenetic: **read-only first** (fixtures from community docs), writes when hardware is available | 1–2 days each for reads |
| **5. Polish & release** | Privacy 1.3 and Data safety, render tests per state, docs | 2 days |

## 9. Decisions for the owner

1. Approve the principle that writes stay hidden until verified on real hardware or an official emulator, even when
   the API probably works.
2. OK to run OpenWrt and RouterOS VMs on this PC for testing?
3. Any other routers we can borrow (home, friends, ISP boxes) for Tier B verification?
4. Privacy policy wording for stored router logins (I'll draft it in privacy-project).

## Sources
- Fritz TR-064 interfaces: https://fritz.com/en/pages/interfaces · openHAB TR-064: https://www.openhab.org/addons/bindings/tr064
- OpenWrt ubus / session: https://openwrt.org/docs/techref/ubus · https://openwrt.org/docs/guide-developer/ubus/session ·
  OpenWrt in QEMU: https://openwrt.org/docs/guide-user/virtualization/qemu
- MikroTik REST API: https://help.mikrotik.com/docs/display/ROS/REST+API · CHR licensing:
  https://manual.mikrotik.com/docs/getting-started/routeros-licensing/chr/chr-licensing/
- UniFi official API keys: https://help.ui.com/hc/en-us/articles/31228198640023 · Omada Open API:
  https://support.omadanetworks.com/en/document/109315/
- ASUSWRT client: https://pypi.org/project/asusrouter/ · Netgear SOAP: https://pypi.org/project/pynetgear/ ·
  Linksys JNAP: https://github.com/reujab/linksys · Xiaomi MiWiFi: https://pypi.org/project/python-xiaomi-miwifi/ ·
  Huawei HiLink: https://pypi.org/project/huawei-lte-api/ · Keenetic RCI (community):
  https://forum.keenetic.com/topic/19227-api-%D0%B7%D0%B0%D0%BF%D1%80%D0%BE%D1%81%D1%8B-%D1%87%D0%B5%D1%80%D0%B5%D0%B7-curl
- D-Link HNAP security history: https://nvd.nist.gov/vuln/detail/CVE-2019-7388
