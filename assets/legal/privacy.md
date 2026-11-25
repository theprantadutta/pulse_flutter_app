# Privacy Policy for Pulse

**Policy Version: 1.4**  
**Effective Date: November 25, 2026**  
**Last Updated: November 25, 2026**

Pulse ("the app") is a network diagnostics and monitoring app for Windows, macOS, Linux, Android and iOS, made by Pranta Dutta (prantadutta1997@gmail.com, https://pranta.dev), an independent developer. This policy says what the app stores, what it sends over the network and why, and how to delete it.

## The short version

Pulse has no accounts, no crash reporting, no ads and no tracking. Everything it records stays on your device. It uses no third-party IP or location service: public IP and location lookups go only to Pulse's own server, which keeps nothing. Your router password, if you choose to save it, stays in your device's secure storage and is sent only to your router. The only things Pulse's server keeps are anonymous router results (which router model, which change, whether it worked) and anonymous daily usage counts (for example "12 traceroutes were run on Android yesterday"), which can't be traced to you or your device, and you can turn both off. Beyond that Pulse only contacts the services listed below, and only to do the job you asked for.

## What stays on your device

Pulse keeps these on your device only, in its local database and settings:

- **History:** the results of the pings, traceroutes, port scans, speed tests, packet-loss tests, LAN scans and Geo IP lookups you run, with the hosts you tested and any names you gave them.
- **Saved and monitored targets:** the hosts and names you save (for example "Office PC"), the checks the monitor runs against them, and the incidents it records.
- **Alert rules** and the alerts they have fired.
- **LAN devices** found by LAN scans or by "Watch for new devices": their IP address, MAC address (where your operating system allows it), host name, vendor, and when they were first and last seen. Vendors are looked up in a list built into the app.
- **Router login.** If you sign in to your router in Pulse and tick "Remember on this device", the username and password are kept in your operating system's secure storage (for example the Android Keystore, or the Keychain on iOS and macOS). If you don't tick it, they are kept in memory only and forgotten when Pulse closes. "Forget password" deletes a saved login. Pulse also remembers which routers you signed out of, so it doesn't sign in again until you ask.
- **Router results you gave**, so Pulse doesn't ask you twice, and the router model's results it last received from Pulse's server.
- **Your settings.**

None of this is uploaded anywhere, except the anonymous router results and usage counts described below. Exports (CSV, JSON or text) and copied results go only where you save or paste them.

## What is sent over the network, and to whom

- **The hosts you test.** Pings, traceroutes, port scans, packet-loss tests, LAN scans, Wake-on-LAN packets and monitor checks go directly from your device to the hosts and devices you choose. Traceroute and LAN scans also ask your normal DNS resolver for the names of the addresses they find.
- **Public IP and location lookups (Pulse's own server).** To show your public IP, ISP, network (ASN) and approximate location on the Network screen, to look up hosts on the Geo IP screen, and to show the countries along a traceroute, Pulse sends the relevant IP addresses to **Pulse's own server at pulse.pranta.dev** over HTTPS. The server sees your IP address because you connect to it, answers each request from a location database stored on the server, and then forgets it: it does not log, store or share the addresses you send or your own IP. No third-party IP or location service is involved. The location data is IP geolocation by **DB-IP** (https://db-ip.com), licensed under CC BY 4.0. You can turn these lookups off in Settings, Privacy, "Public IP lookups".
- **Your router.** When you open Router, Pulse talks directly to the router on your local network: over UPnP to read the internet status, traffic and port forwards, and, after you sign in, over the router's own admin interface to read its devices, Wi-Fi networks and settings and to make the changes you ask for. Your router password goes only to your router. "Full router settings" shows the router's own web page inside Pulse.
- **Router results (Pulse's own server).** Pulse only offers router changes it knows work. When you make a change that is not yet confirmed for your router model, Pulse reads the setting back and asks "Did it work?"; if you answer, or if the router refuses the change or doesn't keep it, Pulse sends **Pulse's own server at pulse.pranta.dev** a short report: the type of router connection Pulse used, the router's model, hardware version and firmware version, which change it was (for example "guest network on/off"), whether it worked, and a random ID created for this installation of Pulse. The server stores that ID only as a salted hash, so it can count how many installations confirmed a change without knowing which device sent it; it stores no IP address, network name, device list, password or anything else about you or your network. To show which changes work on your router, Pulse also sends the server your router's model and firmware version. You can turn reports off in Settings, Privacy, "Share router results"; Pulse then neither asks nor sends.
- **Anonymous usage counts (Pulse's own server).** So we can see whether Pulse is useful and which tools to improve, Pulse keeps a tally per day on your device of how many times each feature was used (for example 2 traceroutes and 1 speed test) and whether Pulse was opened that day. Once a day, finished days are sent to **Pulse's own server at pulse.pranta.dev**, which only adds them to daily totals. Each tally contains the day, the feature names and counts, the platform (for example Android), the app version and, for the "opened that day" count, roughly how long ago Pulse was installed (today, 1 to 6 days, 7 to 29 days, or 30 days or more), worked out on your device. It contains no ID of any kind (no installation, device or advertising ID), no hosts, addresses, device names, router details or results, and no location; the server does not log or store your IP address, so the totals can't be linked to you, to your device, or to each other. Usage counts are not used for advertising and are never shared or sold. You can turn them off in Settings, Privacy, "Share anonymous usage counts"; Pulse then deletes the tallies it hasn't sent and stops counting.
- **Host names.** Names for the addresses you look up (reverse DNS) come from your device's normal DNS resolver.
- **IPv6.** Pulse reads your public IPv6 address from your own device's network settings. Nothing is sent for it.
- **Speed test.** A speed test downloads test data from and uploads test data to **Cloudflare** (speed.cloudflare.com) or the **Hetzner** speed-test server you pick. Those services see your IP address. A speed test can use a lot of data, which may count against a mobile data plan.
- **Update check.** When you tap "Check for updates", Pulse asks **GitHub** for the latest release.

The Geo IP map is drawn from map data built into the app, so viewing it sends nothing. Cloudflare, Hetzner and GitHub handle requests under their own privacy policies. Pulse sends them nothing beyond what each request needs: no device identifiers, no account, and none of your history.

## The Pulse website

If you use the contact form on pulse.pranta.dev, your message, your email address and anything else you type in it are emailed to the developer so we can reply. They are used only for that, kept only in that email inbox, and never shared or used for marketing. The website has no analytics, cookies or trackers.

## Permissions

- **Location (Wi-Fi name).** Android, iOS, macOS and Windows only reveal the name of the Wi-Fi network you're connected to to apps that have location permission, and Android also needs Location turned on. Pulse asks only to show your Wi-Fi name. It never reads your GPS position or tracks where you are.
- **Nearby Wi-Fi devices and local network.** Used to read Wi-Fi details, to scan and ping devices on your local network, and to talk to your router.
- **Notifications.** Used for the "Pulse · monitoring" status notification and to tell you when an alert rule fires.
- **Background running.** If "Run in background" is on, Pulse keeps checking your targets with a status notification on Android (and may ask to be exempt from battery optimisation so the system doesn't stop it), uses background refresh on iOS, and keeps running in the system tray on desktop. It restarts monitoring after your device reboots. If you turn on "Launch at login", it starts with your computer.

## Keeping and deleting your data

History is deleted automatically after the period you choose in Settings, Data & export, "Keep history" (90 days unless you change it). You can delete it all in Settings, Data & export, "Clear history", delete everything with "Clear all data", or uninstall the app. Because the data never leaves your device, and Pulse's server keeps none of the lookups it answers, there is nothing for us to delete on a server. Router results and usage counts are anonymous and can't be traced to your device, so they can't be singled out for deletion; router results are kept to tell everyone with the same router model which changes work, and usage counts are kept as daily totals. To have a contact-form message deleted, email us.

## Children

The app is not directed at children under 13, and it does not knowingly collect information from anyone.

## Changes

If this policy changes, the new version will appear here with a new version number and date.

## Contact

Pranta Dutta, prantadutta1997@gmail.com, https://pranta.dev
