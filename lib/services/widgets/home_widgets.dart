import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/app_database.dart';
import '../../data/models/app_settings.dart';

/// Pulse's home screen widgets (Android: Jetpack Glance in
/// `android/app/src/main/kotlin/com/example/pulse/widgets/`; iOS: WidgetKit in
/// `ios/PulseWidgets/`, see `docs/IOS_WIDGETS.md`).
///
/// The app publishes what the widgets show as JSON strings under shared keys
/// (home_widget's preferences file on Android, the App Group's UserDefaults on
/// iOS). Ping widgets measure on their own (native ping, no Flutter), so the
/// app only shares speed results, monitor status, the public address, saved
/// targets and the theme. Keys and shapes must match WidgetStore.kt and
/// PulseShared.swift.
enum WidgetKind {
  ping('PingWidgetReceiver', 'PulsePingWidget', 'Ping', 'Live latency for one host, with a reply chart and stats.'),
  multiping(
    'MultiPingWidgetReceiver',
    'PulseMultiPingWidget',
    'Multi-host ping',
    'Router, DNS and servers side by side.',
  ),
  speed('SpeedWidgetReceiver', 'PulseSpeedWidget', 'Speed test', 'Your latest result and a button to run a new test.'),
  monitor(
    'MonitorWidgetReceiver',
    'PulseMonitorWidget',
    'Monitor',
    'What is up or down, uptime and the last 24 hours.',
  ),
  actions('ActionsWidgetReceiver', 'PulseActionsWidget', 'Quick actions', 'Shortcuts into the tools you use most.'),
  network('NetworkWidgetReceiver', 'PulseNetworkWidget', 'Network', 'Wi-Fi, addresses, router latency and DNS.');

  const WidgetKind(this.androidClass, this.iOSKind, this.label, this.description);
  final String androidClass;
  final String iOSKind;
  final String label;
  final String description;

  String get qualifiedAndroidName => 'com.example.pulse.widgets.$androidClass';

  static WidgetKind? byName(String? name) => WidgetKind.values.where((k) => k.name == name).firstOrNull;

  /// [cls] may be short (`.widgets.PingWidgetReceiver`) or fully qualified.
  static WidgetKind? byAndroidClass(String? cls) =>
      WidgetKind.values.where((k) => cls != null && cls.split('.').last == k.androidClass).firstOrNull;

  /// What its settings screen changes (Settings › Home screen widgets).
  String get settingsHint => switch (this) {
    ping || multiping => 'Hosts, refresh and style',
    network => 'Addresses, refresh and style',
    actions => 'Shortcuts and style',
    speed || monitor => 'Style',
  };

  /// Kinds whose settings include hosts and a refresh interval.
  bool get pings => this == ping || this == multiping || this == network;
}

/// Tools the Quick actions widget can open (ids match ActionsWidget.kt / Swift).
enum WidgetTool {
  ping('Ping'),
  speed('Speed test'),
  trace('Traceroute'),
  lan('LAN scan'),
  geo('Geo IP'),
  ports('Port scan'),
  loss('Packet loss'),
  monitor('Monitor'),
  network('Network'),
  history('History');

  const WidgetTool(this.label);
  final String label;

  static const defaults = [ping, speed, trace, lan, geo, ports, loss, monitor];
}

/// The router: widgets resolve it to the current default gateway.
const kGatewayHost = 'gateway';

@immutable
class WidgetTarget {
  const WidgetTarget(this.host, [this.name]);
  final String host;
  final String? name;

  String get title => (name?.trim().isNotEmpty ?? false) ? name!.trim() : (host == kGatewayHost ? 'Router' : host);

  Map<String, Object?> toJson() => {'host': host, 'name': name};

  static WidgetTarget fromJson(Map<String, dynamic> j) => WidgetTarget('${j['host'] ?? ''}', j['name'] as String?);

  @override
  bool operator ==(Object other) => other is WidgetTarget && other.host == host && other.name == name;

  @override
  int get hashCode => Object.hash(host, name);
}

/// One placed widget's settings (Android; iOS keeps them in the widget's own
/// App Intent configuration).
@immutable
class WidgetSettings {
  const WidgetSettings({
    this.targets = const [],
    this.intervalMin = 30,
    this.tools = WidgetTool.defaults,
    this.showPublicIp = false,
    this.showLocalIp = true,
    this.colors = '',
    this.background = 'solid',
    this.probes = 4,
    this.showChart = true,
  });

  final List<WidgetTarget> targets;

  /// Background refresh in minutes; 0 = only when tapped.
  final int intervalMin;
  final List<WidgetTool> tools;
  final bool showPublicIp;
  final bool showLocalIp;

