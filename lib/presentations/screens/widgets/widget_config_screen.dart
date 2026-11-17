import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/ping_provider.dart';
import '../../../services/widgets/home_widgets.dart';
import '../../navigation/destinations.dart';

/// Badge icon and tone of each widget kind (Settings › Home screen widgets
/// and the configure screen).
PulseIcons widgetKindIcon(WidgetKind k) => switch (k) {
  WidgetKind.ping => PulseIcons.pulse,
  WidgetKind.multiping => PulseIcons.signal,
  WidgetKind.speed => PulseIcons.gauge,
  WidgetKind.monitor => PulseIcons.monitor,
  WidgetKind.actions => PulseIcons.grid,
  WidgetKind.network => PulseIcons.wifi,
};

PulseTone widgetKindTone(WidgetKind k) => switch (k) {
  WidgetKind.ping || WidgetKind.monitor => PulseTone.pink,
  WidgetKind.multiping || WidgetKind.network => PulseTone.lavender,
  WidgetKind.speed || WidgetKind.actions => PulseTone.lime,
};

const _quickHosts = [
  WidgetTarget(kGatewayHost, 'Router'),
  WidgetTarget('1.1.1.1', 'Cloudflare'),
  WidgetTarget('8.8.8.8', 'Google'),
  WidgetTarget('9.9.9.9', 'Quad9'),
];

const _maxHosts = 6;

/// Settings for one placed widget (Android). Opened by the launcher when a
/// widget is added or reconfigured (WidgetConfigActivity, [fromLauncher]) or
/// from Settings › Home screen widgets.
class WidgetConfigScreen extends ConsumerStatefulWidget {
  const WidgetConfigScreen({super.key, required this.widgetId, required this.kind, required this.fromLauncher});
  final int widgetId;
  final WidgetKind kind;
  final bool fromLauncher;

  @override
  ConsumerState<WidgetConfigScreen> createState() => _WidgetConfigScreenState();
}

class _WidgetConfigScreenState extends ConsumerState<WidgetConfigScreen> {
  WidgetSettings? _s;
  List<WidgetTarget> _saved = const [];
  final _host = TextEditingController();
  final _name = TextEditingController();
  bool _saving = false;

  WidgetKind get kind => widget.kind;

