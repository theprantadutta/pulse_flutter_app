# Pulse — project notes for Claude

## Layout (Nov 2026)
`G:\Personal\MyProjects\pulse\` is a plain folder holding two repos, like Pourfect and Snake Classic:
- `pulse_flutter_app/` — this app (GitHub `theprantadutta/pulse_flutter_app`, renamed from `pulse`; public).
- `pulse-rust-api/` — the Rust (axum) backend that serves the marketing / support / download site at
  https://pulse.pranta.dev (GitHub `theprantadutta/pulse-rust-api`, private).

## Current design: "Expressive" (branch `redesign/expressive`)
Material 3 Expressive redesign (plum surfaces; pink / lavender / lime; Roboto Flex; M3 Expressive shapes and motion).
It replaced the earlier "Wire" design (branch `redesign/wire`, now merged history only).

- **Spec:** `design_handoff_pulse_expressive/` (README, `DESIGN_SYSTEM.md`, `SCREENS.md`, `tokens/`, `prototype/`
  HTML, icon/shape/logo SVGs). The kit's PNG screenshots and MP4 motion clips (34 MB) are not committed; the user has
  them in `Downloads\Pulse-Expressive-Redesign-Kit\pulse-redesign-kit\{screenshots,animations}`.
- **Design system in code** — import `lib/core/widgets/pulse/pulse.dart` only:
  `lib/core/theme/pulse_theme.dart` (schemes, `PulseTokens` latency/map colours, `PulseAccent` (Pink/Lavender/Lime/Blue
  swaps the fixed hero family), `pulseText`/`pulseNumber`, `context.colors/type/pulse`), `pulse_shapes.dart`
  (`PulseShape`, `PulseShapeBox`, `WavyProgress`, `PulseLogo`), `pulse_motion.dart` (entrances, press morph, live
  values), components in `lib/core/widgets/pulse/` (page scaffold, buttons, button group, chips, target field, hero
  metric, stat row, segmented list, bars, pills, empty/error states), icons = kit SVGs in `assets/icons/`.
  No hard-coded colours in screens; hex values live only in `pulse_theme.dart`.
- **Shell:** `lib/presentations/navigation/pulse_shell.dart`. compact < 600 dp: NavigationBar (Ping · Network · Tools ·
  History); ≥ 600: 96 dp rail (logo, "+" → `/ping?add=1`, 4 destinations, Settings at the bottom); ≥ 840 tool routes
  get the Tools pane. Tool catalogue (badge shape/colour, last result) in `tools_catalog.dart`.
  Navigation rule: tabs/rail/Tools pane use `context.go`; drill-ins (tool tiles, LAN from Network, Alerts, rule
  editor, Settings) use `context.push` so back returns to the opener. System back with nothing to pop goes to
  `parentRoute()` (destinations.dart) instead of closing the app.
- **Splash:** `main.dart` holds the native splash (`FlutterNativeSplash.preserve`); `SplashScreen` is the only place
  that calls `remove()`, after its first frame. The native images in `assets/brand/splash/` are drawn with
  `PulseLogo`'s exact geometry at 168 dp (672 px @4x) on the theme surface, so the hand-off is invisible. Regenerate
  them with the same geometry if the logo changes, then `dart run flutter_native_splash:create`.
  The router must always start on `/launch` (`overridePlatformDefaultLocation: true`): a platform route such as
  the Monitor notification's `/monitor` would otherwise skip SplashScreen, so boot never runs and the deferred
  first frame is never released (blank screen). The requested route becomes SplashScreen's `next` instead.
- **Brand assets:** kit logo PNGs → `assets/brand/icon/*` (launcher icons via `flutter_launcher_icons.yaml`; Windows
  `.ico`, macOS, web and tray icons are written pixel-exact; Android notification icon `ic_stat_pulse`).
- **Geo IP map:** offline Natural Earth vector map `assets/data/world_map.bin` (format in `assets/data/README.md`),
  drawn by `lib/presentations/screens/geo/world_map.dart`. No tile provider.
- **Settings added:** `accent`, `dynamicColor` (dynamic_color, keeps brand roles), `expressiveMotion` (off ⇒
  `disableAnimations` app-wide).
- **Do not** replace the repo's `screenshots/` folder with kit PNGs; real device screenshots will be taken later.

### Public IP and Geo IP: our backend only
- **No third-party IP services** (user's rule): public IP, Geo IP, traceroute countries all go to
  `pulse-rust-api` (`/api/v1/ip`, `/api/v1/geo/lookup`, DB-IP Lite data) via `lib/services/pulse_api.dart`.
  Reverse DNS uses the device resolver; public IPv6 = the device's global unicast address. Credit "IP geolocation
  by DB-IP" wherever that data shows (CC BY 4.0).
- Requests are HMAC-signed with `PULSE_APP_KEY`, compiled in from the git-ignored `secrets.json` (same value as the
  backend `.env`). **Every build that should do lookups needs it:**
  `flutter run --dart-define-from-file=secrets.json`, `flutter build appbundle --release --dart-define-from-file=secrets.json`
  (also for Windows/macOS/iOS). Without it, Geo IP shows "This build has no Pulse API key".
- Release signing: `android/key.properties` (git-ignored) → upload key in `C:/android-keys/pulse/` (same layout
  as Gridwell/Pourfect; credentials file there). Play App Signing holds the app signing key.

### In-app updates and reviews (`lib/services/store/`)
- `app_updates.dart` (`appUpdateProvider`): Google Play in-app updates (`in_app_update`) when installed by Play —
  flexible background download, immediate when priority ≥ 4 or 30 days stale; otherwise (desktop, debug/sideloaded
  Android) the latest GitHub release. `StorePrompts` (around the shell, `navigation/store_prompts.dart`) checks quietly
  at start (≤ every 12 h) and offers Update / Restart. Play's flow only works on builds installed from Play
  (internal testing or later), never on `flutter run` builds.
- `app_reviews.dart`: every saved run (HistoryRepository `onSaved`) is a review moment; the native review sheet
  (`in_app_review`) shows after 5 runs and 3 days, at most every 120 days and 3 times. "Rate Pulse" buttons open the
  store page instead (requestReview from a button may show nothing). iOS uses `PulseShareConfig.appStoreId` = 6837617016.

### Home screen widgets (Nov 2026)
- Six widgets on both platforms: Ping (one host), Multi-host ping (up to 6), Speed test, Monitor, Network, Quick actions.
  Every size from 1×1 up (Android responsive Glance sizes; iOS small→extra large + Lock Screen; iOS 18 controls).
- **Android:** Jetpack Glance in `android/app/src/main/kotlin/com/example/pulse/widgets/` (Compose compiler plugin in
  Gradle; Glance comes with `home_widget`). Ping widgets ping natively (`/system/bin/ping`), no Flutter: ↻ runs
  `RefreshPingAction`, `WidgetRefreshWorker` (WorkManager, ≥ 15 min) refreshes on each widget's interval. Settings per
  widget: `WidgetConfigActivity` (a `MainActivity` subclass) opens Flutter on `/widgets/configure?id=&kind=`, which
  saves `w.cfg.<id>` and calls `HomeWidget.finishHomeWidgetConfigure()`.
- **iOS:** WidgetKit + App Intents in `ios/PulseWidgets/`, built as the `PulseWidgets` extension target (Nov 21, 2026;
  App Group `group.com.pranta.pulse`); see `docs/IOS_WIDGETS.md` for the setup and the on-device checklist.
- **Dart:** `lib/services/widgets/home_widgets.dart` (`PulseWidgets`: keys, JSON shapes, monitor snapshot, per-widget
  settings, `WidgetLink` parsing), `providers/widgets_provider.dart` (publishes theme, saved targets, speed results,
  monitor while the app runs), the background monitor publishes Monitor after each cycle, `NetworkInfoNotifier`
  publishes the public IP + gateway. `navigation/widget_links.dart` opens widget taps (`pulse://ping?host=`,
  `speed?run=1`, `open?to=/route`). Settings › Appearance › Home screen widgets (`/settings/widgets`) lists and pins them.
- Keys/JSON shapes are shared by Dart, `WidgetStore.kt` and `PulseShared.swift`; change all three together.

### Router control (shipped in 1.2.0)
- Plan: `docs/ROUTER_ANY_ROUTER_PLAN.md` (support ladder, verified capabilities, drivers, safety rules). Feasibility:
  `docs/ROUTER_CONTROL_RESEARCH.md`. Code: `lib/services/net/router/` (probe, UPnP IGD, drivers + registry),
  `providers/router_provider.dart`, `router_manage_provider.dart`, `screens/router/`.
- Office router = TP-Link Archer AX53 (192.168.0.1, firmware 1.7.1 / web UI 1.11): the "luci-encrypted-web" driver.
  Over HTTPS its web app sends PLAIN form data (the AES/SG envelope is only for HTTP). Its password is in the
  git-ignored `.env` as `PULSE_ROUTER_PASSWORD`; `test/services/tplink_live_test.dart` reads it. Never print or open
  `.env`, and never change the office Wi-Fi or reboot the router without the owner's explicit OK.
- **Owner's home router (future session):** the owner offered it for testing. If a session runs on a network whose
  router is NOT the TP-Link AX53 (check `RouterProbe` / the gateway's UPnP description), that's the home router: identify
  it, see which driver probes answer (`detectRouterDriver`), record fixtures, run read tests, and ask the owner before
  any write.
- Tools hub: Router is the wide card under the 8 tools (`kRouterTool`). Router pages: hub, Devices, Wi-Fi, Internet
  (connection type), Port forwards. Changes go through `runRouterAction` (Try it / read-back / "Did it work?");
  reports go to pulse-rust-api `/api/v1/router/*` unless Settings › Privacy › "Share router results" is off. Never
  retry a sign-in automatically (routers lock the admin out) and never force-sign-out another session without asking.
- Store screenshots for router screens: `flutter test test/render/store_screens_test.dart` + `python tools/store_shots.py`
  (sample data only). Listing text: `docs/PLAY_STORE_LISTING.md`.
- Router logins are saved only when the user ticks "Remember on this device" (default off); otherwise in memory for
  the session. Feature verification is meant to be crowd-sourced through the backend (owner's decision): ask users
  whether an action worked and store verified/unverified per driver + model + firmware + feature.

### Decisions made with the user
- Persistence: **drift** (`lib/data/db/app_database.dart`, run `dart run build_runner build` after schema edits).
- **No stubs anywhere.** Every screen/provider must be fully real: LAN scan, Monitor, Alerts, Geo IP, Packet loss
  included. Full background work: Android foreground service (`flutter_foreground_task`), iOS WorkManager/BGTask,
  desktop system tray (`tray_manager` + `window_manager`, keep monitoring when window closes), local notifications
  on all platforms (`flutter_local_notifications`), launch-at-login implemented natively (the `launch_at_startup`
  package conflicts with `device_info_plus` 13).
- Always use the latest pub.dev versions (check pub.dev + changelogs).
- Commit after each step; no Claude / AI attribution in commit messages. Style: `feat: :sparkles: ...` (gitmoji).
- The app imports `package:material_ui/material_ui.dart` (decoupled Material), not `flutter/material.dart`.

### Engines and providers
- Engines: `lib/services/net/` (ping prober + Windows ICMP FFI, traceroute, port scanner, speed test, LAN scan with
  ARP/NetBIOS/OUI plus device identification in `lan/`: router DNS PTR (`router_names.dart`), UPnP/SSDP
  (`ssdp.dart`), mDNS/DNS-SD browse (`mdns_browser.dart`), identifying ports (`port_hints.dart`), merged by
  `LanScanner.identify`; every source is optional because routers differ (multicast filtering, no LAN DNS), and
  SSDP/mDNS also ask found hosts by unicast. Users can rename devices and pick their type (lan_devices v3/v4), Wake-on-LAN, geo IP, per-OS network details, gateway), `lib/services/background/`
  (MonitorEngine, notifications, foreground service), `lib/services/desktop/` (window + tray, launch at login).
- Providers: `lib/providers/*` (one per tool; `pingBoardProvider` = multi-ping; `monitorRunnerProvider` decides where
  monitoring runs: tray on desktop, foreground service on Android/iOS when "Run in background" is on, else in-app).
- Layout: see "Shell" above. Phones (shortest side < 600 dp) are locked to portrait in `main.dart`.
  `test/render/device_render_test.dart` renders screens at Galaxy A24 / Galaxy Tab A9 sizes; every screen has its own
  render test (`renderMatrix`: phone 390×844 + tablet 1280×800, light + dark) writing PNGs to `build/renders/`.
- DB schema v4 (v2 saved_targets + sessions.label; v3 lan_devices custom_name, model, identity; v4 picked_type). Bump `schemaVersion` + add an `onUpgrade` step for changes.

### Test checklist for real devices (office PC: Android phone + Windows)
- Android: install `flutter run` → allow notifications; Network screen asks for location (needed for SSID);
  Monitor → add a target → Settings › Monitor › Run in background → a "Pulse · monitoring" notification should stay;
  kill the app, targets keep being checked; alert rules notify. LAN scan on Android cannot read MACs (OS limit).
- Windows: closing the window hides to the tray (tray menu: Show / Pause / Quit); launch at login (Run key for the
  plain build, StartupTask for the MSIX) starts hidden with `--autostart`; the first launch shows the 720×440 launch
  window then grows to the app.
- Local MSIX on this PC: signed with a per-machine self-signed cert `CN=Pranta Dutta` stored in
  `%USERPROFILE%\.pulse-signing\` (pfx + password.txt, user-only ACL; public .cer trusted in LocalMachine\TrustedPeople).
  Rebuild: `dart run msix:create --certificate-path %USERPROFILE%\.pulse-signing\pulse_local.pfx --certificate-password
  <password.txt> --publisher "CN=Pranta Dutta" --install-certificate false`, install with Windows PowerShell 5.1
  `Add-AppxPackage` (the Appx module does not load in PowerShell 7). Never trust msix's bundled test_certificate.pfx —
  its private key is public.
- iOS and macOS build on the owner's Mac (see "iOS / App Store" below). macOS runs un-sandboxed (system tools) —
  see `macos/Runner/*.entitlements`.

## iOS / App Store (Nov 2026)
- **App Store Connect:** "Pulse: Ping & Network Tools", Apple ID 6837617016, SKU `com.pranta.pulse`, team 9M6X7M798T.
  Bundle IDs `com.pranta.pulse` + `com.pranta.pulse.PulseWidgets`, App Group `group.com.pranta.pulse` (App Groups +
  Access Wi-Fi Information on both). 1.2.1 (6) was rejected Nov 22 under Guideline 2.1 (Information Needed: a screen recording plus purpose, usage, external services, regions, regulation answers in the review Notes); the version was renamed 1.2.2 and resubmitted with build 7 (see `docs/APP_STORE_LISTING.md`). Listing text, privacy
  label, compliance answers and screenshot inventory: `docs/APP_STORE_LISTING.md`. Distribution profiles are in the
  owner's `~/Certificates & Documents/Apple Signing/` (`Pulse.mobileprovision`, `Pulse_Widgets.mobileprovision`);
  Xcode automatic signing is what the IPA uses. No App Store Connect API access on the team: the owner uploads.
- **Build:** `flutter build ipa --release --dart-define-from-file=secrets.json` → `build/ios/ipa/Pulse.ipa`. Bump the
  build number (`version:` in pubspec) for every upload. Swift Package Manager only (no CocoaPods); permission_handler's
  SPM manifest enables permissions from the Info.plist usage keys. `ITSAppUsesNonExemptEncryption` = false.
- **UIScene lifecycle** (required by the iOS 27 SDK, else a launch crash): `Info.plist` › `UIApplicationSceneManifest`
  with `FlutterSceneDelegate`; `AppDelegate` registers plugins and the `network_info` channel in
  `didInitializeImplicitFlutterEngine`; the notification delegate and the background-engine registrant stay in
  `didFinishLaunching` (flutter_foreground_task registers its BGTask in `+load`).
- **Large iPads:** `PulseTabletScale` (`lib/core/widgets/pulse/pulse_tablet_scale.dart`, iOS only) lays a 12.9"/13"
  iPad out at an 800 dp short side (the design tablet) and draws it scaled up; 11" iPads, phones, Android and desktop
  are untouched. Render tests cover `kIpad13`, `kIpad13Landscape`, `kIpad11` (`test/render/render_harness.dart`).
- **dart_ping fork (keep it):** iOS ping uses our fork via `dependency_overrides` in `pubspec.yaml`
  (`theprantadutta/dart_ping`, tag `pulse-ios-identifier-v1` = commit 16458ed on branch `fix/ios-reply-identifier`).
  Upstream 10.0.1 matched ICMP replies by sequence only and Darwin delivers every reply to every ICMP socket, so
  concurrent pings stole each other's replies (wrong RTTs, traceroute "reaching" the target at hop 1). Don't drop the
  override, delete the tag or switch back to pub.dev until point-source/dart_ping#106 is merged and released; then
  remove the override, bump `dart_ping`, and re-check the Ping board and a traceroute on an iPhone simulator.
  Local clone: `~/Personal/forks/dart_ping`; its `example/ios` RunnerTests (46) cover the fix.
- **dart_ping#106 status (Nov 23, 2026):** merged Nov 22 with the maintainer's additions (offline
  `PingEngine.matchedProbe` tests, loopback v4/v6 tests, live test opt-in via `DART_PING_LIVE_TESTS`), **not released**
  (pub.dev 10.0.1). The owner has **no physical iPhone**; results from the iOS 27 simulator (Pulse pointed at
  `point-source/dart_ping@2714e20`: 3 concurrent pings + traceroute correct) and native macOS runs (v4 hosts + `::1`)
  were posted on #106 (issuecomment-7106663384), saying plainly it was a simulator. Internet IPv6 is untested (the
  office network has no IPv6 route). Once 10.0.2+ is on pub.dev: remove the `dart_ping` override, bump `dart_ping`,
  re-check the Ping board and a traceroute on an iPhone simulator and on Android.
- **Simulators** (owner's 8 GB Mac): boot one at a time, and coordinate with other Claude sessions that use them.
  Screenshots: `xcrun simctl status_bar <udid> override --time 9:41 …`, idb for taps (points, not pixels). Raw captures
  in `app-store-screenshots/{iphone,ipad}/`, the owner's captioned set in `app-store-screenshots/marketing/`.
- **Widgets:** the extension builds and registers; still to test placing each widget on a real device
  (`docs/IOS_WIDGETS.md` checklist).

## Microsoft Store (Windows MSIX)
- Packaging: `dart run msix:create` (config in `pubspec.yaml` › `msix_config`). Output: `build/windows/x64/runner/Release/pulse.msix`.
  Local builds are signed with the msix tool's test certificate; Store builds use `dart run msix:create --store`
  (unsigned — the Store signs it).
- Launch at login inside the package uses the manifest StartupTask (`startup_task`, id `PulseStartup`) via the runner's
  C++/WinRT channel (`windows/runner/startup_task.cpp`); unpackaged builds keep the HKCU Run key. Windows only lets the
  user re-enable a task they switched off in Task Manager › Startup apps.
- Toast activation: `toast_activator.clsid` must equal the `guid` in `lib/services/background/notifications.dart`.
- Version: `msix_version` must end in `.0` for the Store; keep it in step with `version:` (currently 1.2.2.0 / 1.2.2+7; bump the build number for every Play upload).
- Policies (Store listing): https://legal.pranta.dev/pulse/privacy and https://legal.pranta.dev/pulse/terms, served
  from `G:\Personal\MyProjects\privacy-project\Projects\pulse\` (push to master → auto-deploys). Current versions:
  privacy 1.3, terms 1.3 (Nov 18, 2026: router control, saved router logins, anonymous router results); bump them and the dates whenever data use, services or permissions change.
- STILL NEEDED from the user: a Partner Center account and the reserved app name; then copy Package/Identity/Name →
  `identity_name`, Package/Identity/Publisher (CN=…) → `publisher`, PublisherDisplayName → `publisher_display_name`,
  set `display_name` to the reserved name, and add that name to `displayNames` in privacy-project `Program.cs` if it
  differs from "Pulse". Store listing also needs screenshots, description and age rating (done in Partner Center).

## Flutter 3.50 notes (Nov 2026)
- Android's asset packager unpacks `.gz` assets and drops the extension, so the OUI table ships as
  `assets/data/oui_tsv.gzip`. Don't name assets `*.gz`.
- Never `restartService()` the foreground service: the old engine's teardown unregisters plugins of the new one
  (shared_preferences throws in onStart and no cycle runs). `BackgroundMonitor.start` updates it in place.
- After a Visual Studio update moves MSVC, delete `build/windows` if CMake says the compiler path doesn't exist.
- Other Claude sessions share this PC's Flutter SDK and the two Android devices: message them before using a device
  or touching `C:\Users\pranta\develop\flutter\bin\cache`.

## Verifying
- `flutter analyze` must be clean. `dart format` uses page width 120 (analysis_options.yaml).
- `flutter test` — `test/render/*` (tag `render`) writes PNG renders to `build/renders/` with real fonts;
  `test/services/*_live_test.dart` (tag `network`) hits the real network. Run `flutter test --exclude-tags network`
  for the offline suite. Don't run several `flutter test` processes at once on Windows: they fight over
  `build/native_assets/windows/sqlite3.dll` ("failed to delete").
- Windows build needs the Visual Studio component **"C++ ATL for latest v143 build tools"** (for
  `flutter_local_notifications_windows`).
- The user continues on the office PC with an Android device + Windows PC — run on both there.