  /// '' (follow Settings › Appearance), 'app' (Pulse colours and accent) or
  /// 'wallpaper' (Material You).
  final String colors;

  /// 'solid', 'translucent' or 'clear'.
  final String background;
  final int probes;
  final bool showChart;

  static WidgetSettings defaultsFor(WidgetKind kind) => switch (kind) {
    WidgetKind.ping => const WidgetSettings(targets: [WidgetTarget('1.1.1.1', 'Cloudflare')]),
    WidgetKind.multiping => const WidgetSettings(
      targets: [
        WidgetTarget(kGatewayHost, 'Router'),
        WidgetTarget('1.1.1.1', 'Cloudflare'),
        WidgetTarget('8.8.8.8', 'Google'),
        WidgetTarget('9.9.9.9', 'Quad9'),
      ],
    ),
    _ => const WidgetSettings(),
  };

  WidgetSettings copyWith({
    List<WidgetTarget>? targets,
    int? intervalMin,
    List<WidgetTool>? tools,
    bool? showPublicIp,
    bool? showLocalIp,
    String? colors,
    String? background,
    int? probes,
    bool? showChart,
  }) => WidgetSettings(
    targets: targets ?? this.targets,
    intervalMin: intervalMin ?? this.intervalMin,
    tools: tools ?? this.tools,
    showPublicIp: showPublicIp ?? this.showPublicIp,
    showLocalIp: showLocalIp ?? this.showLocalIp,
    colors: colors ?? this.colors,
    background: background ?? this.background,
    probes: probes ?? this.probes,
    showChart: showChart ?? this.showChart,
  );

  Map<String, Object?> toJson() => {
    'targets': [for (final t in targets) t.toJson()],
    'interval': intervalMin,
    'tools': [for (final t in tools) t.name],
    'publicIp': showPublicIp,
    'localIp': showLocalIp,
    'colors': colors,
    'background': background,
    'probes': probes,
    'chart': showChart,
  };

  static WidgetSettings fromJson(Map<String, dynamic> j, WidgetKind kind) {
    final d = defaultsFor(kind);
    final targets = (j['targets'] as List?)
        ?.whereType<Map>()
        .map((e) => WidgetTarget.fromJson(e.cast<String, dynamic>()))
        .where((t) => t.host.isNotEmpty)
        .toList();
    final tools = (j['tools'] as List?)
        ?.map((e) => WidgetTool.values.where((t) => t.name == e).firstOrNull)
        .whereType<WidgetTool>()
        .toList();
    return WidgetSettings(
      targets: (targets == null || targets.isEmpty) ? d.targets : targets,
      intervalMin: (j['interval'] as num?)?.toInt() ?? d.intervalMin,
      tools: (tools == null || tools.isEmpty) ? d.tools : tools,
      showPublicIp: j['publicIp'] as bool? ?? d.showPublicIp,
      showLocalIp: j['localIp'] as bool? ?? d.showLocalIp,
      colors: j['colors'] as String? ?? d.colors,
      background: j['background'] as String? ?? d.background,
      probes: (j['probes'] as num?)?.toInt() ?? d.probes,
      showChart: j['chart'] as bool? ?? d.showChart,
    );
  }
}

/// One widget on the home screen.
@immutable
class PlacedWidget {
  const PlacedWidget({required this.kind, this.androidId, this.iOSFamily});
  final WidgetKind kind;
  final int? androidId;
  final String? iOSFamily;
}

/// What a widget tap asks the app to do.
sealed class WidgetLink {
  const WidgetLink();

  /// `pulse://ping?host=…&name=…`, `pulse://speed?run=1`, `pulse://monitor`,
  /// `pulse://open?to=/traceroute`. iOS links also carry `homeWidget` (the
  /// marker home_widget looks for).
  static WidgetLink? parse(Uri? uri) {
    if (uri == null) return null;
    final what = uri.host.isNotEmpty ? uri.host : uri.pathSegments.firstOrNull ?? '';
    final q = uri.queryParameters;
    return switch (what) {
      'ping' when (q['host'] ?? '').isNotEmpty => PingLink(q['host']!, q['name']),
      'speed' => SpeedLink(run: q['run'] == '1'),
      'monitor' => const OpenLink('/monitor'),
      'open' when (q['to'] ?? '').startsWith('/') => OpenLink(q['to']!),
      _ => null,
    };
  }
}

class PingLink extends WidgetLink {
  const PingLink(this.host, this.name);
  final String host;
  final String? name;
}

class SpeedLink extends WidgetLink {
  const SpeedLink({required this.run});
  final bool run;
}

class OpenLink extends WidgetLink {
  const OpenLink(this.route);
  final String route;
}

