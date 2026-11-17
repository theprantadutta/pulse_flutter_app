# iOS home screen widgets — setup on a Mac

**Status (Nov 2026):** all Swift code is written, but none of it has been built yet: it was written on Windows,
where Xcode isn't available. A Mac session must add the widget extension target to the Xcode project, turn
on the capabilities below, build, and fix any compile errors. Android is done and tested (Jetpack Glance,
`android/app/src/main/kotlin/com/example/pulse/widgets/`).

## What exists

| Path | What |
| --- | --- |
| `ios/PulseWidgets/PulseWidgetsBundle.swift` | `@main` bundle: 6 widgets, plus 2 Control Center controls on iOS 18 |
| `ios/PulseWidgets/PingWidgets.swift` | Ping (one host) and Multi-host ping |
| `ios/PulseWidgets/StatusWidgets.swift` | Speed test and Monitor |
| `ios/PulseWidgets/ToolWidgets.swift` | Quick actions and Network |
| `ios/PulseWidgets/Intents.swift` | Per-widget settings (`WidgetConfigurationIntent`s), host picker entity, `RefreshPingIntent` (the ↻ button) |
| `ios/PulseWidgets/Shared/PulseShared.swift` | App Group store: same keys and JSON as Dart `PulseWidgets` and Kotlin `WidgetStore` |
| `ios/PulseWidgets/Shared/PulsePinger.swift` | Unprivileged ICMP over `SOCK_DGRAM` (the way SimplePing does it), run inside the extension |
| `ios/PulseWidgets/Shared/NetworkNow.swift` | `NWPathMonitor` + `getifaddrs` + `NEHotspotNetwork` |
| `ios/PulseWidgets/Shared/PulseTheme.swift`, `Components.swift` | Pulse palette (accent from Settings) and shared views |
| `ios/PulseWidgets/Info.plist`, `PulseWidgets.entitlements` | Extension plist and entitlements |
| `ios/Runner/Runner.entitlements` | App Group + Wi-Fi info for the app (new; not yet referenced by the project) |
| `ios/Runner/Info.plist` | Now registers the `pulse://` URL scheme |

Families: Ping, Speed and Monitor use small, medium and large plus Lock Screen circular, rectangular and inline;
Multi-host ping uses small through extra large plus rectangular; Network uses small, medium, large, rectangular and
inline; Quick actions uses small through extra large plus circular. Per-widget settings (host, interval, pings per
refresh, chart, shortcuts, IP visibility, background) are in each widget's **Edit Widget** sheet. The ↻ buttons ping
inside the extension (interactive widgets, iOS 17). Run on the Speed widget opens `pulse://speed?run=1`.

## One-time Xcode setup

1. `cd pulse_flutter_app && flutter pub get && cd ios && pod install`, then open `ios/Runner.xcworkspace`.
2. **File › New › Target › Widget Extension.** Product name `PulseWidgets`; bundle id
   **`com.pranta.pulse.PulseWidgets`**; leave *Include Live Activity* and *Include Configuration App Intent*
   **unchecked**; embed in **Runner**. When Xcode offers to activate the scheme, choose **Cancel** (keep Runner).
3. Xcode creates an `ios/PulseWidgets/` group with template files (`PulseWidgets.swift`,
   `PulseWidgetsBundle.swift`, `AppIntent.swift`, `Assets.xcassets`, `Info.plist`). **Delete the template Swift
   files** (Move to Trash), but keep `Assets.xcassets`. Our files are already on disk at the same path: right-click
   the group › *Add Files to "Runner"…*, select everything in `ios/PulseWidgets/` (including `Shared/`) and tick
   **only the PulseWidgets target**. If Xcode created its own `Info.plist`, point the target's
   *Info.plist File* build setting at `PulseWidgets/Info.plist` and remove the duplicate.
4. **PulseWidgets target › General:** Minimum Deployments **iOS 17.0** (the app itself stays at 15.0; the widgets
   just won't appear below 17). Also check that *Frameworks and Libraries* has WidgetKit and SwiftUI (Xcode adds them).
5. **PulseWidgets target › Build Settings:** `CODE_SIGN_ENTITLEMENTS = PulseWidgets/PulseWidgets.entitlements`,
   `MARKETING_VERSION = $(FLUTTER_BUILD_NAME)` and `CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)` (the Info.plist
   already uses these). The extension's version must match Runner's or App Store Connect rejects the upload.
6. **Runner target › Build Settings:** `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`.
7. **Signing & Capabilities** on *both* Runner and PulseWidgets (same team):
   - **App Groups** → `group.com.pranta.pulse` (register it in the developer portal when Xcode asks). The id must
     match `PulseGroup.id` (Swift) and `PulseWidgets.appGroup` (Dart).
   - **Access Wi-Fi Information** (Wi-Fi name on the Network screen and widget).
8. Make sure the **Embed Foundation Extensions** build phase of Runner runs *before* the "Thin Binary" / "Run Script"
   phases; otherwise Flutter builds fail with "Cycle inside Runner". Drag it above them if needed.
9. Build the PulseWidgets scheme for a simulator, then `flutter run` the app on a device.

## Things to check when it first builds

- `AppIntentConfiguration` + `@Parameter(size:)` on `MultiPingConfig.hosts` need the iOS 17 SDK; the
  `ControlWidget`s in the bundle are behind `if #available(iOS 18.0, *)` and need Xcode 16+.
- `PulsePinger`: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` works on device and simulator. If the reply parsing
  is off, log `buf[0..<n]`: IPv4 replies include the IP header, IPv6 replies don't.
- The **Router** host resolves to `w.gateway`, which the app publishes after it reads the network (Network screen /
  speed test). iOS has no public API for the gateway, so the widget says "Open Pulse once on this network" until then.
- `NEHotspotNetwork.fetchCurrent` returns nil unless Pulse has location permission *and* the entitlement is present;
  the widget then shows "Wi-Fi".
- `home_widget` forwards URLs that include the `homeWidget` query item (`PulseLink` adds it) to Dart, where
  `WidgetLink.parse` (lib/services/widgets/home_widgets.dart) and `WidgetLinks` (navigation) route them.
- Dart calls `HomeWidget.updateWidget(iOSName: <kind>)` with the kinds in `WidgetKinds` (`PulsePingWidget`, …); keep
  the names in sync if you rename anything.
- Optional: to list placed widgets with their settings in Settings › Home screen widgets, call
  `HomeWidgetPlugin.setConfigurationLookup(to: [...])` in `AppDelegate` with each kind's intent type (and add
  `Intents.swift` to the Runner target as well). It already lists them without that, minus the settings.

## Testing checklist (device, iOS 17+)

- Add each widget in every size (Home Screen and Lock Screen); check light, dark, and tinted/clear (iOS 18).
- Ping widgets: ↻ pings without opening Pulse; Edit Widget › Host offers Router, Cloudflare, Google, Quad9, Pulse's
  saved targets, and anything typed into the search box.
- Speed test: run a test in Pulse; the widget updates. Run on the widget opens Pulse and starts a test.
- Monitor: add targets and turn on Run in background; the widget shows status, uptime and 24 h blocks.
- Network: local and public addresses are partly hidden until switched on in Edit Widget.
- Controls (iOS 18): add "Run a speed test" and "Pulse tool" in Control Center.
- Then update `CLAUDE.md` ("Home screen widgets") and this file with anything that changed.
