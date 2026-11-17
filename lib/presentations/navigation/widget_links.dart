import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers/ping_provider.dart';
import '../../providers/speed_provider.dart';
import '../../providers/widgets_provider.dart';
import '../../services/widgets/home_widgets.dart';
import '../screens/ping/ping_configure.dart' show gatewayProvider;
import 'app_router.dart';
import 'destinations.dart';

/// Around the shell: keeps widget data in sync ([widgetSyncProvider]) and
/// opens what a widget tap asked for — Ping detail for a host, the Speed test
/// (optionally starting it), Monitor or any tool.
class WidgetLinks extends ConsumerStatefulWidget {
  const WidgetLinks({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<WidgetLinks> createState() => _WidgetLinksState();
}

class _WidgetLinksState extends ConsumerState<WidgetLinks> {
  /// The launch link is handled once per process, not on every shell rebuild.
  static bool _launchHandled = false;
  StreamSubscription<Uri?>? _clicks;

  @override
  void initState() {
    super.initState();
    if (!PulseWidgets.supported) return;
    _clicks = HomeWidget.widgetClicked.listen(_open, onError: (Object _) {});
    if (!_launchHandled) {
      _launchHandled = true;
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_open, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    _clicks?.cancel();
    super.dispose();
  }

  Future<void> _open(Uri? uri) async {
    final link = WidgetLink.parse(uri);
    if (link == null || !mounted) return;
    final router = ref.read(routerProvider);
    switch (link) {
      case OpenLink(:final route):
        router.go(route);
      case SpeedLink(:final run):
        router.go(Routes.speed);
        if (run && !ref.read(speedProvider).running) {
          // Let the screen appear first so the run is visible from its start.
          await Future<void>.delayed(const Duration(milliseconds: 450));
          if (mounted) unawaited(ref.read(speedProvider.notifier).start());
        }
      case PingLink(:final host, :final name):
        final target = host == kGatewayHost
            ? await ref.read(gatewayProvider.future).catchError((Object _) => null)
            : host;
        if (target == null || !mounted) {
          router.go(Routes.ping);
          return;
        }
        final board = ref.read(pingBoardProvider.notifier);
        final existing = ref
            .read(pingBoardProvider)
            .sessions
            .where((s) => s.host.toLowerCase() == target.toLowerCase());
        final id = existing.isNotEmpty
            ? existing.first.id
            : await board.start(target, name: host == kGatewayHost ? (name ?? 'Router') : name);
        if (!mounted) return;
        if (id == null) {
          router.go(Routes.ping);
          return;
        }
        board.focus(id);
        router.go('${Routes.pingDetail}?id=${Uri.encodeQueryComponent(id)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(widgetSyncProvider);
    return widget.child;
  }
}
