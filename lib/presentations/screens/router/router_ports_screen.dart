import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/network_provider.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../providers/router_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../../services/net/router/router_probe.dart';
import '../../../services/net/router/upnp_igd.dart';
import '../../navigation/destinations.dart';
import 'router_format.dart';

/// Port forwards: the ones apps opened over UPnP (add and remove), and the
/// router's own rules when Pulse is signed in (read only for now).
class RouterPortsScreen extends ConsumerWidget {
  const RouterPortsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = ref.watch(routerProfileProvider).value;
    final rules = ref.watch(routerManageProvider).value?.forwards ?? const <RouterForward>[];
    return PulsePage(
      title: 'Port forwards',
      backTo: Routes.router,
      actions: [
        PulseIconButton(
          icon: PulseIcons.refresh,
          tooltip: 'Read again',
          onPressed: () {
            ref.invalidate(portMappingsProvider);
            ref.read(routerManageProvider.notifier).refresh();
          },
        ),
      ],
      children: [
        if (p?.igd != null) ...[
          const PulseSectionLabel('Opened by apps (UPnP)'),
          _PortForwards(profile: p!),
        ] else
          PulseCard(
            child: Text(
              "UPnP is off on this router, so apps can't open ports and Pulse can't add any. Turn it on in Full "
              'router settings (usually under NAT forwarding) if a game or app needs incoming connections.',
              style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        if (rules.isNotEmpty) ...[
          const PulseSectionLabel('Router rules'),
          PulseSegmentedList(
            animate: false,
            children: [
              for (final r in rules)
                PulseListItem(
                  title: r.name.isEmpty ? '${r.protocol} ${r.externalPort}' : r.name,
                  subtitle:
                      '${r.protocol} ${r.externalPort} → ${r.internalIp}:${r.internalPort}${r.enabled ? '' : ' · off'}',
                  leading: PulseIcon(PulseIcons.port, size: 22, color: c.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Rules you made in the router. Edit them in Full router settings.',
              style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
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
                  title: m.description.isEmpty ? '${m.protocol} ${m.externalPort}' : m.description,
                  subtitleMaxLines: 2,
                  subtitle: [
                    '${m.protocol} ${m.externalPort} → ${m.internalClient}:${m.internalPort}',
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
        Align(
          alignment: Alignment.centerLeft,
          child: PulseButton(
            label: 'Add port forward',
            icon: PulseIcons.plus,
            style: PulseButtonStyle.tonal,
            size: PulseButtonSize.small,
            onPressed: () => _add(context, ref, igd),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Added through UPnP. Some routers only accept forwards to the device that asks.',
            style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
          ),
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
