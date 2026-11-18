import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../providers/router_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../../services/net/router/router_probe.dart';
import '../../../services/net/router/verification.dart';
import '../../navigation/destinations.dart';
import 'router_actions.dart';
import 'router_format.dart';

/// Router hub: the router on this network at a glance (status, devices,
/// traffic), tiles into full pages for what Pulse can do with it (Devices,
/// Wi-Fi, Guest network, Port forwards) — only the ones this router actually
/// answered — the router's details, Restart, the login, and "Full router
/// settings" (its own admin page inside Pulse) for everything else.
class RouterScreen extends ConsumerWidget {
  const RouterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(routerProfileProvider);
    return PulsePage(
      title: 'Router',
      backTo: Routes.tools,
      actions: [
        PulseIconButton(
          icon: PulseIcons.refresh,
          tooltip: 'Detect again',
          onPressed: () {
            ref.invalidate(routerProfileProvider);
            ref.invalidate(routerManageProvider);
          },
        ),
      ],
      children: switch (profile) {
        AsyncData(value: final p?) => [_Hub(profile: p)],
        AsyncData() => [
          const SizedBox(height: 48),
          const PulseEmptyState(
            title: 'No router here',
            message: 'Connect to Wi-Fi or Ethernet. On mobile data there is no router Pulse can reach.',
            icon: PulseIcons.router,
            shape: PulseShape.cookie9,
          ),
        ],
        AsyncError(:final error) => [
          PulseErrorBanner(
            title: "Couldn't look at your router",
            message: '$error',
            onRetry: () => ref.invalidate(routerProfileProvider),
          ),
        ],
        _ => [const _Detecting()],
      },
    );
  }
}

/// Where the managed session stands.
enum _Session { none, signedOut, needsLogin, loading, error, ready }

class _Hub extends ConsumerWidget {
  const _Hub({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final type = ref.watch(routerDriverTypeProvider);
    final cred = ref.watch(routerCredentialProvider).value;
    final signedOut = ref.watch(routerSignedOutProvider).contains(p.id);
    final native = type.value != null;
    // Watching the manager signs in, so only when there's a login to use.
    final m = native && cred != null && !signedOut ? ref.watch(routerManageProvider) : null;
    final v = m?.value;
    final session = !native
        ? _Session.none
        : cred == null
        ? _Session.needsLogin
        : signedOut
        ? _Session.signedOut
        : switch (m) {
            AsyncData(value: _?) => _Session.ready,
            AsyncError() => _Session.error,
            _ => _Session.loading,
          };

    final hero = _Hero(profile: p, managed: v, native: native);
    final status = <Widget>[
      if (type.isLoading) const _Note(text: 'Checking whether Pulse can sign in to this router…', busy: true),
      if (session == _Session.needsLogin || session == _Session.signedOut)
        _SignInCard(profile: p, savedLogin: session == _Session.signedOut ? cred : null),
      if (session == _Session.loading) const _Note(text: 'Signing in to your router…', busy: true),
      if (session == _Session.error) _SignInError(profile: p, error: m!.error!, cred: cred),
    ];
    final tiles = _Tiles(profile: p, managed: v);
    final internet = [
      if (p.igd != null) ...[const PulseSectionLabel('Internet'), _InternetCard(profile: p)],
    ];
    final details = [
      if (v?.overview != null) ...[const PulseSectionLabel('Router details'), _Overview(o: v!.overview!)],
      if (v != null && v.actions.contains(RouterActions.reboot)) ...[
        const PulseSectionLabel('Router actions'),
        _Actions(profile: p, managed: v),
      ],
      if (p.igd == null) ...[
        const SizedBox(height: 12),
        _Tip(
          icon: PulseIcons.info,
          title: 'Turn on UPnP to see more here',
          message: p.brand.cloudOnly
              ? '${p.brand.label} routers are managed in their own app; Pulse can still open the router page if it '
                    'has one.'
              : 'With UPnP on, Pulse shows the internet connection, live traffic and port forwards straight from '
                    'your router. It is usually under Advanced › NAT forwarding or Network in the router settings.',
        ),
      ],
    ];
    final account = [
      if (native) ...[const PulseSectionLabel('Router login'), _LoginCard(profile: p, signedIn: v != null)],
      const PulseSectionLabel('What Pulse can do here'),
      _Capabilities(profile: p, managed: v, native: native),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              for (final w in status) ...[const SizedBox(height: 12), w],
              const SizedBox(height: 12),
              tiles,
              ...internet,
              ...details,
              ...account,
              const SizedBox(height: 16),
            ],
          );
        }
        // Wide: status and pages on the left, details and login on the right.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  for (final w in status) ...[const SizedBox(height: 12), w],
                  const SizedBox(height: 12),
                  tiles,
                  ...internet,
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...details, ...account, const SizedBox(height: 16)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Detecting extends StatelessWidget {
  const _Detecting();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 64),
    child: Column(
      children: [
        const PulseShapeBadge(shape: PulseShape.cookie9, tone: PulseTone.lime, icon: PulseIcons.router, size: 96),
        const SizedBox(height: 20),
        Text('Looking at your router…', style: context.type.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Model, UPnP, and what Pulse can do with it',
          style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
      ],
    ),
  );
}

