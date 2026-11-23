# App Store listing (iOS / iPadOS)

App Store Connect › Apps › **Pulse: Ping & Network Tools** (Apple ID `6837617016`, SKU `com.pranta.pulse`,
bundle `com.pranta.pulse`, widget extension `com.pranta.pulse.PulseWidgets`, team 9M6X7M798T). Created Nov 21, 2026.
The Play listing is `PLAY_STORE_LISTING.md`; this one differs where iOS behaves differently (see "iOS differences").

## Identity and links

| Field | Value |
| --- | --- |
| Name (30) | Pulse: Ping & Network Tools |
| Subtitle (30) | Speed test, LAN scan & router |
| Primary language | English (U.S.) |
| Marketing URL | https://pulse.pranta.dev/ |
| Support URL | https://pulse.pranta.dev/support |
| Privacy Policy URL | https://legal.pranta.dev/pulse/privacy |
| Terms (EULA, in the description footer) | https://legal.pranta.dev/pulse/terms |
| Category | Primary: Utilities · Secondary: Developer Tools |
| Copyright | 2026 Pranta Dutta |
| Price | Free, no in-app purchases · all countries and regions |

## Promotional text (170 max)

Your router, in your hand: see every device with live speeds, switch Wi-Fi and the guest network, and share Wi-Fi
with a QR code. Plus nine network tools in one calm app.

## Keywords (100 max, comma separated, no spaces after commas)

traceroute,speed test,wifi,lan scanner,network,router,port scan,latency,ip,dns,monitor,packet loss

## Description (4000 max)

Pulse puts nine network tools and your router in one calm, good-looking app. Find out why the internet is slow,
what is on your Wi-Fi, which hop is losing packets, and fix things at the router without hunting for its admin
page.

YOUR ROUTER, IN YOUR HAND
• Sign in to your router once and manage it from Pulse.
• Every device on your network with its live download and upload speed, signal strength, time online and data used.
• Switch your Wi-Fi, guest network and smart-home network on or off, change their names and passwords, and share them with a QR code.
• See your internet connection and change its type (Dynamic IP, Static IP, PPPoE, L2TP or PPTP) with the settings your provider gave you.
• Restart the router and watch it come back.
• Port forwards opened by apps and games, add your own over UPnP.
• "Full router settings" opens the router's own page inside Pulse with your login filled in, for everything else.
• Pulse only shows what works on your router. Changes not yet confirmed for your model are marked "Try it": Pulse checks the router afterwards and asks whether it worked, and your answer helps everyone with the same router.
• Sign-in and control work today on TP-Link Archer routers with the newer web interface (tested on the Archer AX53). On most other routers Pulse shows the internet status, live traffic and port forwards over UPnP, and opens the router's own page. More router families are on the way.

NINE TOOLS
• Ping: live latency, loss and jitter for up to 32 hosts at once, with names like "Office PC".
• Traceroute: every hop with times, countries and the slowest jump called out.
• Port scan: common ports, 1–1024 or your own range, with service names.
• Speed test: download, upload, ping and jitter.
• Packet loss: every packet charted, bursts detected, a plain verdict.
• LAN scan: devices on your network with names, device types and open ports; Wake-on-LAN.
• Geo IP: hosts on a built-in world map with distance and hops.
• Monitor and alerts: checks with uptime and incidents; alerts for outages, high latency and packet loss.
• Router: everything above.

MADE FOR IPHONE AND IPAD
iPhone gets a compact layout; iPad gets a navigation rail, a tools pane and a ping board with every host side by side. Home Screen and Lock Screen widgets for ping, multi-host ping, speed test, monitor, network and quick actions.

PRIVATE BY DESIGN
No account, no ads, no analytics, no tracking. Your history stays on your device. Your router password is saved only if you choose "Remember on this device", in the Keychain, and is sent only to your router. Public IP and location lookups use Pulse's own server, which keeps nothing. Router results ("did it work?") are anonymous and can be turned off.

Free and open source (Apache 2.0). IP geolocation by DB-IP.

Only test networks and devices you own or are allowed to test.

Terms of use: https://legal.pranta.dev/pulse/terms

## iOS differences (keep the description honest)

- No "new device on your network" alerts: the LAN watch doesn't run on iOS (`monitor_provider.dart`).
- No vendor names in LAN scan: iOS gives apps no ARP table / MAC addresses ("MAC address · Hidden by iOS").
- The Wi-Fi name needs location permission plus the Access Wi-Fi Information entitlement (both set up).
- Background monitoring runs only as often as iOS allows (BGTask); the description doesn't promise constant checks.

## What's new (first release)

Pulse is now on iPhone and iPad: nine network tools, your router, and Home Screen widgets.

## App Review notes