  @override
  void initState() {
    super.initState();
    PulseWidgets.settingsFor(widget.widgetId, kind).then((s) {
      if (!mounted) return;
      setState(() => _s = s);
      if (kind == WidgetKind.ping && s.targets.isNotEmpty) {
        final t = s.targets.first;
        _host.text = t.host == kGatewayHost ? '' : t.host;
        _name.text = t.name ?? '';
      }
    });
    ref.read(savedTargetsRepositoryProvider).watch().first.then((list) {
      if (mounted) setState(() => _saved = [for (final t in list) WidgetTarget(t.host, t.name)]);
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _name.dispose();
    super.dispose();
  }

  void _set(WidgetSettings Function(WidgetSettings s) f) => setState(() => _s = f(_s!));

  /// The single host of a Ping widget, from the fields (or the Router chip).
  WidgetTarget? get _pingTarget {
    final host = _host.text.trim();
    final name = _name.text.trim();
    if (host.isEmpty) {
      final current = _s?.targets.firstOrNull;
      return current?.host == kGatewayHost ? WidgetTarget(kGatewayHost, name.isEmpty ? 'Router' : name) : null;
    }
    return WidgetTarget(host, name.isEmpty ? null : name);
  }

  Future<void> _save() async {
    var s = _s!;
    if (kind == WidgetKind.ping) {
      final t = _pingTarget;
      if (t == null) {
        showPulseToast(context, 'Enter a host or IP to ping', icon: PulseIcons.pulse);
        return;
      }
      s = s.copyWith(targets: [t]);
    }
    if (kind == WidgetKind.multiping && s.targets.isEmpty) {
      showPulseToast(context, 'Add at least one host', icon: PulseIcons.signal);
      return;
    }
    setState(() => _saving = true);
    await PulseWidgets.saveSettings(widget.widgetId, kind, s);
    if (!mounted) return;
    if (widget.fromLauncher) {
      await PulseWidgets.finishConfigure();
    } else {
      showPulseToast(context, '${kind.label} widget updated', icon: PulseIcons.check);
      context.canPop() ? context.pop() : context.go(Routes.widgets);
    }
  }

  void _cancel() {
    if (widget.fromLauncher) {
      // RESULT_CANCELED: a new widget isn't added, an existing one keeps its settings.
      SystemNavigator.pop();
    } else {
      context.canPop() ? context.pop() : context.go(Routes.widgets);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final children = <Widget>[
      _Header(kind: kind),
      if (s != null) ..._sections(context, s),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: PulseButton(
              label: 'Cancel',
              style: PulseButtonStyle.outlined,
              size: PulseButtonSize.large,
              onPressed: _saving ? null : _cancel,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: PulseButton(
              label: widget.fromLauncher ? 'Add widget' : 'Save',
              icon: PulseIcons.check,
              style: PulseButtonStyle.pink,
              size: PulseButtonSize.large,
              onPressed: s == null || _saving ? null : _save,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
    ];
    return PopScope(
      canPop: !widget.fromLauncher,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: PulsePage(
        title: widget.fromLauncher ? 'New widget' : 'Edit widget',
        showBack: true,
        backTo: widget.fromLauncher ? null : Routes.widgets,
        children: children,
      ),
    );
  }

  List<Widget> _sections(BuildContext context, WidgetSettings s) {
    final out = <Widget>[];
    switch (kind) {
      case WidgetKind.ping:
        out.addAll([
          const PulseSectionLabel('Host'),
          PulseTargetField(controller: _host, hint: 'Host or IP, e.g. 1.1.1.1', onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          PulseTargetField(
            controller: _name,
            hint: 'Name (optional)',
            icon: PulseIcons.edit,
            keyboardType: TextInputType.text,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _HostChips(
            hosts: [..._quickHosts, ..._saved],
            isSelected: (t) => t.host == kGatewayHost
                ? _host.text.trim().isEmpty && s.targets.firstOrNull?.host == kGatewayHost
                : _host.text.trim().toLowerCase() == t.host.toLowerCase(),
            onTap: (t) {
              _host.text = t.host == kGatewayHost ? '' : t.host;
              _name.text = t.name ?? '';
              _set((x) => x.copyWith(targets: [t]));
            },
          ),
        ]);
      case WidgetKind.multiping:
        out.addAll([
          PulseSectionLabel('Hosts · ${s.targets.length} of $_maxHosts'),
          if (s.targets.isNotEmpty)
            PulseSegmentedList(
              animate: false,
              children: [
                for (final (i, t) in s.targets.indexed)
                  PulseListItem(
                    title: t.title,
                    subtitle: t.host == kGatewayHost ? 'Your current router' : (t.title == t.host ? null : t.host),
                    leading: PulseIcon(t.host == kGatewayHost ? PulseIcons.router : PulseIcons.server, size: 22),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0)
                          PulseIconButton(
                            icon: PulseIcons.up,
                            tooltip: 'Move up',
                            visualSize: 36,
                            iconSize: 18,
                            onPressed: () => _set((x) {
                              final l = [...x.targets]..insert(i - 1, x.targets[i]);
                              l.removeAt(i + 1);
                              return x.copyWith(targets: l);
                            }),
                          ),
                        PulseIconButton(
                          icon: PulseIcons.x,
                          tooltip: 'Remove ${t.title}',
                          visualSize: 36,
                          iconSize: 18,
                          onPressed: () => _set((x) => x.copyWith(targets: [...x.targets]..removeAt(i))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (s.targets.length < _maxHosts) ...[
            const SizedBox(height: 12),
            PulseTargetField(
              controller: _host,
              hint: 'Add a host or IP',
              icon: PulseIcons.plus,
              onSubmitted: (v) {
                final h = v.trim();
                if (h.isEmpty || s.targets.any((t) => t.host.toLowerCase() == h.toLowerCase())) return;
                _host.clear();
                _set((x) => x.copyWith(targets: [...x.targets, WidgetTarget(h)]));
              },
            ),
            const SizedBox(height: 12),
            _HostChips(
              hosts: [
                for (final t in [..._quickHosts, ..._saved])
                  if (!s.targets.any((x) => x.host.toLowerCase() == t.host.toLowerCase())) t,
              ],
              isSelected: (_) => false,
              onTap: (t) => _set((x) => x.copyWith(targets: [...x.targets, t])),
            ),
          ],
        ]);
      case WidgetKind.actions:
        final unused = WidgetTool.values.where((t) => !s.tools.contains(t)).toList();
        out.addAll([
          const PulseSectionLabel('Shortcuts, in order'),
          Text(
            'The widget shows as many as fit its size, from the first. Tap one to remove it.',
            style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, t) in s.tools.indexed)
                PulseChip(
                  label: '${i + 1}  ${t.label}',
                  selected: true,
                  showCheck: false,
                  onTap: s.tools.length <= 1 ? null : () => _set((x) => x.copyWith(tools: [...x.tools]..remove(t))),
                ),
            ],
          ),
          if (unused.isNotEmpty) ...[
            const PulseSectionLabel('Add'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in unused)
                  PulseChip(
                    label: t.label,
                    icon: PulseIcons.plus,
                    onTap: () => _set((x) => x.copyWith(tools: [...x.tools, t])),
                  ),
              ],
            ),
          ],
        ]);
      case WidgetKind.network:
        out.addAll([
          const PulseSectionLabel('Show'),
          PulseSegmentedList(
            animate: false,
            children: [
              PulseSwitchItem(
                icon: PulseIcons.lan,
                title: 'Local addresses',
                subtitle: 'Off shows them partly hidden',
                value: s.showLocalIp,
                onChanged: (v) => _set((x) => x.copyWith(showLocalIp: v)),
              ),
              PulseSwitchItem(
                icon: PulseIcons.globe,
                title: 'Public IP address',
                subtitle: 'The one Pulse last looked up. Off shows it partly hidden',
                value: s.showPublicIp,
                onChanged: (v) => _set((x) => x.copyWith(showPublicIp: v)),
              ),
            ],
          ),
        ]);
      case WidgetKind.speed:
      case WidgetKind.monitor:
        out.addAll([
          const PulseSectionLabel('What it shows'),
          Text(
            kind == WidgetKind.speed
                ? 'Your latest speed test, and the recent ones when the widget is tall enough. '
                      'Run opens Pulse and starts a test.'
                : 'Monitor targets with their status, uptime and, when tall, the last 24 hours. '
                      'It updates after every monitor check, even with Pulse closed while Run in background is on.',
            style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ]);
    }

    if (kind.pings) {
      out.addAll([
        const PulseSectionLabel('Refresh in the background'),
        PulseButtonGroup<int>(
          small: true,
          segments: const [
            PulseSegment(0, 'Tap'),
            PulseSegment(15, '15 min'),
            PulseSegment(30, '30 min'),
            PulseSegment(60, '1 h'),
            PulseSegment(180, '3 h'),
          ],
          selected: s.intervalMin,
          onChanged: (v) => _set((x) => x.copyWith(intervalMin: v)),
        ),
        const SizedBox(height: 6),
        Text(
          s.intervalMin == 0
              ? 'Only pings when you tap refresh on the widget.'
              : 'Android may delay background refreshes to save battery. Refresh on the widget always pings now.',
          style: context.type.bodySmall!.copyWith(color: context.colors.onSurfaceVariant),
        ),
        if (kind != WidgetKind.network) ...[
          const PulseSectionLabel('Pings per refresh'),
          PulseButtonGroup<int>(
            small: true,
            segments: const [PulseSegment(1, '1'), PulseSegment(4, '4'), PulseSegment(6, '6'), PulseSegment(10, '10')],
            selected: s.probes,
            onChanged: (v) => _set((x) => x.copyWith(probes: v)),
          ),
          const SizedBox(height: 12),
          PulseSegmentedList(
            animate: false,
            children: [
              PulseSwitchItem(
                icon: PulseIcons.signal,
                title: 'Reply chart',
                subtitle: 'Bars for the last replies, when there is room',
                value: s.showChart,
                onChanged: (v) => _set((x) => x.copyWith(showChart: v)),
              ),
            ],
          ),
        ],
      ]);
    }

    out.addAll([
      const PulseSectionLabel('Style'),
      PulseButtonGroup<String>(
        small: true,
        segments: [
          const PulseSegment('', 'Like Pulse'),
          const PulseSegment('app', 'Pulse colors'),
          if (Platform.isAndroid) const PulseSegment('wallpaper', 'Wallpaper'),
        ],
        selected: s.colors,
        onChanged: (v) => _set((x) => x.copyWith(colors: v)),
      ),
      const SizedBox(height: 6),
      Text(switch (s.colors) {
        'app' => 'Plum surfaces with the accent picked in Settings › Appearance.',
        'wallpaper' => 'Material You colors from your wallpaper (Android 12 and later).',
        _ => 'Follows Settings › Appearance: your accent, or wallpaper colors when Dynamic color is on.',
      }, style: context.type.bodySmall!.copyWith(color: context.colors.onSurfaceVariant)),
      const SizedBox(height: 12),
      PulseButtonGroup<String>(
        small: true,
        segments: const [
          PulseSegment('solid', 'Solid'),
          PulseSegment('translucent', 'Translucent'),
          PulseSegment('clear', 'Clear'),
        ],
        selected: s.background,
        onChanged: (v) => _set((x) => x.copyWith(background: v)),
      ),
    ]);
    return out;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.kind});
  final WidgetKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          PulseShapeBadge(shape: PulseShape.cookie9, tone: widgetKindTone(kind), icon: widgetKindIcon(kind), size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.label, style: context.type.titleLarge),
                const SizedBox(height: 4),
                Text(kind.description, style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HostChips extends StatelessWidget {
  const _HostChips({required this.hosts, required this.isSelected, required this.onTap});
  final List<WidgetTarget> hosts;
  final bool Function(WidgetTarget) isSelected;
  final ValueChanged<WidgetTarget> onTap;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in hosts)
          if (seen.add(t.host.toLowerCase()))
            PulseChip(
              label: t.title,
              icon: t.host == kGatewayHost ? PulseIcons.router : null,
              selected: isSelected(t),
              onTap: () => onTap(t),
            ),
      ],
    );
  }
}
