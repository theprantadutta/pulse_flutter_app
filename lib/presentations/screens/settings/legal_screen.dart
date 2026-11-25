import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../navigation/destinations.dart';
import 'settings_screen.dart' show kPrivacyUrl, kTermsUrl;

/// The legal documents bundled with the app (`assets/legal/`). They are copies
/// of `privacy-project/Projects/pulse/*.md`, the source of what
/// legal.pranta.dev serves; update both together.
enum LegalDoc {
  privacy('Privacy policy', 'assets/legal/privacy.md', kPrivacyUrl),
  terms('Terms of use', 'assets/legal/terms.md', kTermsUrl);

  const LegalDoc(this.title, this.asset, this.url);

  final String title;
  final String asset;

  /// The hosted copy, offered from the header and if the asset can't be read.
  final String url;

  static LegalDoc fromName(String? name) => values.firstWhere((d) => d.name == name, orElse: () => privacy);

  String get route => '${Routes.legal}?doc=$name';
}

final legalTextProvider = FutureProvider.family<String, LegalDoc>((ref, doc) => rootBundle.loadString(doc.asset));

/// Settings › Privacy policy / Terms of use, read inside the app.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(legalTextProvider(doc));
    final web = PulseIconButton(
      icon: PulseIcons.globe,
      tooltip: 'Open in browser',
      onPressed: () => openExternalLink(context, doc.url),
    );
    final pad = context.pagePadding;
    final Widget body = switch (text) {
      AsyncData(:final value) => _Document(blocks: parseLegalMarkdown(value), padding: pad),
      AsyncError() => ListView(
        padding: EdgeInsets.fromLTRB(pad, 24, pad, 24),
        children: [
          PulseEmptyState(
            icon: PulseIcons.shield,
            title: "Couldn't open the ${doc.title.toLowerCase()}",
            message: 'It is also at ${doc.url.replaceFirst('https://', '')}.',
            action: PulseButton(
              label: 'Open in browser',
              icon: PulseIcons.globe,
              onPressed: () => openExternalLink(context, doc.url),
            ),
          ),
        ],
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return PulsePage(title: doc.title, backTo: Routes.settings, showBack: true, actions: [web], body: body);
  }
}

class _Document extends StatelessWidget {
  const _Document({required this.blocks, required this.padding});

  final List<LegalBlock> blocks;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(padding, 4, padding, 24 + bottom),
      itemCount: blocks.length,
      // A readable line length on tablets and desktop.
      itemBuilder: (context, i) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(width: double.infinity, child: _BlockView(block: blocks[i], first: i == 0)),
        ),
      ),
    );
  }
}

enum LegalBlockKind { heading, paragraph, bullet, rule }

/// One block of a legal document. [level] is the heading level or the list
/// nesting depth.
@immutable
class LegalBlock {
  const LegalBlock(this.kind, this.text, {this.level = 0});

  final LegalBlockKind kind;
  final String text;
  final int level;

  @override
  bool operator ==(Object other) =>
      other is LegalBlock && other.kind == kind && other.text == text && other.level == level;

  @override
  int get hashCode => Object.hash(kind, text, level);

  @override
  String toString() => 'LegalBlock($kind, $level, "$text")';
}

final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _bullet = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$');
final _rule = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');

/// The Markdown the legal documents use: headings, paragraphs, `-`/`*`/`1.`
/// lists (nested by indentation), `---` rules and a line break after a line
/// ending in two spaces. Inline `**bold**` is drawn by [legalSpans].
List<LegalBlock> parseLegalMarkdown(String source) {
  final out = <LegalBlock>[];
  LegalBlockKind? open;
  var level = 0;
  // Whether the previous line ended in two spaces (a Markdown line break).
  var hardBreak = false;
  final buf = StringBuffer();

  void flush() {
    if (open != null && buf.isNotEmpty) out.add(LegalBlock(open!, buf.toString().trim(), level: level));
    buf.clear();
    open = null;
  }

  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (_rule.hasMatch(line)) {
      flush();
      out.add(const LegalBlock(LegalBlockKind.rule, ''));
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flush();
      out.add(LegalBlock(LegalBlockKind.heading, h.group(2)!.trim(), level: h.group(1)!.length));
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null) {
      flush();
      open = LegalBlockKind.bullet;
      level = b.group(1)!.length ~/ 2;
      buf.write(b.group(2));
      continue;
    }
    if (open == null) {
      open = LegalBlockKind.paragraph;
      level = 0;
      buf.write(line.trim());
    } else {
      buf.write(hardBreak ? '\n${line.trim()}' : ' ${line.trim()}');
    }
    hardBreak = raw.endsWith('  ');
  }
  flush();
  return out;
}

final _bold = RegExp(r'\*\*(.+?)\*\*');

/// [text] with `**bold**` runs in [boldWeight].
List<InlineSpan> legalSpans(String text, {FontWeight boldWeight = FontWeight.w700}) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _bold.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(
      TextSpan(
        text: m.group(1),
        style: TextStyle(fontWeight: boldWeight),
      ),
    );
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.first});

  final LegalBlock block;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final body = t.bodyLarge!.copyWith(color: c.onSurfaceVariant, height: 1.5);
    Widget rich(String text, TextStyle style) => Text.rich(TextSpan(style: style, children: legalSpans(text)));

    switch (block.kind) {
      case LegalBlockKind.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: c.outlineVariant),
        );
      case LegalBlockKind.heading:
        // The document's own title repeats the page title, so it is shown
        // smaller, as a subtitle.
        final style = switch (block.level) {
          1 => t.titleMedium!.copyWith(color: c.onSurfaceVariant),
          2 => t.titleLarge!.copyWith(color: c.primary, fontWeight: FontWeight.w700),
          _ => t.titleMedium!.copyWith(color: c.onSurface, fontWeight: FontWeight.w700),
        };
        return Padding(
          padding: EdgeInsets.only(top: first ? 0 : (block.level <= 2 ? 24 : 16), bottom: 8),
          child: Semantics(header: true, child: rich(block.text, style)),
        );
      case LegalBlockKind.bullet:
        return Padding(
          padding: EdgeInsetsDirectional.only(start: 4 + block.level * 16.0, top: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: body.fontSize! * .62),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: rich(block.text, body)),
            ],
          ),
        );
      case LegalBlockKind.paragraph:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: rich(block.text, body));
    }
  }
}