/// Name, model, online state, and the numbers that matter most.
class _Hero extends ConsumerWidget {
  const _Hero({required this.profile, required this.managed, required this.native});
  final RouterProfile profile;
  final RouterManaged? managed;

  /// Pulse has its own pages for this router, so the router's page is secondary.
  final bool native;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = profile;
    final o = managed?.overview;
    final live = p.igd != null ? ref.watch(routerLiveProvider).value : null;
    final online = o?.internet ?? live?.status.connected;
    final model = o == null ? null : routerModel(o);
    // Skip the model when the name already says it ("TP-Link Archer AX53 1.0").
    final named = o?.model != null && p.name.toLowerCase().contains(o!.model!.toLowerCase());
    final sub = [if (model != null && !named) model, p.gateway];
    final clients = managed?.clients ?? const <RouterClient>[];
    final hasClientRates = clients.any((d) => d.downBps != null);
    // With UPnP the Internet card below shows live traffic; don't repeat it.
    final sumRates = p.igd == null && hasClientRates;
    final down = sumRates ? clients.fold<double>(0, (a, d) => a + (d.downBps ?? 0)) : null;
    final up = sumRates ? clients.fold<double>(0, (a, d) => a + (d.upBps ?? 0)) : null;
    final uptime = o?.wanUptime ?? live?.status.uptime;
    final stats = [
      if (managed != null && managed!.features.contains(RouterFeature.clients))
        PulseStat('Devices', '${clients.length}'),
      if (down != null) PulseStat('Download', splitRate(down).$1, unit: splitRate(down).$2),
      if (up != null) PulseStat('Upload', splitRate(up).$1, unit: splitRate(up).$2),
      if (uptime != null) PulseStat('Online for', fmtUptime(uptime)),
      if (o?.cpu != null && down == null) PulseStat('CPU', '${(o!.cpu! * 100).round()}', unit: '%'),
      if (o?.memory != null && down == null) PulseStat('Memory', '${(o!.memory! * 100).round()}', unit: '%'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PulsePop(
                child: PulseShapeBadge(
                  shape: PulseShape.cookie9,
                  tone: PulseTone.lime,
                  icon: PulseIcons.router,
                  size: 60,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: context.type.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      sub.join(' · '),
                      style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (online != null) ...[
                      const SizedBox(height: 8),
                      PulsePill(
                        online ? 'Internet connected' : 'Internet down',
                        tone: online ? PulsePillTone.lime : PulsePillTone.error,
                        dot: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                // Four tiles need ~320 dp; below that, two rows of two.
                if (stats.length <= 2 || box.maxWidth >= 340) return PulseStatRow(stats: stats);
                return Column(
                  children: [
                    PulseStatRow(stats: stats.take(2).toList()),
                    const SizedBox(height: 6),
                    PulseStatRow(stats: stats.skip(2).toList()),
                  ],
                );
              },
            ),
          ],
          if (down != null && (o?.cpu != null || o?.memory != null)) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (o!.cpu != null)
                  Expanded(
                    child: _Meter(label: 'CPU', value: o.cpu!),
                  ),
                if (o.cpu != null && o.memory != null) const SizedBox(width: 16),
                if (o.memory != null)
                  Expanded(
                    child: _Meter(label: 'Memory', value: o.memory!),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PulseButton(
                  label: 'Full router settings',
                  icon: PulseIcons.settings,
                  style: native ? PulseButtonStyle.tonal : PulseButtonStyle.pink,
                  onPressed: () => context.push(Routes.routerAdmin),
                ),
              ),
              const SizedBox(width: 8),
              PulseIconButton(
                icon: PulseIcons.copy,
                tooltip: 'Copy router address',
                style: PulseIconButtonStyle.tonal,
                visualSize: 48,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: p.adminUrl.toString()));
                  showPulseToast(context, 'Copied ${p.adminUrl}', icon: PulseIcons.copy);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: context.type.labelLarge!.copyWith(color: c.onSurfaceVariant)),
            const Spacer(),
            Text('${(value * 100).round()}%', style: context.type.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 8,
            backgroundColor: c.surfaceContainerHighest,
            color: value > .85 ? c.error : c.tertiary,
          ),
        ),
      ],
    );
  }
}

