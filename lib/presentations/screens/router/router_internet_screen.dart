import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../navigation/destinations.dart';
import 'router_actions.dart';
import 'router_wifi_screen.dart' show routerPageFallback;

/// The router's internet connection: what it has now, and the connection
/// types it offers (only those) with each type's settings.
class RouterInternetScreen extends ConsumerWidget {
  const RouterInternetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(routerManageProvider);
    final w = m.value?.wan;
    return PulsePage(
      title: 'Internet connection',
      backTo: Routes.router,
      actions: [
        PulseIconButton(
          icon: PulseIcons.refresh,
          tooltip: 'Read again',
          onPressed: () => ref.read(routerManageProvider.notifier).refresh(),
        ),
      ],
      children: w == null
          ? [
              if (m.value != null)
                const PulseEmptyState(
                  title: 'Not available here',
                  message: "This router didn't share its internet settings. Full router settings has them.",
                  icon: PulseIcons.globe,
                  shape: PulseShape.cookie9,
                )
              else
                routerPageFallback(context, ref, m),
            ]
          : [_Status(w: w), _Editor(key: ValueKey(w.current), w: w)],
    );
  }
}

class _Status extends StatefulWidget {
  const _Status({required this.w});
  final WanConfig w;

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final c = context.colors;
    String mask(String ip) {
      final p = ip.split('.');
      return p.length == 4 ? '${p[0]}.••.••.${p[3]}' : '••••';
    }

