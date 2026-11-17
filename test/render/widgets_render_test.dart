@Tags(['render'])
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/data/db/app_database.dart';
import 'package:pulse/presentations/screens/widgets/widget_config_screen.dart';
import 'package:pulse/presentations/screens/widgets/widgets_screen.dart';
import 'package:pulse/providers/database_provider.dart';
import 'package:pulse/providers/settings_provider.dart';
import 'package:pulse/services/widgets/home_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

/// Settings › Home screen widgets and each widget kind's settings screen.
/// (The test host has no widget platform, so they show their defaults.)
void main() {
  setUpAll(loadPulseFonts);

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
      ],
    );
  }

  testWidgets('home screen widgets', (tester) async {
    final c = (await tester.runAsync(container))!;
    final failures = await renderMatrix(tester, 'widgets', c, const WidgetsScreen(), location: '/settings/widgets');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    expect(failures, isEmpty);
  });

  for (final kind in WidgetKind.values) {
    testWidgets('widget settings: ${kind.name}', (tester) async {
      final c = (await tester.runAsync(container))!;
      final failures = await renderMatrix(
        tester,
        'widget_config_${kind.name}',
        c,
        WidgetConfigScreen(widgetId: 1, kind: kind, fromLauncher: true),
        location: '/widgets/configure',
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      expect(failures, isEmpty);
    });
  }
}
