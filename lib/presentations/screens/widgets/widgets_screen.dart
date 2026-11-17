import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../services/widgets/home_widgets.dart';
import '../../navigation/destinations.dart';
import '../settings/settings_widgets.dart';
import 'widget_config_screen.dart';

/// Settings › Home screen widgets: what's available, how to add each one
/// (Android pins it straight from here), and the widgets already placed,
/// each editable.
class WidgetsScreen extends ConsumerStatefulWidget {
  const WidgetsScreen({super.key});

  @override
  ConsumerState<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends ConsumerState<WidgetsScreen> with WidgetsBindingObserver {
  List<PlacedWidget> _placed = const [];
  bool _canPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the home screen after adding or removing one.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final placed = await PulseWidgets.installed();
    final canPin = await PulseWidgets.canPin();
    if (!mounted) return;
    setState(() {
      _placed = placed;
      _canPin = canPin;
    });
  }

  Future<void> _add(WidgetKind kind) async {
    if (_canPin) {
      await PulseWidgets.pin(kind);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add the ${kind.label} widget'),
        content: Text(
          Platform.isIOS
              ? 'Touch and hold an empty spot on your Home Screen, tap Edit › Add Widget, search for Pulse '
                    'and pick ${kind.label}. Touch and hold the widget, then tap Edit Widget to choose hosts and style.'
              : 'Touch and hold an empty spot on your home screen, tap Widgets, find Pulse and drag '
                    '${kind.label} onto the screen. Pulse then asks how you want it set up.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final add = SettingsGroup(
      items: [
        for (final k in WidgetKind.values)
          (r) => PulseListItem(
            title: k.label,
            subtitle: k.description,
            subtitleMaxLines: 2,
            minHeight: 76,
            leading: PulseShapeBadge(
              shape: PulseShape.cookie9,
              tone: widgetKindTone(k),
              icon: widgetKindIcon(k),
              size: 44,
            ),
            trailing: _canPin
                ? IntrinsicWidth(
                    child: PulseButton(
                      label: 'Add',
                      icon: PulseIcons.plus,
                      style: PulseButtonStyle.tonal,
                      size: PulseButtonSize.small,
                      onPressed: () => _add(k),
                    ),
                  )
                : PulseIcon(PulseIcons.chevR, size: 20, color: c.onSurfaceVariant),
            onTap: () => _add(k),
          ),
      ],
    );
    final placed = _placed.isEmpty
        ? null
        : SettingsGroup(
            items: [
              for (final w in _placed)
                (r) => SettingsValueItem(
                  icon: widgetKindIcon(w.kind),
                  title: w.kind.label,
                  subtitle: Platform.isIOS
                      ? '${_family(w.iOSFamily)} · edit it on the Home Screen'
                      : 'Tap to change hosts, refresh and style',
                  chevron: Platform.isAndroid,
                  onTap: Platform.isAndroid && w.androidId != null
                      ? () => context.push('${Routes.widgetConfigure}?id=${w.androidId}&kind=${w.kind.name}&inApp=1')
                      : null,
                ),
            ],
          );
    final about = SettingsGroup(
      items: [
        (r) => SettingsValueItem(
          icon: PulseIcons.refresh,
          title: 'Live without opening Pulse',
          subtitle: Platform.isIOS
              ? 'Ping widgets measure on their own; the refresh button pings right away (iOS 17+). '
                    'iOS decides how often widgets update in the background.'
              : 'Ping widgets measure on their own; refresh pings right away. Background refresh runs '
                    'every 15 minutes at most, as Android allows.',
        ),
        (r) => const SettingsValueItem(
          icon: PulseIcons.gauge,
          title: 'Speed tests run in the app',
          subtitle: 'A test moves tens of megabytes, so the widget\'s Run button opens Pulse and starts it there.',
        ),
        (r) => const SettingsValueItem(
          icon: PulseIcons.shield,
          title: 'Private by default',
          subtitle: 'Addresses on the Network widget are partly hidden unless you choose to show them.',
        ),
      ],
    );
    return PulsePage(
      title: 'Home screen widgets',
      backTo: Routes.settings,
      showBack: true,
      children: [
        const _Hero(),
        const PulseSectionLabel('Add a widget'),
        add,
        if (placed != null) ...[const PulseSectionLabel('On your home screen'), placed],
        const PulseSectionLabel('Good to know'),
        about,
        const SizedBox(height: 24),
      ],
    );
  }

  static String _family(String? f) => switch (f) {
    'systemSmall' => 'Small',
    'systemMedium' => 'Medium',
    'systemLarge' => 'Large',
    'systemExtraLarge' => 'Extra large',
    'accessoryCircular' || 'accessoryRectangular' || 'accessoryInline' => 'Lock Screen',
    _ => 'Placed',
  };
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(32)),
      child: Column(
        children: [
          const PulsePop(
            child: PulseShapeBadge(
              shape: PulseShape.cookie9,
              tone: PulseTone.lavender,
              icon: PulseIcons.grid,
              size: 96,
            ),
          ),
          const SizedBox(height: 18),
          Text('Pulse on your home screen', textAlign: TextAlign.center, style: context.type.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Live ping, your last speed test, monitor status, your connection and shortcuts, '
            'in any size from one cell up.',
            textAlign: TextAlign.center,
            style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
