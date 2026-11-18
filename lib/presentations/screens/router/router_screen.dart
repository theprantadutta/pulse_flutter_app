import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/network_provider.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../providers/router_provider.dart';
import '../../../services/net/router/router_probe.dart';
import '../../../services/net/router/upnp_igd.dart';
import '../../navigation/destinations.dart';
import 'router_manage.dart';

/// Router: Pulse's own view of the router on this network — who it is, the
/// internet connection and live traffic it reports, UPnP port forwards, the
/// saved login, and "Full router settings" for everything else (the router's
/// own admin page inside Pulse, with the login filled in).
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
          onPressed: () => ref.invalidate(routerProfileProvider),
        ),
      ],
      children: switch (profile) {
        AsyncData(value: final p?) => _sections(context, ref, p),
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

  List<Widget> _sections(BuildContext context, WidgetRef ref, RouterProfile p) => [
    _Hero(profile: p),
    ...routerManageSections(context, ref, p),
    if (p.igd != null) ...[
      const PulseSectionLabel('Internet'),
      _InternetCard(profile: p),
      const PulseSectionLabel('Port forwards'),
      _PortForwards(profile: p),
    ] else ...[
      const SizedBox(height: 12),
      _Tip(
        icon: PulseIcons.info,
        title: 'Turn on UPnP to see more here',
        message: p.brand.cloudOnly
            ? '${p.brand.label} routers are managed in their own app; Pulse can still open the router page if it has one.'
            : 'With UPnP on, Pulse shows the internet connection, live traffic and port forwards straight from '
                  'your router. It is usually under Advanced › NAT forwarding or Network in the router settings.',
      ),
    ],
    const PulseSectionLabel('Router login'),
    _LoginCard(profile: p),
    const PulseSectionLabel('What Pulse can do with this router'),
    _Capabilities(profile: p),
    const SizedBox(height: 24),
  ];
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
          'Model, UPnP, and where its settings page lives',
          style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final info = p.igd?.info;
    final sub = [p.gateway, if (info?.friendlyName != null && info!.friendlyName != p.name) info.friendlyName!];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
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
                  size: 64,
                ),
              ),
              const SizedBox(width: 16),
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
                  ],
                ),
              ),
            ],
          ),
          if (p.protocols.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final pr in p.protocols) PulsePill(pr.label, tone: PulsePillTone.outline)],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: PulseButton(
                  label: 'Full router settings',
                  icon: PulseIcons.settings,
                  style: PulseButtonStyle.pink,
                  size: PulseButtonSize.large,
                  onPressed: () => context.push(Routes.routerAdmin),
                ),
              ),
              const SizedBox(width: 10),
              PulseIconButton(
                icon: PulseIcons.copy,
                tooltip: 'Copy router address',
                style: PulseIconButtonStyle.tonal,
                visualSize: 56,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: p.adminUrl.toString()));
                  showPulseToast(context, 'Copied ${p.adminUrl}', icon: PulseIcons.copy);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Opens ${p.adminUrl.host}${p.adminUrl.hasPort ? ':${p.adminUrl.port}' : ''} inside Pulse, '
            'with your saved login filled in.',
            style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String fmtRate(double? bps) {
  if (bps == null) return '—';
  if (bps >= 1e9) return '${(bps / 1e9).toStringAsFixed(2)} Gbps';
  if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(bps >= 1e8 ? 0 : 1)} Mbps';
  if (bps >= 1e3) return '${(bps / 1e3).toStringAsFixed(0)} kbps';
  return '${bps.toStringAsFixed(0)} bps';
}

