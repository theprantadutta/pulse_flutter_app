import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../navigation/destinations.dart';
import 'router_format.dart';
import 'router_wifi_screen.dart' show routerPageFallback;

enum _Filter { all, wifi, wired, guest }

enum _Sort { busy, name, signal }

/// Everything connected to the router, as the router sees it: live speed,
/// signal, time online and data used, refreshed every 15 seconds.
class RouterDevicesScreen extends ConsumerStatefulWidget {
  const RouterDevicesScreen({super.key});

  @override
  ConsumerState<RouterDevicesScreen> createState() => _RouterDevicesScreenState();
}

class _RouterDevicesScreenState extends ConsumerState<RouterDevicesScreen> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.busy;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(RouterClient d) {
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.wifi => d.link != ClientLink.wired && !d.guest,
      _Filter.wired => d.link == ClientLink.wired,
      _Filter.guest => d.guest,
    };
    final q = _search.text.trim().toLowerCase();
    if (!ok || q.isEmpty) return ok;
    return [d.name, d.ip, d.mac, d.kind].any((v) => v != null && v.toLowerCase().contains(q));
  }

  int _compare(RouterClient a, RouterClient b) {
    String n(RouterClient d) => (d.name ?? d.ip ?? d.mac).toLowerCase();
    final s = switch (_sort) {
      _Sort.busy => ((b.downBps ?? 0) + (b.upBps ?? 0)).compareTo((a.downBps ?? 0) + (a.upBps ?? 0)),
      _Sort.signal => (b.signal ?? -999).compareTo(a.signal ?? -999),
      _Sort.name => 0,
    };
    return s != 0 ? s : n(a).compareTo(n(b));
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(routerManageProvider);
    final v = m.value;
    final all = v?.clients ?? const <RouterClient>[];
    final shown = all.where(_matches).toList()..sort(_compare);
    final wired = all.where((d) => d.link == ClientLink.wired).length;
    final guest = all.where((d) => d.guest).length;
    final down = all.fold<double>(0, (a, d) => a + (d.downBps ?? 0));
    final up = all.fold<double>(0, (a, d) => a + (d.upBps ?? 0));
    final hasRates = all.any((d) => d.downBps != null);
    return PulsePage(
      title: 'Devices',
      subtitle: v == null ? null : '${all.length} connected',
      backTo: Routes.router,
      actions: [
        PulseIconButton(
          icon: PulseIcons.refresh,
          tooltip: 'Read again',
          onPressed: () => ref.read(routerManageProvider.notifier).refresh(),
        ),
      ],
      children: v == null
          ? [routerPageFallback(context, ref, m)]
          : [
              PulseStatRow(
                stats: [
                  PulseStat('All', '${all.length}'),
                  PulseStat('Wi-Fi', '${all.length - wired - guest}'),
                  PulseStat('Wired', '$wired'),
                  if (hasRates) ...[
                    PulseStat('Down', splitRate(down).$1, unit: splitRate(down).$2),
                    PulseStat('Up', splitRate(up).$1, unit: splitRate(up).$2),
                  ] else
                    PulseStat('Guest', '$guest'),
                ],
              ),
              const SizedBox(height: 12),
              if (all.length > 8) ...[
                PulseTargetField(
                  controller: _search,
                  hint: 'Search name, IP or MAC',
                  keyboardType: TextInputType.text,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (f, label) in [
                    (_Filter.all, 'All ${all.length}'),
                    (_Filter.wifi, 'Wi-Fi ${all.length - wired - guest}'),
                    (_Filter.wired, 'Wired $wired'),
                    if (guest > 0 || v.wifi.any((n) => n.guest)) (_Filter.guest, 'Guest $guest'),
                  ])
                    PulseChip(
                      label: label,
                      small: true,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                  PopupMenuButton<_Sort>(
                    tooltip: 'Sort',
                    initialValue: _sort,
                    onSelected: (s) => setState(() => _sort = s),
                    itemBuilder: (_) => [
                      if (hasRates) const PopupMenuItem(value: _Sort.busy, child: Text('Busiest first')),
                      const PopupMenuItem(value: _Sort.name, child: Text('Name')),
                      if (all.any((d) => d.signal != null))
                        const PopupMenuItem(value: _Sort.signal, child: Text('Strongest signal')),
                    ],
                    child: PulseChip(
                      label: switch (_sort) {
                        _Sort.busy => 'Busiest',
                        _Sort.name => 'Name',
                        _Sort.signal => 'Signal',
                      },
                      small: true,
                      icon: PulseIcons.filter,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                PulseCard(
                  child: Text(
                    all.isEmpty ? 'The router reports no devices.' : 'No device matches.',
                    style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, box) {
                    final cols = box.maxWidth >= 900 ? 2 : 1;
                    if (cols == 1) {
                      return PulseSegmentedList(animate: false, children: [for (final d in shown) _DeviceRow(d: d)]);
                    }
                    final half = (shown.length / 2).ceil();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PulseSegmentedList(
                            animate: false,
                            children: [for (final d in shown.take(half)) _DeviceRow(d: d)],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PulseSegmentedList(
                            animate: false,
                            children: [for (final d in shown.skip(half)) _DeviceRow(d: d)],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'As the router reports them; updates every 15 seconds while this page is open.',
                  style: context.type.bodySmall!.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.d});
  final RouterClient d;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = (d.downBps ?? 0) + (d.upBps ?? 0) > 0;
    return PulseListItem(
      title: d.name ?? d.ip ?? d.mac,
      subtitle: [linkLabel(d), if (d.ip != null && d.name != null) d.ip!, ?signalLabel(d.signal)].join(' · '),
      subtitleMaxLines: 2,
      leading: deviceBadge(context, d),
      onTap: () => showDeviceSheet(context, d),
      trailing: busy
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('↓ ${fmtRate(d.downBps)}', style: context.type.labelMedium),
                Text('↑ ${fmtRate(d.upBps)}', style: context.type.labelSmall!.copyWith(color: c.onSurfaceVariant)),
              ],
            )
          : PulseIcon(PulseIcons.chevR, size: 18, color: c.onSurfaceVariant),
    );
  }
}

/// Everything the router knows about one device, with copy buttons.
void showDeviceSheet(BuildContext context, RouterClient d) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final c = context.colors;
    Widget row(String k, String v, {bool copy = false}) => PulseListItem(
      overline: k,
      title: v,
      trailing: copy
          ? PulseIconButton(
              icon: PulseIcons.copy,
              tooltip: 'Copy $k',
              visualSize: 36,
              iconSize: 18,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: v));
                showPulseToast(context, 'Copied $v', icon: PulseIcons.copy);
              },
            )
          : null,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                deviceBadge(context, d, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name ?? d.ip ?? d.mac, style: context.type.titleLarge),
                      Text(linkLabel(d), style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            if ((d.downBps ?? 0) + (d.upBps ?? 0) > 0) ...[
              const SizedBox(height: 16),
              PulseStatRow(
                stats: [
                  PulseStat('Download', splitRate(d.downBps!).$1, unit: splitRate(d.downBps!).$2),
                  PulseStat('Upload', splitRate(d.upBps ?? 0).$1, unit: splitRate(d.upBps ?? 0).$2),
                ],
              ),
            ],
            const SizedBox(height: 16),
            PulseSegmentedList(
              animate: false,
              children: [
                if (d.ip != null) row('IP address', d.ip!, copy: true),
                row('MAC address', d.mac, copy: true),
                if (d.signal != null) row('Signal', '${signalLabel(d.signal)} (${d.signal} dBm)'),
                if (d.online != null) row('Connected for', fmtUptime(d.online!)),
                if (d.trafficBytes != null) row('Data used', fmtBytes(d.trafficBytes!)),
                if (d.kind != null) row('Type (router guess)', d.kind!),
              ],
            ),
          ],
        ),
      ),
    );
  },
);
