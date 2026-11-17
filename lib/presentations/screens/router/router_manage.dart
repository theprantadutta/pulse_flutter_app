import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../providers/router_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../../services/net/router/router_probe.dart';
import 'router_screen.dart' show editRouterLogin, fmtRate, fmtUptime;

/// The natively managed part of the Router screen (routers Pulse has a driver
/// for): a sign-in prompt, or the router's status, devices, Wi-Fi networks,
/// its own port-forward rules and Restart.
List<Widget> routerManageSections(BuildContext context, WidgetRef ref, RouterProfile p) {
  if (driverFor(p) == null) return const [];
  final cred = ref.watch(routerCredentialProvider).value;
  if (cred == null) return [const SizedBox(height: 12), _SignInCard(profile: p)];
  final m = ref.watch(routerManageProvider);
  return switch (m) {
    AsyncData(value: final v?) => [
      if (v.overview != null) ...[const PulseSectionLabel('Router'), _Overview(o: v.overview!)],
      if (v.features.contains(RouterFeature.clients)) ...[
        PulseSectionLabel('Devices · ${v.clients.length}'),
        _Devices(clients: v.clients),
      ],
      if (v.wifi.isNotEmpty) ...[const PulseSectionLabel('Wi-Fi'), _Wifi(networks: v.wifi)],
      if (v.forwards.isNotEmpty) ...[const PulseSectionLabel('Router port forwards'), _Forwards(rules: v.forwards)],
      const PulseSectionLabel('Router actions'),
      _Actions(profile: p),
    ],
    AsyncError(:final error) => [
      const SizedBox(height: 12),
      PulseErrorBanner(
        title: "Couldn't sign in to the router",
        message: error is RouterDriverException
            ? [
                error.message,
                if (error.detail != null && error.kind == RouterErrorKind.wrongPassword) error.detail!,
              ].join(' ')
            : '$error',
        onRetry: () => ref.invalidate(routerManageProvider),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: IntrinsicWidth(
          child: PulseButton(
            label: 'Change login',
            icon: PulseIcons.edit,
            style: PulseButtonStyle.tonal,
            size: PulseButtonSize.small,
            onPressed: () => editRouterLogin(context, ref, p, cred),
          ),
        ),
      ),
    ],
    _ => [
      const SizedBox(height: 12),
      const PulseCard(
        child: Row(
          children: [
            SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 14),
            Expanded(child: Text('Signing in to your router…')),
          ],
        ),
      ),
    ],
  };
}