/// "Archer AX53 v1.0": the hardware version alone when it already names the
/// model, else model + version.
String? routerModel(RouterOverview o) {
  final hw = o.hardwareVersion;
  if (hw == null) return o.model;
  if (o.model == null || hw.toLowerCase().contains(o.model!.toLowerCase())) return hw;
  return '${o.model} ${RegExp(r'^\d').hasMatch(hw) ? 'v$hw' : hw}';
}

/// Tiles into the full pages; only for things this router answered.
class _Tiles extends ConsumerWidget {
  const _Tiles({required this.profile, required this.managed});
  final RouterProfile profile;
  final RouterManaged? managed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = managed;
    final igd = profile.igd;
    final upnpCount = igd == null ? null : ref.watch(portMappingsProvider).value?.length;
    final tiles = <_TileData>[];
    if (v != null && v.features.contains(RouterFeature.clients)) {
      final wired = v.clients.where((d) => d.link == ClientLink.wired).length;
      tiles.add(
        _TileData(
          title: 'Devices',
          value: '${v.clients.length}',
          caption: '${v.clients.length - wired} on Wi-Fi · $wired wired',
          icon: PulseIcons.laptop,
          shape: PulseShape.circle,
          tone: PulseTone.lavender,
          route: Routes.routerDevices,
        ),
      );
    }
    final wan = v?.wan;
    if (wan != null && wan.current != null) {
      tiles.add(
        _TileData(
          title: 'Internet',
          value: wan.current!.label,
          caption: switch (wan.connected) {
            true => 'Connected',
            false => 'Not connected',
            null => '${wan.available.length} types offered',
          },
          icon: PulseIcons.globe,
          shape: PulseShape.sunny,
          tone: PulseTone.lime,
          route: Routes.routerInternet,
        ),
      );
    }
    final main = v?.wifi.where((n) => n.kind == WifiKind.main).toList() ?? const <WifiNetwork>[];
    if (main.isNotEmpty) {
      final on = main.where((n) => n.enabled == true).length;
      tiles.add(
        _TileData(
          title: 'Wi-Fi',
          value: on == 0 ? 'Off' : '$on on',
          caption: main.first.ssid ?? '${main.length} bands',
          icon: PulseIcons.wifi,
          shape: PulseShape.cookie7,
          tone: PulseTone.lime,
          route: Routes.routerWifi,
        ),
      );
    }
    final extra = v?.wifi.where((n) => n.kind != WifiKind.main).toList() ?? const <WifiNetwork>[];
    if (extra.isNotEmpty) {
      final guest = extra.where((n) => n.guest).toList();
      final on = (guest.isEmpty ? extra : guest).any((n) => n.enabled == true);
      tiles.add(
        _TileData(
          title: guest.isEmpty ? 'Smart-home' : 'Guest network',
          value: on ? 'On' : 'Off',
          caption: (guest.isEmpty ? extra : guest).first.ssid ?? 'For visitors',
          icon: PulseIcons.share,
          shape: PulseShape.cookie9,
          tone: PulseTone.pink,
          route: '${Routes.routerWifi}?focus=guest',
        ),
      );
    }
    final rules = v?.forwards.length ?? 0;
    if (igd != null || rules > 0) {
      final n = (upnpCount ?? 0) + rules;
      tiles.add(
        _TileData(
          title: 'Port forwards',
          value: upnpCount == null && igd != null ? '…' : '$n',
          caption: igd != null ? 'UPnP on' : 'Router rules',
          icon: PulseIcons.port,
          shape: PulseShape.clover4,
          tone: PulseTone.lavender,
          route: Routes.routerPorts,
        ),
      );
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 640 ? 4 : 2;
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in tiles) SizedBox(width: w, child: _Tile(t))],
        );
      },
    );
  }
}

class _TileData {
  const _TileData({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    required this.shape,
    required this.tone,
    required this.route,
  });
  final String title, value, caption, route;
  final PulseIcons icon;
  final PulseShape shape;
  final PulseTone tone;
}

