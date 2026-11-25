import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/data/db/app_database.dart';
import 'package:pulse/presentations/screens/settings/legal_screen.dart';
import 'package:pulse/providers/database_provider.dart';
import 'package:pulse/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

void main() {
  setUpAll(loadPulseFonts);

  group('parseLegalMarkdown', () {
    test('headings, paragraphs, bullets, rules and two-space line breaks', () {
      const md =
          '# Title\n\n**Version: 1.3**  \n**Date: today**\n\nOne paragraph\nhard-wrapped.\n\n'
          '## Section\n\n- **Bold:** item\n  continued\n- second\n  - nested\n1. numbered\n\n---\n';
      expect(parseLegalMarkdown(md), const [
        LegalBlock(LegalBlockKind.heading, 'Title', level: 1),
        LegalBlock(LegalBlockKind.paragraph, '**Version: 1.3**\n**Date: today**'),
        LegalBlock(LegalBlockKind.paragraph, 'One paragraph hard-wrapped.'),
        LegalBlock(LegalBlockKind.heading, 'Section', level: 2),
        LegalBlock(LegalBlockKind.bullet, '**Bold:** item continued'),
        LegalBlock(LegalBlockKind.bullet, 'second'),
        LegalBlock(LegalBlockKind.bullet, 'nested', level: 1),
        LegalBlock(LegalBlockKind.bullet, 'numbered'),
        LegalBlock(LegalBlockKind.rule, ''),
      ]);
    });

    test('bold runs become spans and no markup is left in the text', () {
      final spans = legalSpans('a **b** c');
      expect(spans.map((s) => (s as TextSpan).text), ['a ', 'b', ' c']);
      for (final doc in LegalDoc.values) {
        final blocks = parseLegalMarkdown(File(doc.asset).readAsStringSync());
        final shown = blocks.map((b) => legalSpans(b.text).map((s) => (s as TextSpan).text).join()).join('\n');
        expect(shown, isNot(contains('**')), reason: doc.name);
        expect(shown, isNot(matches(RegExp(r'^#', multiLine: true))), reason: doc.name);
      }
    });
  });

  test('bundled documents match privacy-project (the source of legal.pranta.dev)', () {
    final source = Directory('../../privacy-project/Projects/pulse');
    if (!source.existsSync()) return markTestSkipped('privacy-project is not checked out next to pulse');
    for (final doc in LegalDoc.values) {
      final name = doc.asset.split('/').last;
      String norm(String s) => s.replaceAll('\r\n', '\n');
      expect(
        norm(File(doc.asset).readAsStringSync()),
        norm(File('${source.path}/$name').readAsStringSync()),
        reason: 'assets/legal/$name is out of date: copy it from privacy-project/Projects/pulse/$name',
      );
    }
  });

  for (final doc in LegalDoc.values) {
    testWidgets('legal: ${doc.name}', (tester) async {
      final c = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            databaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
          ],
        );
        await c.read(legalTextProvider(doc).future);
        return c;
      }))!;
      final failures = await renderMatrix(tester, 'legal_${doc.name}', c, LegalScreen(doc: doc), location: doc.route);
      expect(failures, isEmpty);
      expect(find.text(doc.title), findsWidgets);
      expect(find.textContaining('**'), findsNothing);
      c.dispose();
    });
  }
}
