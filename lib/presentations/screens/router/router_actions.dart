import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_manage_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/net/router/drivers/router_driver.dart';
import '../../../services/net/router/verification.dart';

/// Runs one router change the safe way:
///
/// 1. Verified actions run after the usual confirmation (if any). Unverified
///    ones say "Not confirmed for your router yet" first.
/// 2. [run] makes the change and reads the setting back: true = the router
///    reports the new value, false = it doesn't, null = couldn't read back.
/// 3. A failed read-back is reported as "didn't work" by itself; otherwise
///    Pulse asks "Did it work?" until this router model is verified.
Future<void> runRouterAction(
  BuildContext context,
  WidgetRef ref, {
  required String action,
  required Future<bool?> Function() run,
  required String done,
  String? confirmTitle,
  String? confirmBody,
  String confirmLabel = 'Continue',
  String working = 'Talking to the router…',
}) async {
  final caps = ref.read(routerCapabilitiesProvider).value;
  final trust = caps?.trust(action) ?? ActionTrust.untested;
  if (confirmBody != null || trust != ActionTrust.verified) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirmTitle ?? RouterActions.label(action)),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (confirmBody != null) Text(confirmBody),
            if (trust != ActionTrust.verified) ...[
              if (confirmBody != null) const SizedBox(height: 14),
              _UntestedNote(caps: caps),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(trust == ActionTrust.verified ? confirmLabel : 'Try it'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }

  bool? result;
  Object? error;
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(canPop: false, child: _Working(text: working)),
    ),
  );
  try {
    result = await run();
  } on Object catch (e) {
    error = e;
  }
  nav.pop();
  if (!context.mounted) return;

  // With "Share router results" off, Pulse neither asks nor sends.
  final id = ref.read(settingsProvider).routerReports ? caps?.identity : null;
  final verify = ref.read(routerVerificationProvider);
  Future<void> report(bool worked) async {
    if (id == null) return;
    await verify.report(id, action, worked: worked);
    ref.invalidate(routerCapabilitiesProvider);
  }

  if (error != null) {
    final msg = error is RouterDriverException ? error.message : 'The router did not accept it: $error';
    showPulseToast(context, msg, icon: PulseIcons.info);
    // The router answered but refused: that's a real "doesn't work".
    if (error is RouterDriverException && error.kind == RouterErrorKind.unexpected) await report(false);
    return;
  }
  if (result == false) {
    showPulseToast(context, "The router didn't keep the change", icon: PulseIcons.info);
    await report(false);
    return;
  }
  showPulseToast(
    context,
    result == true ? done : '$done. Pulse couldn\'t read it back, so check it yourself.',
    icon: PulseIcons.check,
  );
  if (id != null && (caps?.asks(action) ?? true)) {
    final worked = await askDidItWork(context, action: action, identity: id);
    if (worked != null) await report(worked);
  }
}

class _UntestedNote extends StatelessWidget {
  const _UntestedNote({required this.caps});
  final RouterCapabilities? caps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final id = caps?.identity;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: c.tertiaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PulseIcon(PulseIcons.info, size: 20, color: c.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not confirmed for your router yet',
                  style: context.type.titleSmall!.copyWith(color: c.onTertiaryContainer),
                ),
                const SizedBox(height: 4),
                Text(
                  id == null
                      ? 'Pulse checks the router afterwards and tells you if the change did not stick.'
                      : 'Nobody has confirmed this on ${id.model} (firmware ${id.firmware}) yet. Pulse checks the '
                            'router afterwards and asks whether it worked; your answer helps everyone with this router.',
                  style: context.type.bodySmall!.copyWith(color: c.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Row(
      children: [
        const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: 18),
        Expanded(child: Text(text, style: context.type.bodyLarge)),
      ],
    ),
  );
}

/// "Did it work?" — true / false, or null when the person isn't sure.
Future<bool?> askDidItWork(BuildContext context, {required String action, required RouterIdentity identity}) =>
    showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: PulseShapeBadge(
                    shape: PulseShape.cookie7,
                    tone: PulseTone.lime,
                    icon: PulseIcons.help,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Did it work?', textAlign: TextAlign.center, style: context.type.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '${RouterActions.label(action)} · ${identity.model}\n\nThe router reports the change. Did it '
                  'really happen? Only the router model, firmware and your answer are shared, to help others '
                  'with this router.',
                  textAlign: TextAlign.center,
                  style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                PulseButton(
                  label: 'Yes, it worked',
                  icon: PulseIcons.check,
                  style: PulseButtonStyle.pink,
                  onPressed: () => Navigator.pop(context, true),
                ),
                const SizedBox(height: 8),
                PulseButton(
                  label: "No, it didn't",
                  icon: PulseIcons.x,
                  style: PulseButtonStyle.tonal,
                  onPressed: () => Navigator.pop(context, false),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not sure')),
              ],
            ),
          ),
        );
      },
    );