class _Tile extends StatelessWidget {
  const _Tile(this.t);
  final _TileData t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${t.title}: ${t.value}, ${t.caption}',
      excludeSemantics: true,
      child: PulseCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        onTap: () => context.push(t.route),
        child: SizedBox(
          height: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PulseShapeBadge(shape: t.shape, tone: t.tone, icon: t.icon, size: 40),
                  const Spacer(),
                  PulseIcon(PulseIcons.chevR, size: 18, color: c.onSurfaceVariant),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(t.value, style: pulseNumber(26).copyWith(color: c.onSurface)),
              ),
              Text(t.title, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                t.caption,
                style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.busy = false});
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) => PulseCard(
    child: Row(
      children: [
        if (busy) const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        if (busy) const SizedBox(width: 14),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _SignInCard extends ConsumerWidget {
  const _SignInCard({required this.profile, this.savedLogin});
  final RouterProfile profile;

  /// Set after signing out with the password still saved: one tap signs in.
  final RouterCredential? savedLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            savedLogin != null ? 'Signed out of the router' : 'Manage your router here',
            style: context.type.titleLarge!.copyWith(color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            savedLogin != null
                ? 'Your password is still saved on this device. Sign in again with one tap.'
                : "Sign in with the router's admin password to see every device, switch and edit Wi-Fi and the "
                      'guest network, check the router itself and restart it, all in Pulse.',
            style: context.type.bodyMedium!.copyWith(color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PulseButton(
                label: 'Sign in to router',
                icon: PulseIcons.shield,
                style: PulseButtonStyle.pink,
                onPressed: savedLogin != null
                    ? () => ref.read(routerSignedOutProvider.notifier).set(profile.id, false)
                    : () => editRouterLogin(context, ref, profile, null),
              ),
              if (savedLogin != null)
                PulseButton(
                  label: 'Other password',
                  icon: PulseIcons.edit,
                  style: PulseButtonStyle.outlined,
                  onPressed: () async {
                    await editRouterLogin(context, ref, profile, savedLogin);
                    ref.read(routerSignedOutProvider.notifier).set(profile.id, false);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Pulse signs in the way the router's own page does, so that page may sign out if it is open in a browser.",
            style: context.type.bodySmall!.copyWith(color: c.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

class _SignInError extends ConsumerWidget {
  const _SignInError({required this.profile, required this.error, required this.cred});
  final RouterProfile profile;
  final Object error;
  final RouterCredential? cred;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = error;
    final kind = e is RouterDriverException ? e.kind : null;
    // Retrying with the same password can't fix a wrong one: ask for it again.
    void askAgain() =>
        editRouterLogin(context, ref, profile, cred == null ? null : RouterCredential(cred!.username, ''));
    final wrong = kind == RouterErrorKind.wrongPassword;
    if (kind == RouterErrorKind.busy) return _SignedInElsewhere(profile: profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseErrorBanner(
          title: switch (kind) {
            RouterErrorKind.wrongPassword => 'Wrong password',
            RouterErrorKind.lockedOut => 'Sign-in locked for now',
            RouterErrorKind.busy => 'Someone else is signed in',
            _ => "Couldn't sign in to the router",
          },
          message: wrong
              ? "The router didn't accept that password. Enter it again; it's usually the one you use on the "
                    "router's own page, not the Wi-Fi password."
              : (e is RouterDriverException ? e.message : '$e'),
          retryLabel: wrong ? 'Enter again' : 'Retry',
          // While locked, every attempt is refused (and may count): no Retry.
          onRetry: kind == RouterErrorKind.lockedOut
              ? null
              : wrong
              ? askAgain
              : () => ref.invalidate(routerManageProvider),
        ),
        if (!wrong) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: PulseButton(
              label: 'Change password',
              icon: PulseIcons.edit,
              style: PulseButtonStyle.tonal,
              size: PulseButtonSize.small,
              onPressed: askAgain,
            ),
          ),
        ],
      ],
    );
  }
}

class _Overview extends StatefulWidget {
  const _Overview({required this.o});
  final RouterOverview o;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  bool _showWan = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    String mask(String ip) {
      final p = ip.split('.');
      return p.length == 4 ? '${p[0]}.••.••.${p[3]}' : '••••';
    }

    final model = routerModel(o);
    return PulseCard(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (model != null) _Row(label: 'Model', value: model),
          if (o.firmware != null) _Row(label: 'Firmware', value: o.firmware!),
          if (o.wanIp != null)
            _Row(
              label: 'Internet IP',
              value: _showWan ? o.wanIp! : mask(o.wanIp!),
              trailing: PulseIconButton(
                icon: _showWan ? PulseIcons.shield : PulseIcons.search,
                tooltip: _showWan ? 'Hide address' : 'Show address',
                visualSize: 32,
                iconSize: 16,
                onPressed: () => setState(() => _showWan = !_showWan),
              ),
            ),
          if (o.wanType != null) _Row(label: 'Connection', value: _wanType(o.wanType!)),
          if (o.lanIp != null) _Row(label: 'Router address', value: o.lanIp!),
          if (o.dhcpServer != null) _Row(label: 'DHCP server', value: o.dhcpServer! ? 'On' : 'Off'),
          if (o.ipv6 != null) _Row(label: 'IPv6', value: o.ipv6!),
        ],
      ),
    );
  }

  static String _wanType(String t) => switch (t.toLowerCase()) {
    'dhcp' || 'dynamic' => 'Dynamic IP',
    'pppoe' => 'PPPoE',
    'static' => 'Static IP',
    'l2tp' => 'L2TP',
    'pptp' => 'PPTP',
    _ => t,
  };
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.profile, required this.managed});
  final RouterProfile profile;
  final RouterManaged managed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final caps = ref.watch(routerCapabilitiesProvider).value;
    final offers = caps?.offers(RouterActions.reboot) ?? true;
    if (!offers) return const SizedBox.shrink();
    return PulseSegmentedList(
      animate: false,
      children: [
        PulseListItem(
          title: 'Restart router',
          subtitle: 'Internet and Wi-Fi drop for a minute or two; Pulse waits until it is back',
          subtitleMaxLines: 2,
          leading: PulseIcon(PulseIcons.power, size: 22, color: c.error),
          trailing: const RouterTrustPill(RouterActions.reboot),
          onTap: () => restartRouter(
            context,
            ref,
            name: managed.overview == null ? profile.name : (routerModel(managed.overview!) ?? profile.name),
            host: profile.gateway,
          ),
        ),
      ],
    );
  }
}