- No account or sign-in is needed; every tool works on any network.
- The Router screens need a supported router on the reviewer's network (sign-in and control: TP-Link Archer with
  the newer web interface). On other routers Pulse shows status over UPnP and opens the router's own page.
- Local network permission: Pulse pings and scans devices on the local network (LAN scan, router).
- Location permission is only used so iOS shares the Wi-Fi network name; Pulse doesn't use or store location.

## Screenshots

Raw captures (live data on the office network, status bar overridden to 9:41) for the marketing versions:

- `app-store-screenshots/iphone/` — iPhone 17 Pro Max (iOS 26.5), 1320×2868 (6.9"), 11 shots: ping, traceroute,
  speed (live + result), LAN scan, router, router devices, port scan, Geo IP, monitor, tools.
- `app-store-screenshots/ipad/` — iPad Air 13-inch M4 (iOS 26.5), 2048×2732 (13"), 10 shots: ping board (6 hosts),
  traceroute, speed (live + result), router, router devices, LAN scan, port scan, Geo IP, tools. Retaken Nov 21, 2026
  after the large-iPad layout fix (`PulseTabletScale`: 13" iPads lay out like the 800 dp design tablet, scaled up).

Marketing (captioned, the ones uploaded to App Store Connect on Nov 21, 2026):

- `app-store-screenshots/marketing/iphone-6.3/` — 10 × 1206×2622, in the "iPhone with Dynamic Island (medium
  display)" 6.1"/6.3" slot; App Store Connect scales them for the other iPhone sizes.
- `app-store-screenshots/marketing/ipad-13/` — 9 × 2064×2752, in the iPad 13" slot (used for all iPad sizes).

Avoided: own public IP / location (Geo IP shows github.com), the router's WAN IP is masked by the app.

## App Privacy (nutrition label)

Matches privacy policy 1.3 (Nov 18, 2026; https://legal.pranta.dev/pulse/privacy). Data used to track you: none.
Data linked to you: none. **Data not linked to you** (both optional, Settings › Privacy › "Share router results";
purpose App Functionality only):

- Diagnostics › Other Diagnostic Data: router results (connection type, router model, hardware and firmware version,
  which change, whether it worked).
- Identifiers › Device ID: the random per-install ID sent with router results (stored only as a salted hash).

Not collected: public IP / geo lookups (the server answers and forgets them), history (on device only), router
login (Keychain, sent only to the router), location (only lets iOS reveal the Wi-Fi name; never read or sent).

## Export compliance

`ITSAppUsesNonExemptEncryption = false` in `ios/Runner/Info.plist`: Pulse only uses standard HTTPS/TLS from the OS.

## Age rating

Every content question: None / No. Unrestricted web access: No (the only web view shows the user's own router
admin page). No user-generated content, messaging, ads, gambling, or contests.

## App Review: 2.1 rejection and resubmission (Nov 22–23, 2026)

- **1.2.1 (6) rejected** Nov 22, 2026 under **Guideline 2.1 – Information Needed** (not a bug). Apple asked for, in the
  review Notes: (1) a screen recording starting at app launch showing the main flow, (2) purpose and audience, (3) how
  to use it, (4) external services, (5) regional differences, (6) regulated-industry documents.
- **Response:** the version was renamed **1.2.2** (no "What's New" field on a first release); the Notes answer all six
  points; the recording (`app-review/Pulse-App-Review.mp4`, 4 min, 720p; it shows the office LAN's device names) was made on the iOS 27.0 simulator and the Notes say so. It
  leaves out Geo IP and the Network tab because they show the public IP. Build 7 (1.2.2) attached; resubmitted
  Nov 23, 2026 22:30 ("Waiting for Review"), video attached by the owner, auto-release.
- Reusable flow script and how it was recorded: `xcrun simctl io <udid> recordVideo --codec=h264`, idb taps, the
  ping-board add step retried until the chip row changes (it is flaky right after a fresh install).

## App Store Connect state (Nov 21, 2026)

- **Submitted:** 1.2.1 (build 6) sent to App Review Nov 21, 2026 ~16:45 ("Waiting for Review"), auto-release.

- App Information, Pricing (free, 175 regions), age rating (4+), version 1.2.1 listing text and URLs: saved.
- App Review contact: the owner (name, phone, email entered in App Store Connect). Sign-in required: off. Release:
  automatically after approval.
- App Privacy: answers saved (verified against the code: `verification.dart` report payload, gated by
  `settings.routerReports`; server stores `install` as a salted SHA-256, no IP). Published by the owner
  (Nov 21, 2026).
- App Compliance, China mainland: Security Assessment = No (no E2E messaging or AIGC), AI Generated or Synthetic
  Content = No; both Active. ICP Filing Number is optional ("if you have one"); not needed until Apple asks.
  Digital Services Act: the account is already declared a trader.