/// A small "Try it" / "Verified" marker for an action.
class RouterTrustPill extends ConsumerWidget {
  const RouterTrustPill(this.action, {super.key});
  final String action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(routerCapabilitiesProvider).value;
    final t = caps?.trust(action) ?? ActionTrust.untested;
    if (t == ActionTrust.verified) return const SizedBox.shrink();
    final mine = caps?.mine[action];
    return Tooltip(
      // A tap explains it (it's a label, not a button).
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      message: mine == true
          ? 'Worked for you, but not confirmed by enough people yet.'
          : 'Not confirmed for this router model yet. Make the change below; Pulse checks the router afterwards '
                'and asks whether it worked.',
      child: PulsePill(mine == true ? 'Worked for you' : 'Try it', tone: PulsePillTone.outline),
    );
  }
}

/// Restarts the router and watches it go away and come back. True when it
/// dropped and returned, false when it never went away, null when it hadn't
/// come back after four minutes.
Future<bool?> restartAndWait(
  Future<void> Function() reboot,
  String host,
  void Function(String) status, {
  Duration poll = const Duration(seconds: 3),
}) async {
  Future<bool> up() async {
    for (final port in const [443, 80]) {
      try {
        final s = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
        s.destroy();
        return true;
      } on Object {
        // try the next port
      }
    }
    return false;
  }

  await reboot();
  status('Waiting for the router to go down…');
  final downBy = DateTime.now().add(const Duration(seconds: 90));
  var dropped = false;
  while (DateTime.now().isBefore(downBy)) {
    await Future<void>.delayed(poll);
    if (!await up()) {
      dropped = true;
      break;
    }
  }
  if (!dropped) return false;
  status('Restarting… this usually takes one to two minutes');
  final backBy = DateTime.now().add(const Duration(minutes: 4));
  while (DateTime.now().isBefore(backBy)) {
    await Future<void>.delayed(poll);
    if (await up()) {
      // The web server answers a little before the router is ready.
      await Future<void>.delayed(const Duration(seconds: 5));
      return true;
    }
  }
  return null;
}

/// Restart with the full flow: confirm, live status while it restarts, the
/// result read from the router's own behaviour, then a fresh sign-in.
Future<void> restartRouter(BuildContext context, WidgetRef ref, {required String name, required String host}) async {
  final caps = ref.read(routerCapabilitiesProvider).value;
  final trust = caps?.trust(RouterActions.reboot) ?? ActionTrust.untested;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Restart $name?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Every device loses the internet and Wi-Fi until the router is back, usually in one to two minutes.',
          ),
          if (trust != ActionTrust.verified) ...[const SizedBox(height: 14), _UntestedNote(caps: caps)],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restart')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final text = ValueNotifier('Asking the router to restart…');
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: ValueListenableBuilder(
          valueListenable: text,
          builder: (_, v, _) => _Working(text: v),
        ),
      ),
    ),
  );
  bool? result;
  Object? error;
  try {
    result = await restartAndWait(ref.read(routerManageProvider.notifier).reboot, host, (s) => text.value = s);
  } on Object catch (e) {
    error = e;
  }
  nav.pop();
  text.dispose();
  final id = ref.read(settingsProvider).routerReports ? caps?.identity : null;
  if (id != null && error == null && result != null) {
    // Objective either way: it went down and came back, or never went down.
    await ref.read(routerVerificationProvider).report(id, RouterActions.reboot, worked: result);
    ref.invalidate(routerCapabilitiesProvider);
  }
  ref.invalidate(routerManageProvider);
  if (!context.mounted) return;
  showPulseToast(
    context,
    error != null
        ? (error is RouterDriverException ? error.message : 'The router did not accept it: $error')
        : switch (result) {
            true => '$name restarted and is back',
            false => "The router didn't restart",
            null => "$name hasn't come back yet. Give it a few more minutes.",
          },
    icon: result == true ? PulseIcons.check : PulseIcons.info,
  );
}

/// A Wi-Fi join code (`WIFI:T:WPA;S:…;P:…;;`) drawn from the qr package.
class WifiQr extends StatelessWidget {
  const WifiQr({super.key, required this.ssid, this.password, this.hidden = false, this.size = 220});
  final String ssid;
  final String? password;
  final bool hidden;
  final double size;

  static String _esc(String v) => v.replaceAllMapped(RegExp(r'([\\;,":])'), (m) => '\\${m[1]}');

  String get payload {
    final open = password == null || password!.isEmpty;
    return 'WIFI:T:${open ? 'nopass' : 'WPA'};S:${_esc(ssid)};${open ? '' : 'P:${_esc(password!)};'}'
        '${hidden ? 'H:true;' : ''};';
  }

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode(payload: QrPayload.fromString(payload)));
    return Semantics(
      label: 'QR code to join $ssid',
      child: Container(
        padding: const EdgeInsets.all(14),
        // Scanners need dark-on-light whatever the theme.
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: CustomPaint(size: Size.square(size), painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (image.isDark(r, col)) {
          canvas.drawRect(Rect.fromLTWH(col * cell, r * cell, cell + .5, cell + .5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