    Widget row(String k, String v, {Widget? trailing}) => SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(k, style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(v, style: context.type.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ?trailing,
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PulseShapeBadge(shape: PulseShape.cookie9, tone: PulseTone.lime, icon: PulseIcons.globe, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.current?.label ?? 'Unknown type', style: context.type.titleLarge),
                    const SizedBox(height: 4),
                    if (w.connected != null)
                      PulsePill(
                        w.connected! ? 'Connected' : 'Not connected',
                        tone: w.connected! ? PulsePillTone.lime : PulsePillTone.error,
                        dot: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (w.ip != null)
            row(
              'IP address',
              _show ? w.ip! : mask(w.ip!),
              trailing: PulseIconButton(
                icon: _show ? PulseIcons.shield : PulseIcons.search,
                tooltip: _show ? 'Hide addresses' : 'Show addresses',
                visualSize: 32,
                iconSize: 16,
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          if (w.gateway != null) row('Gateway', _show ? w.gateway! : mask(w.gateway!)),
          if (w.dns.isNotEmpty) row('DNS', w.dns.join(', ')),
        ],
      ),
    );
  }
}

/// The type picker and the chosen type's settings.
class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.w});
  final WanConfig w;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late WanType? _type = widget.w.current ?? widget.w.available.firstOrNull;
  final _f = <String, TextEditingController>{};
  bool _manualDns = false;
  bool _secondaryStatic = false;
  bool _hidePass = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String k) => _f.putIfAbsent(k, TextEditingController.new);
  String _t(String k) => _c(k).text.trim();

  /// Fills the fields with the router's saved values for the chosen type.
  void _load() {
    final s = _type == null ? null : widget.w.settings[_type];
    _c('ip').text = s?.ip ?? '';
    _c('netmask').text = s?.netmask ?? (_type == WanType.static ? '255.255.255.0' : '');
    _c('gateway').text = s?.gateway ?? '';
    _c('dns1').text = s?.dns1 ?? '';
    _c('dns2').text = s?.dns2 ?? '';
    _c('mtu').text = s?.mtu?.toString() ?? '';
    _c('hostname').text = s?.hostname ?? '';
    _c('username').text = s?.username ?? '';
    _c('password').text = s?.password ?? '';
    _c('server').text = s?.server ?? '';
    _manualDns = s?.manualDns ?? false;
    _secondaryStatic = s?.secondaryStatic ?? false;
  }

  static final _ipv4 = RegExp(r'^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$');

  static bool _mask(String v) {
    if (!_ipv4.hasMatch(v)) return false;
    final bits = v.split('.').map(int.parse).fold<int>(0, (a, b) => (a << 8) | b);
    final inv = ~bits & 0xffffffff;
    return bits != 0 && (inv & (inv + 1)) == 0;
  }

  String? _ipErr(String k, {bool optional = false}) {
    final v = _t(k);
    if (v.isEmpty) return optional ? null : 'Required';
    return _ipv4.hasMatch(v) ? null : 'Not an IPv4 address';
  }

  /// Field errors for the current type ({} when everything is valid).
  Map<String, String> get _errors {
    final t = _type;
    if (t == null) return const {};
    final e = <String, String>{};
    void ip(String k, {bool optional = false}) {
      final m = _ipErr(k, optional: optional);
      if (m != null) e[k] = m;
    }

    final mtu = _t('mtu');
    if (mtu.isNotEmpty) {
      final v = int.tryParse(mtu);
      if (v == null || v < 576 || v > 1500) e['mtu'] = '576 to 1500';
    }
    final staticAddr = t == WanType.static || (t.usesServer && _secondaryStatic);
    if (staticAddr) {
      ip('ip');
      if (!_mask(_t('netmask'))) e['netmask'] = 'Not a subnet mask';
      ip('gateway', optional: t != WanType.static);
    }
    if (t == WanType.static || ((t == WanType.dhcp || t == WanType.pppoe) && _manualDns) || staticAddr) {
      ip('dns1', optional: t != WanType.static && !_manualDns);
      ip('dns2', optional: true);
    }
    if (t.usesLogin) {
      if (_t('username').isEmpty) e['username'] = 'Required';
      if (_c('password').text.isEmpty) e['password'] = 'Required';
    }
    if (t.usesServer && _t('server').isEmpty) e['server'] = 'Required';
    return e;
  }

  WanSettings _settings() {
    final t = _type!;
    String? v(String k) => _t(k).isEmpty ? null : _t(k);
    final staticAddr = t == WanType.static || (t.usesServer && _secondaryStatic);
    final dns = t == WanType.static || staticAddr || _manualDns;
    return WanSettings(
      type: t,
      ip: staticAddr ? v('ip') : null,
      netmask: staticAddr ? v('netmask') : null,
      gateway: staticAddr ? v('gateway') : null,
      dns1: dns ? v('dns1') : null,
      dns2: dns ? (v('dns2') ?? '') : null,
      manualDns: t == WanType.dhcp || t == WanType.pppoe ? _manualDns : null,
      mtu: int.tryParse(_t('mtu')),
      hostname: t == WanType.dhcp ? v('hostname') : null,
      username: t.usesLogin ? v('username') : null,
      password: t.usesLogin ? _c('password').text : null,
      server: t.usesServer ? v('server') : null,
      secondaryStatic: t.usesServer ? _secondaryStatic : null,
    );
  }

  Future<void> _save() async {
    final t = _type!;
    final switching = t != widget.w.current;
    final action = switching ? RouterActions.internetType : RouterActions.internetEdit;
    await runRouterAction(
      context,
      ref,
      action: action,
      confirmTitle: switching ? 'Switch to ${t.label}?' : 'Save ${t.label} settings?',
      confirmBody:
          'The internet drops while the router reconnects, usually for a few seconds. If these settings are '
          "wrong for your provider, the internet stays down until they're fixed; your Wi-Fi and this page keep "
          'working, so you can switch back here or in Full router settings.',
      confirmLabel: switching ? 'Switch' : 'Save',
      working: 'Saving and reconnecting…',
      done: switching ? 'Switched to ${t.label}' : '${t.label} settings saved',
      run: () => ref.read(routerManageProvider.notifier).setWan(_settings()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final c = context.colors;
    final caps = ref.watch(routerCapabilitiesProvider).value;
    final actions = ref.watch(routerManageProvider).value?.actions ?? const <String>{};
    final t = _type;
    final switching = t != null && t != w.current;
    final action = switching ? RouterActions.internetType : RouterActions.internetEdit;
    final canSave = actions.contains(action) && (caps?.offers(action) ?? true);
    final errors = _errors;

    Widget field(String k, String label, {String? hint, TextInputType? kb, bool password = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c(k),
        keyboardType: kb ?? (password ? TextInputType.visiblePassword : TextInputType.text),
        obscureText: password && _hidePass,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          errorText: errors[k],
          suffixIcon: password
              ? IconButton(
                  tooltip: _hidePass ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hidePass = !_hidePass),
                  icon: PulseIcon(_hidePass ? PulseIcons.search : PulseIcons.shield, size: 20),
                )
              : null,
        ),
      ),
    );

    const ipKb = TextInputType.numberWithOptions(decimal: true);
    final staticAddr = t == WanType.static || (t != null && t.usesServer && _secondaryStatic);

    void pick(WanType type) => setState(() {
      _type = type;
      _load();
    });

    // A tight list on phones and in the side column; cards on tablets.
    Widget typeList() => PulseSegmentedList(
      animate: false,
      children: [
        for (final type in w.available)
          PulseListItem(
            title: type.label,
            subtitle: type.help,
            subtitleMaxLines: 2,
            selected: type == t,
            onTap: () => pick(type),
            trailing: type == w.current ? const PulsePill('Active', tone: PulsePillTone.lime) : null,
          ),
      ],
    );

    Widget typeGrid(double maxWidth) {
      final cols = maxWidth >= 720 ? 3 : 2;
      final width = (maxWidth - (cols - 1) * 8) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in w.available)
            SizedBox(
              width: width,
              child: _TypeCard(type: type, selected: type == t, active: type == w.current, onTap: () => pick(type)),
            ),
        ],
      );
    }

    final settings = <Widget>[
      if (t != null) ...[
        PulseSectionLabel('${t.label} settings', trailing: canSave ? RouterTrustPill(action) : null),
        PulseCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (t.usesLogin) ...[
                field('username', 'Username', hint: 'From your internet provider'),
                field('password', 'Password', password: true),
              ],
              if (t.usesServer) ...[
                field('server', 'Server address', hint: 'Name or IP from your provider', kb: TextInputType.url),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Static secondary connection'),
                  subtitle: const Text('Only if your provider gave you a fixed address for it'),
                  value: _secondaryStatic,
                  onChanged: (v) => setState(() => _secondaryStatic = v),
                ),
              ],
              if (staticAddr) ...[
                field('ip', 'IP address', kb: ipKb),
                field('netmask', 'Subnet mask', kb: ipKb),
                field('gateway', 'Default gateway', kb: ipKb),
              ],
              if (t == WanType.dhcp)
                field('hostname', 'Host name', hint: 'How the router names itself to the provider'),
              if (t == WanType.dhcp || t == WanType.pppoe)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use my own DNS servers'),
                  subtitle: const Text('Off: use the ones your provider sends'),
                  value: _manualDns,
                  onChanged: (v) => setState(() => _manualDns = v),
                ),
              if (t == WanType.static || _manualDns || staticAddr) ...[
                field('dns1', 'Primary DNS', kb: ipKb),
                field('dns2', 'Secondary DNS (optional)', kb: ipKb),
              ],
              field(
                'mtu',
                'MTU (bytes)',
                hint: 'Leave as is unless your provider says otherwise',
                kb: TextInputType.number,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (canSave)
          PulseButton(
            label: switching ? 'Switch to ${t.label}' : 'Save settings',
            icon: PulseIcons.check,
            style: PulseButtonStyle.pink,
            onPressed: errors.isEmpty ? _save : null,
          )
        else
          Text(
            'Changing this is not available for this router from Pulse; use Full router settings.',
            style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
          ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Your provider decides which type is right. Pulse only lists the types this router offers, '
            'and checks the router afterwards.',
            style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
          ),
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const PulseSectionLabel('Connection type'), typeList()],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: settings),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PulseSectionLabel('Connection type'),
            if (box.maxWidth >= 560) typeGrid(box.maxWidth) else typeList(),
            ...settings,
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.selected, required this.active, required this.onTap});
  final WanType type;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onSecondaryContainer : c.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      label: '${type.label}${active ? ', active' : ''}. ${type.help}',
      excludeSemantics: true,
      child: PulseCard(
        color: selected ? c.secondaryContainer : c.surfaceContainer,
        radius: selected ? 28 : 20,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        onTap: onTap,
        child: SizedBox(
          height: 78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(type.label, style: context.type.titleMedium!.copyWith(color: fg)),
                  ),
                  if (active) const PulsePill('Active', tone: PulsePillTone.lime),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                type.help,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodySmall!.copyWith(color: selected ? fg : c.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
