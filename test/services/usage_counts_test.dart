import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/services/pulse_api.dart';
import 'package:pulse/services/usage_counts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late List<http.Request> sent;
  var now = DateTime(2026, 11, 25, 10);
  var up = true;

  setUp(() async {
    UsageCounts.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sent = [];
    now = DateTime(2026, 11, 25, 10);
    up = true;
  });

  UsageCounts make() => UsageCounts(
    prefs,
    version: '1.2.4',
    platform: 'android',
    now: () => now,
    api: PulseApi(
      key: 'k',
      baseUrl: 'https://api.test',
      client: MockClient((r) async {
        sent.add(r);
        return up ? http.Response('{"counted":1}', 200) : http.Response('down', 503);
      }),
    ),
  );

  test('counts per day, sends only finished days, with no identifier', () async {
    final c = make();
    await UsageCounts.init(c, enabled: true, installed: DateTime(2026, 11, 20));
    UsageCounts.count(UsageEvent.traceRun);
    UsageCounts.count(UsageEvent.traceRun);
    UsageCounts.count(UsageEvent.speedRun);
    expect(sent, isEmpty, reason: 'today is still counting');
    expect(c.tally['2026-11-25'], {'active:d1_6': 1, 'trace.run': 2, 'speed.run': 1});

    now = DateTime(2026, 11, 26, 9);
    await UsageCounts.resumed();
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/api/v1/usage');
    expect(sent.single.headers['x-pulse-signature'], isNotEmpty);
    final items = (jsonDecode(sent.single.body) as Map<String, dynamic>)['items'] as List;
    expect(
      items,
      unorderedEquals([
        {
          'day': '2026-11-25',
          'event': 'active',
          'count': 1,
          'platform': 'android',
          'version': '1.2.4',
          'bucket': 'd1_6',
        },
        {'day': '2026-11-25', 'event': 'trace.run', 'count': 2, 'platform': 'android', 'version': '1.2.4'},
        {'day': '2026-11-25', 'event': 'speed.run', 'count': 1, 'platform': 'android', 'version': '1.2.4'},
      ]),
    );
    for (final i in items.cast<Map<String, dynamic>>()) {
      expect(i.keys.toSet().difference({'day', 'event', 'count', 'platform', 'version', 'bucket'}), isEmpty);
    }
    // Sent days are gone; today (the 26th) is active once.
    expect(c.tally.keys, ['2026-11-26']);
    await UsageCounts.resumed();
    expect(c.tally['2026-11-26'], {'active:d1_6': 1});
  });

  test('a failed send keeps the days for next time', () async {
    final c = make();
    await UsageCounts.init(c, enabled: true);
    UsageCounts.count(UsageEvent.pingStart);
    now = now.add(const Duration(days: 1));
    up = false;
    await UsageCounts.resumed();
    expect(c.tally.containsKey('2026-11-25'), isTrue);
    up = true;
    await UsageCounts.resumed();
    expect(c.tally.containsKey('2026-11-25'), isFalse);
  });

  test('turned off: nothing is counted or sent, and the tally is cleared', () async {
    final c = make();
    await UsageCounts.init(c, enabled: true);
    UsageCounts.count(UsageEvent.lanScan);
    await UsageCounts.setEnabled(false);
    expect(c.tally, isEmpty);
    UsageCounts.count(UsageEvent.lanScan);
    now = now.add(const Duration(days: 2));
    await UsageCounts.resumed();
    expect(c.tally, isEmpty);
    expect(sent, isEmpty);
  });

  test('install-age buckets', () async {
    final c = make();
    await UsageCounts.init(c, enabled: false, installed: DateTime(2026, 11, 25));
    expect(c.bucket(), 'd0');
    now = DateTime(2026, 12, 1);
    expect(c.bucket(), 'd1_6');
    now = DateTime(2026, 12, 2);
    expect(c.bucket(), 'd7_29');
    now = DateTime(2026, 12, 25);
    expect(c.bucket(), 'd30');
  });

  test('every event is on the server allow-list', () {
    const server = {
      'active', 'ping.start', 'trace.run', 'ports.scan', 'speed.run', 'loss.run', 'lan.scan', 'geo.lookup', //
      'monitor.add', 'alert.add', 'wol.send', 'router.signin', 'router.wifi', 'router.wan', 'router.reboot',
      'share', 'export',
    };
    expect(UsageEvent.values.map((e) => e.id).toSet(), server);
  });
}