class _SignInCard extends ConsumerWidget {
  const _SignInCard({required this.profile});
  final RouterProfile profile;

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
            'Manage your ${profile.brand.label} here',
            style: context.type.titleLarge!.copyWith(color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in with the router password to see every device, switch and edit Wi-Fi networks, '
            'check the router itself and restart it — all in Pulse.',
            style: context.type.bodyMedium!.copyWith(color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          IntrinsicWidth(
            child: PulseButton(
              label: 'Sign in to router',
              icon: PulseIcons.shield,
              style: PulseButtonStyle.pink,
              onPressed: () => editRouterLogin(context, ref, profile, null),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Pulse signs in the way the router\'s own page does, so the page signs out if it is open in a browser.',
            style: context.type.bodySmall!.copyWith(color: c.onPrimaryContainer),
          ),
        ],
      ),
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
    final c = context.colors;
    String mask(String ip) {
      final p = ip.split('.');
      return p.length == 4 ? '${p[0]}.••.••.${p[3]}' : '••••';
    }

    Widget row(String k, String v, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(k, style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(v, style: context.type.titleSmall, overflow: TextOverflow.ellipsis),
          ),
          ?trailing,
        ],
      ),
    );

    Widget meter(String label, double v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ${(v * 100).round()}%', style: context.type.labelLarge!.copyWith(color: c.onSurfaceVariant)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v.clamp(0, 1),
              minHeight: 8,
              backgroundColor: c.surfaceContainerHighest,
              color: v > .85 ? c.error : c.tertiary,
            ),
          ),
        ],
      ),
    );

    return PulseCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o.cpu != null || o.memory != null) ...[
            Row(
              children: [
                if (o.cpu != null) meter('CPU', o.cpu!),
                if (o.cpu != null && o.memory != null) const SizedBox(width: 16),
                if (o.memory != null) meter('Memory', o.memory!),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (o.model != null || o.firmware != null)
            row(
              'Model',
              [o.model, if (o.hardwareVersion != null) 'v${o.hardwareVersion}'].whereType<String>().join(' '),
            ),
          if (o.firmware != null) row('Firmware', o.firmware!),
          if (o.wanIp != null)
            row(
              'Internet IP',
              _showWan ? o.wanIp! : mask(o.wanIp!),
              trailing: PulseIconButton(
                icon: _showWan ? PulseIcons.shield : PulseIcons.search,
                tooltip: _showWan ? 'Hide address' : 'Show address',
                visualSize: 32,
                iconSize: 16,
                onPressed: () => setState(() => _showWan = !_showWan),
              ),
            ),
          if (o.wanType != null) row('Connection', _wanType(o.wanType!)),
          if (o.wanUptime != null) row('Online for', fmtUptime(o.wanUptime!)),
          if (o.lanIp != null) row('Router address', o.lanIp!),
          if (o.dhcpServer != null) row('DHCP server', o.dhcpServer! ? 'On' : 'Off'),
          if (o.ipv6 != null) row('IPv6', o.ipv6!),
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

class _Devices extends StatelessWidget {
  const _Devices({required this.clients});
  final List<RouterClient> clients;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (clients.isEmpty) {
      return PulseCard(
        child: Text(
          'The router reports no devices.',
          style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
        ),
      );
    }
    final list = [...clients]
      ..sort((a, b) {
        final s = ((b.downBps ?? 0) + (b.upBps ?? 0)).compareTo((a.downBps ?? 0) + (a.upBps ?? 0));
        return s != 0 ? s : (a.name ?? a.ip ?? a.mac).toLowerCase().compareTo((b.name ?? b.ip ?? b.mac).toLowerCase());
      });
    return PulseSegmentedList(
      animate: false,
      children: [
        for (final d in list)
          PulseListItem(
            title: d.name ?? d.ip ?? d.mac,
            subtitle: [
              _link(d),
              if (d.ip != null && d.name != null) d.ip!,
              d.mac,
              if (d.signal != null) '${d.signal} dBm',
            ].join(' · '),
            subtitleMaxLines: 2,
            leading: PulseIcon(
              d.link == ClientLink.wired ? PulseIcons.laptop : PulseIcons.wifi,
              size: 22,
              color: d.guest ? c.tertiary : c.onSurfaceVariant,
            ),
            trailing: (d.downBps ?? 0) + (d.upBps ?? 0) > 0
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('↓ ${fmtRate(d.downBps)}', style: context.type.labelMedium),
                      Text(
                        '↑ ${fmtRate(d.upBps)}',
                        style: context.type.labelSmall!.copyWith(color: c.onSurfaceVariant),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }

  static String _link(RouterClient d) => switch (d.link) {
    ClientLink.wired => 'Wired',
    ClientLink.wifi2g => 'Wi-Fi 2.4 GHz',
    ClientLink.wifi5g => 'Wi-Fi 5 GHz',
    ClientLink.wifi6g => 'Wi-Fi 6 GHz',
    ClientLink.guest => 'Guest Wi-Fi',
    ClientLink.unknown => 'Connected',
  };
}

class _Wifi extends ConsumerWidget {
  const _Wifi({required this.networks});
  final List<WifiNetwork> networks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PulseSegmentedList(
      animate: false,
      children: [
        for (final n in networks)
          PulseListItem(
            title: n.ssid ?? (n.guest ? 'Guest network' : 'Wi-Fi'),
            subtitle: [
              n.guest ? 'Guest · ${n.bandLabel}' : n.bandLabel,
              if (n.channel != null && n.channel! > 0) 'channel ${n.channel}',
            ].join(' · '),
            leading: PulseIcon(PulseIcons.wifi, size: 22, color: context.colors.onSurfaceVariant),
            onTap: () => _edit(context, ref, n),
            trailing: Switch(
              value: n.enabled ?? false,
              onChanged: n.enabled == null ? null : (v) => _toggle(context, ref, n, v),
            ),
          ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, WifiNetwork n, bool on) async {
    if (!on) {
      final ok = await _confirm(
        context,
        'Turn off ${n.ssid ?? n.bandLabel}?',
        'Devices on this network disconnect. If this phone is on it, Pulse loses the router too; '
            'turn it back on from the router or another network.',
        'Turn off',
      );
      if (ok != true || !context.mounted) return;
    }
    await _apply(
      context,
      ref,
      () => ref.read(routerManageProvider.notifier).setWifi(n, enabled: on),
      on ? 'Turned on' : 'Turned off',
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, WifiNetwork n) async {
    final ssid = TextEditingController(text: n.ssid ?? '');
    final pass = TextEditingController(text: n.password ?? '');
    var hide = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${n.guest ? 'Guest' : 'Wi-Fi'} ${n.bandLabel}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ssid,
                decoration: const InputDecoration(labelText: 'Network name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pass,
                obscureText: hide,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: '8 to 63 characters',
                  suffixIcon: IconButton(
                    tooltip: hide ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => hide = !hide),
                    icon: PulseIcon(hide ? PulseIcons.search : PulseIcons.shield, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Devices on this network have to reconnect with the new name or password.',
                style: context.type.bodySmall!.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final newSsid = ssid.text.trim(), newPass = pass.text;
    ssid.dispose();
    pass.dispose();
    if (ok != true || !context.mounted) return;
    final changeSsid = newSsid.isNotEmpty && newSsid != n.ssid ? newSsid : null;
    final changePass = newPass != (n.password ?? '') ? newPass : null;
    if (changeSsid == null && changePass == null) return;
    if (changePass != null && (changePass.length < 8 || changePass.length > 63)) {
      showPulseToast(context, 'The Wi-Fi password needs 8 to 63 characters', icon: PulseIcons.info);
      return;
    }
    await _apply(
      context,
      ref,
      () => ref.read(routerManageProvider.notifier).setWifi(n, ssid: changeSsid, password: changePass),
      'Wi-Fi updated',
    );
  }
}

class _Forwards extends StatelessWidget {
  const _Forwards({required this.rules});
  final List<RouterForward> rules;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PulseSegmentedList(
      animate: false,
      children: [
        for (final r in rules)
          PulseListItem(
            title: r.name.isEmpty ? '${r.protocol} ${r.externalPort}' : r.name,
            subtitle: '${r.protocol} ${r.externalPort} → ${r.internalIp}:${r.internalPort}${r.enabled ? '' : ' · off'}',
            leading: PulseIcon(PulseIcons.port, size: 22, color: c.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return PulseSegmentedList(
      animate: false,
      children: [
        PulseListItem(
          title: 'Refresh',
          subtitle: 'Read everything from the router again',
          leading: PulseIcon(PulseIcons.refresh, size: 22, color: c.onSurfaceVariant),
          onTap: () => ref.read(routerManageProvider.notifier).refresh(),
        ),
        PulseListItem(
          title: 'Restart router',
          subtitle: 'The internet and Wi-Fi drop for a minute or two',
          leading: PulseIcon(PulseIcons.power, size: 22, color: c.error),
          onTap: () async {
            final ok = await _confirm(
              context,
              'Restart ${profile.name}?',
              'Every device loses the internet and Wi-Fi until the router is back, usually in one to two minutes.',
              'Restart',
            );
            if (ok != true || !context.mounted) return;
            await _apply(context, ref, () => ref.read(routerManageProvider.notifier).reboot(), 'Router is restarting');
          },
        ),
      ],
    );
  }
}

Future<bool?> _confirm(BuildContext context, String title, String body, String action) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(body),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
    ],
  ),
);

Future<void> _apply(BuildContext context, WidgetRef ref, Future<void> Function() run, String done) async {
  try {
    await run();
    if (context.mounted) showPulseToast(context, done, icon: PulseIcons.check);
  } on RouterDriverException catch (e) {
    if (context.mounted) showPulseToast(context, e.message, icon: PulseIcons.info);
  } on Object catch (e) {
    if (context.mounted) showPulseToast(context, 'The router did not accept it: $e', icon: PulseIcons.info);
  }
}
