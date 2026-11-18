import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../navigation/destinations.dart';
import 'router_actions.dart';

/// Every Wi-Fi network the router has: main, guest and smart-home, per band,
/// with on/off, name and password changes (verified or "Try it"), the
/// password and a join QR code.
class RouterWifiScreen extends ConsumerWidget {
  const RouterWifiScreen({super.key, this.focus});

  /// Scrolls the guest / smart-home networks first (the hub's Guest tile).
  final WifiKind? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(routerManageProvider);
    final v = m.value;
    return PulsePage(
      title: focus == WifiKind.guest ? 'Guest network' : 'Wi-Fi',
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
              for (final kind in _order(focus))
                if (v.wifi.any((n) => n.kind == kind)) ...[
                  PulseSectionLabel(_kindTitle(kind)),
                  _KindGrid(
                    networks: [
                      for (final n in v.wifi)
                        if (n.kind == kind) n,
                    ],
                    actions: v.actions,
                  ),
                ],
              if (v.wifi.isEmpty)
                const PulseEmptyState(
                  title: 'No Wi-Fi networks reported',
                  message: 'The router did not list any networks. Full router settings has its Wi-Fi page.',
                  icon: PulseIcons.wifi,
                  shape: PulseShape.cookie7,
                ),
              const SizedBox(height: 16),
              const _Note(),
            ],
    );
  }

  static List<WifiKind> _order(WifiKind? focus) =>
      focus == null ? WifiKind.values : [focus, ...WifiKind.values.where((k) => k != focus)];

  static String _kindTitle(WifiKind k) => switch (k) {
    WifiKind.main => 'Main network',
    WifiKind.guest => 'Guest network',
    WifiKind.iot => 'Smart-home network',
  };
}

/// What sub-pages show while the router isn't signed in or still loading.
Widget routerPageFallback(BuildContext context, WidgetRef ref, AsyncValue<Object?> m) => switch (m) {
  AsyncError(:final error) => PulseErrorBanner(
    title: "Couldn't read the router",
    message: error is RouterDriverException ? error.message : '$error',
    onRetry: () => ref.invalidate(routerManageProvider),
  ),
  AsyncData() => const Padding(
    padding: EdgeInsets.only(top: 48),
    child: PulseEmptyState(
      title: 'Not signed in',
      message: 'Sign in to the router on the Router page to see this.',
      icon: PulseIcons.shield,
      shape: PulseShape.cookie9,
    ),
  ),
  _ => const Padding(
    padding: EdgeInsets.only(top: 64),
    child: Center(child: CircularProgressIndicator()),
  ),
};

class _KindGrid extends StatelessWidget {
  const _KindGrid({required this.networks, required this.actions});
  final List<WifiNetwork> networks;
  final Set<String> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth >= 760 ? 2 : 1;
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final n in networks)
            SizedBox(
              width: w,
              child: _NetworkCard(network: n, actions: actions),
            ),
        ],
      );
    },
  );
}

class _NetworkCard extends ConsumerStatefulWidget {
  const _NetworkCard({required this.network, required this.actions});
  final WifiNetwork network;
  final Set<String> actions;

  @override
  ConsumerState<_NetworkCard> createState() => _NetworkCardState();
}

