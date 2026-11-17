import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/session_tool.dart';
import '../data/repositories/history_repository.dart';
import '../services/widgets/home_widgets.dart';
import 'database_provider.dart';
import 'monitor_provider.dart';
import 'ping_provider.dart';
import 'settings_provider.dart';

/// Keeps the home screen widgets' data current while Pulse is open: theme,
/// saved targets, the latest speed results, the public address and the
/// Monitor snapshot. Watched by `WidgetLinks` around the shell. The
/// background monitor publishes Monitor itself after each cycle.
final widgetSyncProvider = Provider<void>((ref) {
  if (!PulseWidgets.supported) return;
  unawaited(PulseWidgets.init());
  final db = ref.watch(databaseProvider);

  ref.listen(settingsProvider, (_, s) => unawaited(PulseWidgets.publishTheme(s)), fireImmediately: true);

  final subs = <StreamSubscription<Object?>>[];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });

  subs.add(
    ref.read(savedTargetsRepositoryProvider).watch().listen((list) {
      unawaited(PulseWidgets.publishTargets([for (final t in list) WidgetTarget(t.host, t.name)]));
    }),
  );

  // Latest speed runs, with the newest one's jitter from its payload.
  final speedQ = db.select(db.sessions)
    ..where((s) => s.tool.equals(SessionTool.speed.name))
    ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
    ..limit(8);
  subs.add(
    speedQ.watch().listen((rows) {
      if (rows.isEmpty) return;
      double? d(Object? v) => v is num ? v.toDouble() : null;
      final runs = [
        for (final r in rows)
          (
            at: r.startedAt,
            down: d(HistoryRepository.payloadOf(r)['down']),
            up: d(HistoryRepository.payloadOf(r)['up']),
            ping: d(HistoryRepository.payloadOf(r)['ping']),
            server: r.target,
          ),
      ];
      unawaited(PulseWidgets.publishSpeed(runs, jitter: d(HistoryRepository.payloadOf(rows.first)['jitter'])));
    }),
  );

  // Monitor: any new check, target or incident change (in-app runner).
  final trigger = db
      .customSelect(
        'SELECT (SELECT MAX(id) FROM monitor_checks) AS c, (SELECT COUNT(*) FROM monitor_targets) AS t, '
        '(SELECT COUNT(*) FROM incidents WHERE ended_at IS NULL) AS i',
        readsFrom: {db.monitorChecks, db.monitorTargets, db.incidents},
      )
      .watchSingle();
  subs.add(
    trigger.listen((_) {
      unawaited(PulseWidgets.publishMonitor(db, live: ref.read(monitorRunnerProvider).live));
    }),
  );
  ref.listen(monitorRunnerProvider.select((s) => s.live), (_, live) {
    unawaited(PulseWidgets.publishMonitor(db, live: live));
  });
});