String fmtUptime(Duration d) {
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
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
                for (var i = r.history.length; i < _slots; i++) null,
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
          _Row(
            label: 'Public IP',
            value: ip == null ? 'Not reported' : (_showIp ? ip : _mask(ip)),
            trailing: ip == null
                ? null
                : PulseIconButton(
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

  /// The smallest 1-2-5 × 10ⁿ bit rate above every reading (min 1 Mbps), so the
  /// chart's scale only changes when traffic crosses a step.
  static double _niceCeiling(Iterable<double> values) {
    final peak = values.fold(0.0, (a, b) => b > a ? b : a);
    var step = 1e6;
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

class _PortForwards extends ConsumerWidget {
  const _PortForwards({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(portMappingsProvider);
    final igd = profile.igd!;
    final items = list.value ?? const <PortMapping>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.isLoading && items.isEmpty)
          const PulseCard(
            child: SizedBox(height: 56, child: Center(child: CircularProgressIndicator())),
          )
        else if (items.isEmpty)
          PulseCard(
            child: Text(
              'No port forwards. Apps and game consoles add them here when they need incoming connections, '
              'and you can add your own.',
              style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
            ),
          )
        else
          PulseSegmentedList(
            animate: false,
            children: [
              for (final m in items)
                PulseListItem(
                  title: '${m.protocol} ${m.externalPort} → ${m.internalClient}:${m.internalPort}',
                  subtitle: [
                    m.description.isEmpty ? 'No description' : m.description,
                    if (!m.enabled) 'off',
                    if (m.leaseSeconds > 0) 'expires in ${fmtUptime(Duration(seconds: m.leaseSeconds))}',
                  ].join(' · '),
                  leading: PulseIcon(PulseIcons.port, size: 22, color: c.onSurfaceVariant),
                  trailing: PulseIconButton(
                    icon: PulseIcons.trash,
                    tooltip: 'Remove ${m.protocol} ${m.externalPort}',
                    visualSize: 36,
                    iconSize: 18,
                    onPressed: () => _remove(context, ref, igd, m),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            IntrinsicWidth(
              child: PulseButton(
                label: 'Add port forward',
                icon: PulseIcons.plus,
                style: PulseButtonStyle.tonal,
                size: PulseButtonSize.small,
                onPressed: () => _add(context, ref, igd),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Through UPnP: some routers only accept forwards to the device asking.',
                style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, IgdDevice igd, PortMapping m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${m.protocol} ${m.externalPort}?'),
        content: Text(
          'Incoming connections on port ${m.externalPort} will no longer reach ${m.internalClient}. '
          '${m.description.isEmpty ? '' : 'Whatever added it ("${m.description}") may add it again.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await UpnpIgd.deleteMapping(igd, m);
      if (context.mounted) showPulseToast(context, 'Removed ${m.protocol} ${m.externalPort}', icon: PulseIcons.trash);
    } on UpnpFault catch (e) {
      if (context.mounted) showPulseToast(context, e.friendly, icon: PulseIcons.info);
    } on Object catch (e) {
      if (context.mounted) showPulseToast(context, "Couldn't reach the router: $e", icon: PulseIcons.info);
    }
    ref.invalidate(portMappingsProvider);
  }

  Future<void> _add(BuildContext context, WidgetRef ref, IgdDevice igd) async {
    final me = ref.read(networkInfoProvider).value?.link.localIpv4 ?? '';
    final m = await showDialog<PortMapping>(
      context: context,
      builder: (_) => _AddForwardDialog(defaultIp: me),
    );
    if (m == null || !context.mounted) return;
    try {
      await UpnpIgd.addMapping(igd, m);
      if (context.mounted) {
        showPulseToast(
          context,
          'Forwarding ${m.protocol} ${m.externalPort} to ${m.internalClient}',
          icon: PulseIcons.check,
        );
      }
    } on UpnpFault catch (e) {
      if (context.mounted) showPulseToast(context, e.friendly, icon: PulseIcons.info);
    } on Object catch (e) {
      if (context.mounted) showPulseToast(context, "Couldn't reach the router: $e", icon: PulseIcons.info);
    }
    ref.invalidate(portMappingsProvider);
  }
}

class _AddForwardDialog extends StatefulWidget {
  const _AddForwardDialog({required this.defaultIp});
  final String defaultIp;

  @override
  State<_AddForwardDialog> createState() => _AddForwardDialogState();
}

class _AddForwardDialogState extends State<_AddForwardDialog> {
  String _proto = 'TCP';
  late final _ip = TextEditingController(text: widget.defaultIp);
  final _ext = TextEditingController();
  final _int = TextEditingController();
  final _desc = TextEditingController(text: 'Pulse');

  @override
  void dispose() {
    for (final c in [_ip, _ext, _int, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _port(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return v != null && v > 0 && v < 65536 ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final fill = context.colors.surfaceContainerHighest;
    final ext = _port(_ext);
    final ip = _ip.text.trim();
    final valid =
        ext != null &&
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip) &&
        (_int.text.trim().isEmpty || _port(_int) != null);
    return AlertDialog(
      title: const Text('Add port forward'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PulseButtonGroup<String>(
              small: true,
              segments: const [PulseSegment('TCP', 'TCP'), PulseSegment('UDP', 'UDP')],
              selected: _proto,
              onChanged: (v) => setState(() => _proto = v),
            ),
            const SizedBox(height: 12),
            PulseTargetField(
              controller: _ext,
              hint: 'External port',
              icon: PulseIcons.globe,
              keyboardType: TextInputType.number,
              fillColor: fill,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            PulseTargetField(
              controller: _ip,
              hint: 'Device IP',
              icon: PulseIcons.laptop,
              keyboardType: TextInputType.number,
              fillColor: fill,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            PulseTargetField(
              controller: _int,
              hint: 'Device port (same as external)',
              icon: PulseIcons.port,
              keyboardType: TextInputType.number,
              fillColor: fill,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            PulseTargetField(
              controller: _desc,
              hint: 'Description',
              icon: PulseIcons.edit,
              keyboardType: TextInputType.text,
              fillColor: fill,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: !valid
              ? null
              : () => Navigator.pop(
                  context,
                  PortMapping(
                    protocol: _proto,
                    externalPort: ext,
                    internalClient: ip,
                    internalPort: _port(_int) ?? ext,
                    description: _desc.text.trim().isEmpty ? 'Pulse' : _desc.text.trim(),
                  ),
                ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _LoginCard extends ConsumerWidget {
  const _LoginCard({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cred = ref.watch(routerCredentialProvider).value;
    final saved = ref.watch(routerLoginSavedProvider).value ?? false;
    return PulseCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseIcon(cred == null ? PulseIcons.shield : PulseIcons.check, size: 22, color: c.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cred == null
                          ? 'Not signed in'
                          : saved
                          ? 'Login saved'
                          : 'Signed in for this session',
                      style: context.type.titleMedium,
                    ),
                    Text(
                      cred == null
                          ? 'Sign in so Pulse can manage the router and fill in its page.'
                          : cred.username.isEmpty
                          ? 'Password only'
                          : 'User "${cred.username}"',
                      style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IntrinsicWidth(
                child: PulseButton(
                  label: cred == null ? 'Sign in' : 'Change',
                  icon: cred == null ? PulseIcons.plus : PulseIcons.edit,
                  style: PulseButtonStyle.tonal,
                  size: PulseButtonSize.small,
                  onPressed: () => editRouterLogin(context, ref, profile, cred),
                ),
              ),
              if (cred != null) ...[
                const SizedBox(width: 8),
                IntrinsicWidth(
                  child: PulseButton(
                    label: saved ? 'Forget' : 'Sign out',
                    icon: PulseIcons.trash,
                    style: PulseButtonStyle.outlined,
                    size: PulseButtonSize.small,
                    onPressed: () async {
                      await RouterVault.delete(profile.id);
                      ref.read(sessionRouterLoginProvider.notifier).remove(profile.id);
                      ref.invalidate(routerCredentialProvider);
                      if (context.mounted) showPulseToast(context, 'Router login removed', icon: PulseIcons.trash);
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Pulse only saves the login if you tick 'Remember on this device'; then it stays in the system keystore and goes nowhere but your router.",
            style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
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

class _Capabilities extends ConsumerWidget {
  const _Capabilities({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = profile;
    final upnp = p.igd != null;
    final native = ref.watch(routerDriverTypeProvider).value != null;
    Widget item(bool ok, String title, String subtitle) => PulseListItem(
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: 3,
      leading: PulseIcon(ok ? PulseIcons.check : PulseIcons.x, size: 22, color: ok ? c.tertiary : c.onSurfaceVariant),
    );
    return PulseSegmentedList(
      animate: false,
      children: [
        item(true, 'Every setting, in the router page', 'Full router settings opens its own admin page, logged in.'),
        item(upnp, 'Internet status and live traffic', upnp ? 'Read from the router over UPnP.' : 'Needs UPnP on.'),
        item(upnp && p.igd!.canMap, 'Port forwards', upnp ? 'Add and remove over UPnP.' : 'Needs UPnP on.'),
        if (native)
          item(true, 'Devices, Wi-Fi and restart in Pulse', 'Pulse can sign in to this router and show them here.')
        else
          item(
            false,
            'Devices, Wi-Fi and restart in Pulse',
            "Pulse can't sign in to this router yet. Full router settings has everything.",
          ),
      ],
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