class PulseWidgets {
  PulseWidgets._();

  /// iOS App Group shared by Runner and the PulseWidgets extension.
  static const appGroup = 'group.com.pranta.pulse';
  static const _channel = MethodChannel('pulse/widgets');

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const kTheme = 'w.theme';
  static const kTargets = 'w.targets';
  static const kSpeed = 'w.speed';
  static const kMonitor = 'w.monitor';
  static const kPublic = 'w.net.public';
  static const kGateway = 'w.gateway';
  static String kConfig(int id) => 'w.cfg.$id';

  static bool _ready = false;
  static final _last = <String, String>{};

  static Future<void> init() async {
    if (!supported || _ready) return;
    _ready = true;
    if (Platform.isIOS) await HomeWidget.setAppGroupId(appGroup);
  }

  /// Saves [value] as JSON under [key] unless it is unchanged, and returns
  /// whether anything was written.
  static Future<bool> _save(String key, Object? value) async {
    if (!supported) return false;
    await init();
    final json = jsonEncode(value);
    if (_last[key] == json) return false;
    try {
      await HomeWidget.saveWidgetData<String>(key, json);
      _last[key] = json;
      return true;
    } on Object catch (e) {
      // No widget host (e.g. a test) — widgets are a nicety.
      debugPrint('Widgets: save $key failed: $e');
      return false;
    }
  }