/// The router has another admin session: offer to sign it out, like the
/// router's own page does.
class _SignedInElsewhere extends ConsumerWidget {
  const _SignedInElsewhere({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Signed in on another device', style: context.type.titleLarge!.copyWith(color: c.onSecondaryContainer)),
          const SizedBox(height: 6),
          Text(
            'The router allows one admin at a time, and someone is signed in elsewhere: its page in a browser, '
            'or Pulse on another phone or tablet. Sign in here to sign that device out.',
            style: context.type.bodyMedium!.copyWith(color: c.onSecondaryContainer),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PulseButton(
                label: 'Sign in here',
                icon: PulseIcons.shield,
                style: PulseButtonStyle.pink,
                onPressed: () => ref.read(routerManageProvider.notifier).signInHere(),
              ),
              PulseButton(
                label: 'Try again',
                icon: PulseIcons.refresh,
                style: PulseButtonStyle.outlined,
                onPressed: () => ref.invalidate(routerManageProvider),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Signed out somewhere else already? Tap Try again.',
            style: context.type.bodySmall!.copyWith(color: c.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

/// The login: state, sign in / out, change, forget.
class _LoginCard extends ConsumerWidget {
  const _LoginCard({required this.profile, required this.signedIn});
  final RouterProfile profile;
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cred = ref.watch(routerCredentialProvider).value;
    final saved = ref.watch(routerLoginSavedProvider).value ?? false;
    final signedOut = ref.watch(routerSignedOutProvider).contains(profile.id);
    final title = cred == null
        ? 'Not signed in'
        : signedOut
        ? 'Signed out · password saved'
        : signedIn
        ? 'Signed in'
        : 'Signing in…';
    final sub = cred == null
        ? 'Pulse only saves the password if you tick "Remember on this device".'
        : saved
        ? 'Password saved on this device, sent only to your router.'
        : 'Password kept until you close Pulse, then forgotten.';
    return PulseCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseIcon(
                signedIn ? PulseIcons.check : PulseIcons.shield,
                size: 22,
                color: signedIn ? c.tertiary : c.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.type.titleMedium),
                    Text(sub, style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PulseButton(
                label: cred == null ? 'Sign in' : 'Change password',
                icon: cred == null ? PulseIcons.plus : PulseIcons.edit,
                style: PulseButtonStyle.tonal,
                size: PulseButtonSize.small,
                onPressed: () => editRouterLogin(context, ref, profile, cred),
              ),
              if (cred != null && !signedOut)
                PulseButton(
                  label: 'Sign out',
                  icon: PulseIcons.power,
                  style: PulseButtonStyle.outlined,
                  size: PulseButtonSize.small,
                  onPressed: () {
                    // Ends the session (the manager signs out of the router as
                    // it disposes); a saved password stays for one-tap sign-in.
                    if (saved) {
                      ref.read(routerSignedOutProvider.notifier).set(profile.id, true);
                    } else {
                      ref.read(sessionRouterLoginProvider.notifier).remove(profile.id);
                    }
                    showPulseToast(context, 'Signed out of the router', icon: PulseIcons.check);
                  },
                ),
              if (saved)
                PulseButton(
                  label: 'Forget password',
                  icon: PulseIcons.trash,
                  style: PulseButtonStyle.outlined,
                  size: PulseButtonSize.small,
                  onPressed: () async {
                    await RouterVault.delete(profile.id);
                    ref.read(sessionRouterLoginProvider.notifier).remove(profile.id);
                    ref.read(routerSignedOutProvider.notifier).set(profile.id, false);
                    ref.invalidate(routerCredentialProvider);
                    ref.invalidate(routerLoginSavedProvider);
                    if (context.mounted) {
                      showPulseToast(context, 'Password removed from this device', icon: PulseIcons.trash);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What Pulse can read and change on this router, and how sure it is.
class _Capabilities extends ConsumerWidget {
  const _Capabilities({required this.profile, required this.managed, required this.native});
  final RouterProfile profile;
  final RouterManaged? managed;
  final bool native;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = profile;
    final upnp = p.igd != null;
    final v = managed;
    final caps = ref.watch(routerCapabilitiesProvider).value;
    Widget item(bool ok, String title, String subtitle, {Widget? trailing}) => PulseListItem(
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: 3,
      leading: PulseIcon(ok ? PulseIcons.check : PulseIcons.x, size: 22, color: ok ? c.tertiary : c.onSurfaceVariant),
      trailing: trailing,
    );
    final changes = [
      for (final a in v?.actions ?? const <String>{})
        if (_relevant(a, v!)) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseSegmentedList(
          animate: false,
          children: [
            item(true, 'Every setting, in the router page', 'Full router settings opens its own admin page.'),
            item(upnp, 'Internet status and live traffic', upnp ? 'Read from the router over UPnP.' : 'Needs UPnP on.'),
            item(upnp && p.igd!.canMap, 'Port forwards', upnp ? 'Add and remove over UPnP.' : 'Needs UPnP on.'),
            if (!native)
              item(
                false,
                'Devices, Wi-Fi and restart in Pulse',
                "Pulse can't sign in to this router model yet. Full router settings has everything.",
              )
            else if (v == null)
              item(true, 'Devices, Wi-Fi and restart in Pulse', 'Pulse can sign in to this router. Sign in above.')
            else
              for (final a in changes)
                PulseListItem(
                  title: RouterActions.label(a),
                  minHeight: 52,
                  leading: PulseIcon(
                    caps?.trust(a) == ActionTrust.failing ? PulseIcons.x : PulseIcons.check,
                    size: 22,
                    color: caps?.trust(a) == ActionTrust.failing ? c.onSurfaceVariant : c.tertiary,
                  ),
                  // Each row opens where the change is made.
                  onTap: caps?.trust(a) == ActionTrust.failing ? null : () => _open(context, ref, a, v),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      switch (caps?.trust(a)) {
                        ActionTrust.verified => const PulsePill('Verified', tone: PulsePillTone.lime),
                        ActionTrust.failing => const PulsePill('Hidden', tone: PulsePillTone.error),
                        _ => const PulsePill('Try it', tone: PulsePillTone.outline),
                      },
                      if (caps?.trust(a) != ActionTrust.failing) ...[
                        const SizedBox(width: 4),
                        PulseIcon(PulseIcons.chevR, size: 18, color: c.onSurfaceVariant),
                      ],
                    ],
                  ),
                ),
          ],
        ),
        if (v != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              caps == null
                  ? 'This router did not report its model and firmware, so every change is "Try it".'
                  : 'Verified: confirmed on this model and firmware. Try it: not confirmed yet; Pulse reads the '
                        'setting back and asks whether it worked. Hidden: reported not to work here.',
              style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  void _open(BuildContext context, WidgetRef ref, String action, RouterManaged v) {
    switch (action) {
      case RouterActions.reboot:
        restartRouter(
          context,
          ref,
          name: v.overview == null ? profile.name : (routerModel(v.overview!) ?? profile.name),
          host: profile.gateway,
        );
      case RouterActions.internetType || RouterActions.internetEdit:
        context.push(Routes.routerInternet);
      case RouterActions.guestToggle || RouterActions.guestEdit || RouterActions.iotToggle || RouterActions.iotEdit:
        context.push('${Routes.routerWifi}?focus=guest');
      default:
        context.push(Routes.routerWifi);
    }
  }

  /// Only list changes for networks this router has.
  static bool _relevant(String a, RouterManaged v) => switch (a) {
    RouterActions.guestToggle || RouterActions.guestEdit => v.wifi.any((n) => n.kind == WifiKind.guest),
    RouterActions.iotToggle || RouterActions.iotEdit => v.wifi.any((n) => n.kind == WifiKind.iot),
    RouterActions.wifiToggle || RouterActions.wifiEdit => v.wifi.any((n) => n.kind == WifiKind.main),
    RouterActions.internetType || RouterActions.internetEdit => v.wan != null,
    _ => true,
  };
}

class _InternetCard extends ConsumerStatefulWidget {
  const _InternetCard({required this.profile});
  final RouterProfile profile;

  @override
  ConsumerState<_InternetCard> createState() => _InternetCardState();
}

class _InternetCardState extends ConsumerState<_InternetCard> {
  bool _showIp = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = ref.watch(routerLiveProvider);
    final r = live.value;
    final s = r?.status;
    if (r == null) {
      return const PulseCard(
        child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
      );
    }
    final connected = s!.connected;
    final hasCounters = s.bytesReceived != null || s.bytesSent != null;
    final ip = s.externalIp;
    return PulseCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulsePill(
                s.connectionStatus ?? 'Unknown',
                tone: s.connectionStatus == null
                    ? PulsePillTone.neutral
                    : connected
                    ? PulsePillTone.lime
                    : PulsePillTone.error,
                dot: true,
              ),
              const Spacer(),
              if (s.uptime != null)
                Text('Up ${fmtUptime(s.uptime!)}', style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant)),
            ],
          ),
          if (hasCounters) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Rate(label: 'Download', icon: PulseIcons.down, bps: r.downBps),
                ),
                Expanded(
                  child: _Rate(label: 'Upload', icon: PulseIcons.up, bps: r.upBps),
                ),
              ],
            ),
            // Fixed layout: always 40 equal slots (empty ones on the left until
            // readings arrive) and a scale that steps 1-2-5-10… instead of
            // following every peak, so nothing grows or shrinks between polls.
            const SizedBox(height: 12),
            PulseBars(
              values: [
                // Slots without a reading yet sit on the baseline, not as dots.
                for (var i = r.history.length; i < _slots; i++) 0.0,
                for (final h in r.history.skip(r.history.length > _slots ? r.history.length - _slots : 0)) h.$1,
              ],
              max: _niceCeiling(r.history.map((h) => h.$1)),
              height: 48,
              fill: true,
              semanticLabel: 'Download over the last two minutes',
            ),
            const SizedBox(height: 4),
            Text(
              'Everything on your network, measured by the router',
              style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          if (ip != null)
            _Row(
              label: 'Public IP',
              value: _showIp ? ip : _mask(ip),
              trailing: PulseIconButton(
                icon: _showIp ? PulseIcons.shield : PulseIcons.search,
                tooltip: _showIp ? 'Hide address' : 'Show address',
                visualSize: 32,
                iconSize: 16,
                onPressed: () => setState(() => _showIp = !_showIp),
              ),
            ),
          if (s.accessType != null) _Row(label: 'Connection', value: s.accessType!),
          if (_realRate(s.maxDownBps, s.maxUpBps))
            _Row(
              label: 'Link rate',
              value: '${fmtRate(s.maxDownBps!.toDouble())} ↓ · ${fmtRate(s.maxUpBps?.toDouble())} ↑',
            ),
        ],
      ),
    );
  }

  /// Many routers report miniupnpd's placeholder rates (exact powers of two,
  /// e.g. 8 388 608 / 4 194 304) instead of the real line speed; hide those.
  static bool _realRate(int? down, int? up) {
    bool pow2(int v) => v > 0 && (v & (v - 1)) == 0;
    if (down == null || down <= 0) return false;
    return !(pow2(down) && (up == null || pow2(up)));
  }

  static const _slots = 40;

  /// The smallest 1-2-5 × 10ⁿ bit rate above every reading (min 100 kbps), so the
  /// chart's scale only changes when traffic crosses a step.
  static double _niceCeiling(Iterable<double> values) {
    final peak = values.fold(0.0, (a, b) => b > a ? b : a);
    var step = 1e5;
    while (true) {
      for (final m in const [1, 2, 5]) {
        if (peak <= step * m) return step * m;
      }
      step *= 10;
    }
  }

  static String _mask(String ip) {
    final p = ip.split('.');
    return p.length == 4 ? '${p[0]}.••.••.${p[3]}' : '••••';
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.label, required this.icon, required this.bps});
  final String label;
  final PulseIcons icon;
  final double? bps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = fmtRate(bps);
    final i = text.lastIndexOf(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PulseIcon(icon, size: 16, color: c.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: context.type.labelLarge!.copyWith(color: c.onSurfaceVariant)),
          ],
        ),
        PulseNumber(
          i < 0 ? text : text.substring(0, i),
          unit: i < 0 ? null : text.substring(i + 1),
          live: true,
          unitScale: .42,
          style: pulseText(30, 900, wdth: 115, height: 1.1).copyWith(color: c.onSurface),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value, style: context.type.titleSmall, overflow: TextOverflow.ellipsis),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Asks for the router's username and password and saves them in the vault.
Future<void> editRouterLogin(BuildContext context, WidgetRef ref, RouterProfile p, RouterCredential? current) async {
  final user = TextEditingController(text: current?.username ?? '');
  final pass = TextEditingController(text: current?.password ?? '');
  var hide = true;
  // Off unless the person ticks it (or it was already saved).
  var remember = current != null && await RouterVault.read(p.id) != null;
  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final fill = context.colors.surfaceContainerHighest;
        final muted = context.type.bodySmall!.copyWith(color: context.colors.onSurfaceVariant);
        return AlertDialog(
          title: const Text('Router login'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 14),
              PulseTargetField(
                controller: user,
                hint: 'Username',
                icon: PulseIcons.edit,
                keyboardType: TextInputType.text,
                fillColor: fill,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Text('Leave it empty if your router only asks for a password.', style: muted),
              ),
              _PasswordField(controller: pass, hidden: hide, fill: fill, onToggle: () => setState(() => hide = !hide)),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Remember on this device'),
                subtitle: Text(
                  remember
                      ? 'Saved in the system keystore, sent only to your router.'
                      : 'Used until you close Pulse, then forgotten.',
                  style: muted,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (saved == true && pass.text.isNotEmpty) {
    final login = RouterCredential(user.text.trim(), pass.text);
    if (remember) {
      await RouterVault.write(p.id, login);
      ref.read(sessionRouterLoginProvider.notifier).remove(p.id);
    } else {
      await RouterVault.delete(p.id);
      ref.read(sessionRouterLoginProvider.notifier).put(p.id, login);
    }
    ref.invalidate(routerCredentialProvider);
    // Sign in again even when the same password was entered (it may have
    // failed for another reason the first time).
    ref.invalidate(routerManageProvider);
    if (context.mounted) {
      showPulseToast(
        context,
        remember ? 'Router login saved on this device' : 'Signed in for this session only',
        icon: PulseIcons.check,
      );
    }
  }
  user.dispose();
  pass.dispose();
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller, required this.hidden, required this.fill, required this.onToggle});
  final TextEditingController controller;
  final bool hidden;
  final Color fill;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          PulseIcon(PulseIcons.shield, size: 20, color: c.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: hidden,
              autocorrect: false,
              enableSuggestions: false,
              style: context.type.titleMedium!.copyWith(fontSize: 17),
              decoration: const InputDecoration(
                hintText: 'Password',
                border: InputBorder.none,
                isCollapsed: true,
                filled: false,
              ),
            ),
          ),
          PulseIconButton(
            icon: hidden ? PulseIcons.search : PulseIcons.shield,
            tooltip: hidden ? 'Show password' : 'Hide password',
            visualSize: 40,
            iconSize: 18,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.title, required this.message});
  final PulseIcons icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PulseCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PulseIcon(icon, size: 22, color: c.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.type.titleMedium),
                const SizedBox(height: 4),
                Text(message, style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