class _NetworkCardState extends ConsumerState<_NetworkCard> {
  bool _showPass = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.network;
    final c = context.colors;
    final caps = ref.watch(routerCapabilitiesProvider).value;
    final toggle = RouterActions.toggle(n), edit = RouterActions.edit(n);
    final canToggle = widget.actions.contains(toggle) && (caps?.offers(toggle) ?? true) && n.enabled != null;
    final canEdit = widget.actions.contains(edit) && (caps?.offers(edit) ?? true);
    final on = n.enabled ?? false;
    return PulseCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulsePill(n.bandLabel, tone: on ? PulsePillTone.lime : PulsePillTone.neutral, dot: true),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: canToggle || canEdit ? RouterTrustPill(canToggle ? toggle : edit) : null,
                ),
              ),
              if (canToggle)
                Switch(value: on, onChanged: (v) => _toggle(n, v))
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(on ? 'On' : 'Off', style: context.type.labelLarge!.copyWith(color: c.onSurfaceVariant)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            n.ssid ?? n.kindLabel,
            style: context.type.titleLarge!.copyWith(color: on ? c.onSurface : c.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          _kv(context, 'Security', _security(n.security)),
          if (n.channel != null && n.channel! > 0) _kv(context, 'Channel', '${n.channel}'),
          if (n.hidden == true) _kv(context, 'Name', 'Hidden from scans'),
          if (n.password != null)
            _kv(
              context,
              'Password',
              _showPass ? n.password! : '•' * 10,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PulseIconButton(
                    icon: _showPass ? PulseIcons.shield : PulseIcons.search,
                    tooltip: _showPass ? 'Hide password' : 'Show password',
                    visualSize: 32,
                    iconSize: 16,
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                  PulseIconButton(
                    icon: PulseIcons.copy,
                    tooltip: 'Copy password',
                    visualSize: 32,
                    iconSize: 16,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: n.password!));
                      showPulseToast(context, 'Password copied', icon: PulseIcons.copy);
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (n.ssid != null)
                PulseButton(
                  label: 'Share',
                  icon: PulseIcons.share,
                  style: PulseButtonStyle.tonal,
                  size: PulseButtonSize.small,
                  onPressed: () => _share(context, n),
                ),
              if (canEdit)
                PulseButton(
                  label: 'Edit',
                  icon: PulseIcons.edit,
                  style: PulseButtonStyle.outlined,
                  size: PulseButtonSize.small,
                  onPressed: () => _edit(n),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {Widget? trailing}) => SizedBox(
    height: 34,
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(k, style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(v, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        ?trailing,
      ],
    ),
  );

  static String _security(String? s) => switch (s?.toLowerCase()) {
    null => 'Unknown',
    'none' || 'open' => 'Open (no password)',
    'psk_sae' => 'WPA2 / WPA3',
    'sae' => 'WPA3',
    'psk' => 'WPA2',
    'wpa' => 'WPA2 Enterprise',
    'wep' => 'WEP (insecure)',
    final o => o.toUpperCase(),
  };

  Future<void> _toggle(WifiNetwork n, bool on) => runRouterAction(
    context,
    ref,
    action: RouterActions.toggle(n),
    confirmTitle: on ? 'Turn on ${n.ssid ?? n.kindLabel}?' : 'Turn off ${n.ssid ?? n.kindLabel}?',
    confirmBody: on
        ? null
        : n.kind == WifiKind.main
        ? 'Devices on ${n.bandLabel} disconnect. If this device is on it, Pulse loses the router too; '
              'turn it back on from another network or the router itself.'
        : 'Devices on this ${n.kindLabel.toLowerCase()} (${n.bandLabel}) disconnect.',
    confirmLabel: on ? 'Turn on' : 'Turn off',
    working: on ? 'Turning on ${n.bandLabel}…' : 'Turning off ${n.bandLabel}…',
    done: on ? '${n.ssid ?? n.kindLabel} is on' : '${n.ssid ?? n.kindLabel} is off',
    run: () => ref.read(routerManageProvider.notifier).setWifi(n, enabled: on),
  );

  Future<void> _edit(WifiNetwork n) async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditDialog(network: n),
    );
    if (r == null || !mounted) return;
    final (newSsid, newPass) = r;
    final ssid = newSsid.isNotEmpty && newSsid != n.ssid ? newSsid : null;
    final pass = newPass != (n.password ?? '') ? newPass : null;
    if (ssid == null && pass == null) return;
    await runRouterAction(
      context,
      ref,
      action: RouterActions.edit(n),
      confirmTitle: 'Save ${n.kindLabel.toLowerCase()} ${n.bandLabel}?',
      confirmBody:
          'Devices on this network have to reconnect with the new ${[if (ssid != null) 'name', if (pass != null) 'password'].join(' and ')}.',
      confirmLabel: 'Save',
      working: 'Saving ${n.bandLabel}…',
      done: '${n.kindLabel} ${n.bandLabel} updated',
      run: () => ref.read(routerManageProvider.notifier).setWifi(n, ssid: ssid, password: pass),
    );
  }

  void _share(BuildContext context, WifiNetwork n) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(n.ssid!, style: context.type.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              '${n.kindLabel} · ${n.bandLabel}',
              style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            WifiQr(ssid: n.ssid!, password: n.password, hidden: n.hidden ?? false),
            const SizedBox(height: 16),
            Text(
              'Point a phone camera at the code to join without typing the password.',
              textAlign: TextAlign.center,
              style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.network});
  final WifiNetwork network;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _ssid = TextEditingController(text: widget.network.ssid ?? '');
  late final _pass = TextEditingController(text: widget.network.password ?? '');
  bool _hide = true;

  @override
  void dispose() {
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  String? get _ssidError {
    final v = _ssid.text.trim();
    if (v.isEmpty) return 'Enter a name';
    if (v.length > 32) return 'At most 32 characters';
    return null;
  }

  String? get _passError {
    final v = _pass.text;
    if (widget.network.password == null && v.isEmpty) return null;
    if (v.length < 8 || v.length > 63) return '8 to 63 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.network;
    final valid = _ssidError == null && _passError == null;
    return AlertDialog(
      title: Text('${n.kindLabel} · ${n.bandLabel}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ssid,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Network name', errorText: _ssidError),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: _hide,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: '8 to 63 characters',
                errorText: _passError,
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: PulseIcon(_hide ? PulseIcons.search : PulseIcons.shield, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: valid ? () => Navigator.pop(context, (_ssid.text.trim(), _pass.text)) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      'Changes marked "Try it" have not been confirmed on this router model yet. Pulse reads the setting back '
      'afterwards and asks whether it worked. Channels, schedules and the rest are in Full router settings.',
      style: context.type.bodySmall!.copyWith(color: context.colors.onSurfaceVariant),
    ),
  );
}