  static Future<void> update(Iterable<WidgetKind> kinds) async {
    if (!supported) return;
    for (final k in kinds) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: k.qualifiedAndroidName, iOSName: k.iOSKind);
      } on Object catch (e) {
        debugPrint('Widgets: update ${k.name} failed: $e');
      }
    }
  }

  /// Every widget kind: colours apply to all of them.
  static Future<void> publishTheme(AppSettings s) async {
    final changed = await _save(kTheme, {
      'accent': s.accent,
      'dynamic': s.dynamicColor,
      'mode': switch (s.themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    });
    if (changed) await update(WidgetKind.values);
  }

  /// Saved ping targets: host choices for the widgets' settings (iOS shows
  /// them in the widget's Edit sheet).
  static Future<void> publishTargets(List<WidgetTarget> targets) =>
      _save(kTargets, [for (final t in targets) t.toJson()]);

  /// The newest speed results first (as speedHistoryProvider gives them).
  static Future<void> publishSpeed(
    List<({DateTime at, double? down, double? up, double? ping, String server})> runs, {
    double? jitter,
  }) async {
    if (runs.isEmpty) return;
    final r = runs.first;
    final changed = await _save(kSpeed, {
      'at': r.at.millisecondsSinceEpoch,
      'down': r.down,
      'up': r.up,
      'ping': r.ping,
      'jitter': jitter,
      'server': r.server,
      'history': [
        for (final x in runs.take(8)) {'at': x.at.millisecondsSinceEpoch, 'down': x.down, 'up': x.up, 'ping': x.ping},
      ],
    });
    if (changed) await update(const [WidgetKind.speed]);
  }

  /// The public address Pulse last looked up (null when lookups are off).
  static Future<void> publishNetwork({
    String? publicIp,
    String? isp,
    String? city,
    String? country,
    String? gateway,
  }) async {
    final a = await _save(kPublic, {'ip': publicIp, 'isp': isp, 'city': city, 'country': country});
    final b = gateway == null ? false : await _save(kGateway, gateway);
    if (a || b) await update(const [WidgetKind.network]);
  }

  /// Rebuilds the Monitor snapshot from [db]. Called by the in-app runner's
  /// database watch and by the background monitor after every cycle (its
  /// writes happen on another connection the app's streams don't see).
  static Future<void> publishMonitor(AppDatabase db, {required bool live}) async {
    if (!supported) return;
    final snap = await monitorSnapshot(db, live: live);
    if (await _save(kMonitor, snap)) await update(const [WidgetKind.monitor]);
  }

  /// Monitor status for the widget: each enabled target's latest check, 24 h
  /// uptime and one block per hour (0 no data, 1 healthy, 2 degraded, 3 down).
  static Future<Map<String, Object?>> monitorSnapshot(AppDatabase db, {required bool live}) async {
    final now = DateTime.now();
    final startSec = now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000;
    final targets =
        await (db.select(db.monitorTargets)
              ..where((t) => t.enabled.equals(true))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
            .get();
    // drift stores DateTime as unix seconds.
    final rows = await db
        .customSelect(
          'SELECT target_id, CAST((at - ?) / 3600 AS INTEGER) AS b, COUNT(*) AS n, '
          'SUM(CASE WHEN received = 0 THEN 1 ELSE 0 END) AS down, SUM(sent) AS sent, SUM(received) AS recv '
          'FROM monitor_checks WHERE at >= ? GROUP BY target_id, b',
          variables: [Variable.withInt(startSec), Variable.withInt(startSec)],
          readsFrom: {db.monitorChecks},
        )
        .get();
    final open = await (db.select(db.incidents)..where((i) => i.endedAt.isNull())).get();
    final openTargets = open.map((i) => i.targetId).toSet();
    final byTarget = <int, Map<int, QueryRow>>{};
    for (final r in rows) {
      byTarget.putIfAbsent(r.read<int>('target_id'), () => {})[r.read<int>('b')] = r;
    }
    var allN = 0, allUp = 0;
    final out = <Map<String, Object?>>[];
    for (final t in targets) {
      final buckets = byTarget[t.id] ?? const {};
      var n = 0, up = 0;
      final blocks = StringBuffer();
      for (var b = 0; b < 24; b++) {
        final r = buckets[b];
        if (r == null) {
          blocks.write('0');
          continue;
        }
        final cn = r.read<int>('n'), cd = r.read<int>('down');
        final sent = r.read<int>('sent'), recv = r.read<int>('recv');
        n += cn;
        up += cn - cd;
        blocks.write(
          cd > 0
              ? '3'
              : sent > 0 && (sent - recv) / sent > 0.05
              ? '2'
              : '1',
        );
      }
      allN += n;
      allUp += up;
      final last =
          await (db.select(db.monitorChecks)
                ..where((c) => c.targetId.equals(t.id))
                ..orderBy([(c) => OrderingTerm.desc(c.at)])
                ..limit(1))
              .getSingleOrNull();
      out.add({
        'name': t.name,
        'host': t.host,
        'down': last != null && last.received == 0,
        'ms': last?.rttAvg,
        'uptime': n == 0 ? null : up / n * 100,
        'incident': openTargets.contains(t.id),
        'blocks': blocks.toString(),
      });
    }
    return {
      'at': now.millisecondsSinceEpoch,
      'live': live,
      'uptime': allN == 0 ? null : allUp / allN * 100,
      'incidents': open.length,
      'targets': out,
    };
  }

  // ---- Android: per-widget settings ----

  static Future<WidgetSettings> settingsFor(int widgetId, WidgetKind kind) async {
    if (!supported) return WidgetSettings.defaultsFor(kind);
    await init();
    try {
      final raw = await HomeWidget.getWidgetData<String>(kConfig(widgetId));
      if (raw == null) return WidgetSettings.defaultsFor(kind);
      return WidgetSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>, kind);
    } on Object {
      return WidgetSettings.defaultsFor(kind);
    }
  }

  /// Saves one widget's settings, redraws it, re-arms background refresh and,
  /// for ping widgets, pings its hosts right away so it isn't empty.
  static Future<void> saveSettings(int widgetId, WidgetKind kind, WidgetSettings s) async {
    await init();
    await HomeWidget.saveWidgetData<String>(kConfig(widgetId), jsonEncode(s.toJson()));
    await update([kind]);
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('reschedule');
      if (kind.pings) {
        final hosts = kind == WidgetKind.network ? const [kGatewayHost] : [for (final t in s.targets) t.host];
        unawaited(_channel.invokeMethod('refreshPings', {'hosts': hosts, 'count': s.probes}));
      }
    } on Object catch (e) {
      debugPrint('Widgets: reschedule failed: $e');
    }
  }

  /// Placed widgets, so Settings can list and edit them.
  static Future<List<PlacedWidget>> installed() async {
    if (!supported) return const [];
    await init();
    try {
      final list = await HomeWidget.getInstalledWidgets();
      return [
        for (final w in list)
          if ((Platform.isAndroid ? WidgetKind.byAndroidClass(w.androidClassName) : _byIOSKind(w.iOSKind))
              case final k?)
            PlacedWidget(kind: k, androidId: w.androidWidgetId, iOSFamily: w.iOSFamily),
      ];
    } on Object {
      return const [];
    }
  }

  static WidgetKind? _byIOSKind(String? kind) => WidgetKind.values.where((k) => k.iOSKind == kind).firstOrNull;

  /// Android 8+: asks the launcher to place a widget (the launcher shows its
  /// own confirmation, then our settings screen).
  static Future<bool> canPin() async {
    if (!supported || !Platform.isAndroid) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> pin(WidgetKind kind) =>
      HomeWidget.requestPinWidget(qualifiedAndroidName: kind.qualifiedAndroidName);

  /// Inside the configure activity: the widget being set up, if any.
  static Future<void> finishConfigure() async {
    if (!Platform.isAndroid) return;
    await HomeWidget.finishHomeWidgetConfigure();
  }
}
