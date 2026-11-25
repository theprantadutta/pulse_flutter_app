# Play Store listing (with router control)

For the release that ships the Router feature (branch `feature/router-control`). Paste into Play Console ›
Grow users › Store presence › Main store listing when that release goes out, not before: the listing must not
promise a feature the live app doesn't have. The Microsoft Store description (`msix_config.description` in
`pubspec.yaml`) follows the short description.

## App name (30 max)

Pulse: Network Tools

## Short description (80 max)

Ping, traceroute, speed test, LAN scan, monitoring and control of your router.

## Full description (4000 max)

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
• LAN scan: devices on your network with names, vendors and open ports; Wake-on-LAN.
• Geo IP: hosts on a built-in world map with distance and hops.
• Monitor and alerts: background checks with uptime and incidents; alerts for outages, high latency, packet loss and new devices on your network.
• Router: everything above.

MADE FOR EVERY SCREEN
Phones get a compact layout; tablets get a navigation rail, a tools pane and a ping board with every host side by side. Home screen widgets for ping, speed test, monitor and network.

PRIVATE BY DESIGN
No account, no ads, no tracking. Your history stays on your device, and usage counts are anonymous daily totals with no ID or location (you can turn them off). Your router password is saved only if you choose "Remember on this device", in the system's secure storage, and is sent only to your router. Public IP and location lookups use Pulse's own server, which keeps nothing. Router results ("did it work?") are anonymous and can be turned off.

Free and open source (Apache 2.0).

Only test networks and devices you own or are allowed to test.

## What's new (500 max)

Your router, in Pulse: see every device with live speeds, switch Wi-Fi and the guest network, change Wi-Fi names and passwords, share Wi-Fi with a QR code, change the internet connection type and restart the router. Pulse marks changes it hasn't confirmed for your model as "Try it" and checks afterwards. Plus a new Router card in Tools and many layout fixes on phones and tablets.

## Screenshots

- Phone (`play-store-screenshots/`, 8): Ping, Tools, Router, Devices, Speed test, Traceroute, LAN scan, Monitor.
- 7-inch (`play-store-tab-screenshots/7inch-screenshots/`, 8): Ping, Tools, Router, Network, Port scan, LAN scan, Alerts, Adaptive.
- 10-inch (`play-store-tab-screenshots/10inch-screenshots/`, 8): Ping, Tools, Router, Speed test, Traceroute, Geo IP, Monitor, History.

Regenerate the router shots with `flutter test test/render/store_screens_test.dart` then `python tools/store_shots.py`
(run the script on the committed originals: it renames and replaces files).

## Data safety form changes

Add, under **Data collected**:

- **App activity › Other actions** (or "App info and performance › Other"): router feature results, i.e. router
  driver, model, hardware and firmware version, which change was made and whether it worked, with a random ID made
  for this installation (stored hashed). Purpose: App functionality. Not linked to the user, not shared, optional
  (Settings › Privacy › "Share router results"), encrypted in transit.

- **App activity › App interactions** (1.2.4, privacy policy 1.4): anonymous daily usage counts, i.e. how many
  times each feature was used per day, whether the app was opened that day with a coarse install-age bucket, the
  platform and app version. No identifier of any kind. Purpose: Analytics. Not linked to the user, not shared, not
  used for tracking or ads, optional (Settings › Privacy › "Share anonymous usage counts", on by default),
  encrypted in transit.

Unchanged: no personal info, no location, no device identifiers. The router password is not collected: it is
stored on the device only (if the user opts in) and sent only to the user's own router, which is not a transfer
to the developer or a third party.

## Privacy policy and terms

Version 1.3 (router control, router results, saved router logins) is prepared on the `pulse-router-control`
branch of the privacy-project repository. Merge it to master (which deploys it) when this release goes out.
