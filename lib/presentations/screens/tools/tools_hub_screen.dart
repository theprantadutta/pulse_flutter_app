import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../navigation/destinations.dart';
import '../../../providers/router_provider.dart';
import '../../navigation/tools_catalog.dart';

/// 05 Tools hub: 8 tool tiles with their last result, then the wide Router
/// card. Phone: 2-column grid of 138 dp tiles. Tablet: 4 x 2 grid of large
/// tiles plus the card, filling the screen.
class ToolsHubScreen extends ConsumerWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(toolStatusProvider);
    final compact = context.isCompact;
    return PulsePage(
      title: 'Tools',
      large: true,
      subtitle: compact ? null : '${kTools.length} tools · tap to open',
      actions: [
        if (compact)
          PulseIconButton(
            icon: PulseIcons.settings,
            tooltip: 'Settings',
            onPressed: () => context.push(Routes.settings),
          )
        else
          PulseButton(
            label: 'Settings',
            icon: PulseIcons.settings,
            style: PulseButtonStyle.tonal,
            onPressed: () => context.push(Routes.settings),
          ),
      ],
      body: LayoutBuilder(
        builder: (context, box) {
          final grid = [
            for (final t in kTools)
              if (t != kRouterTool) t,
          ];
          final columns = compact ? 2 : (box.maxWidth >= 720 ? 4 : 2);
          final rows = (grid.length / columns).ceil();
          final pad = context.pagePadding;
          const gap = 12.0;
          // Two columns make a narrower card: room for a third line and two chip rows.
          var cardHeight = columns == 4 ? 176.0 : 220.0;
          // Tablets fill the height with the grid plus the Router card;
          // phones use 138 dp tiles and scroll.
          // The page leaves the bottom system inset (gesture bar) to us.
          final inset = MediaQuery.paddingOf(context).bottom;
          double tileFor(double card) => (box.maxHeight - 4 - pad - inset - card - gap - gap * (rows - 1)) / rows;
          // Short screens (a landscape 8" tablet): the card drops its chips
          // so the tiles keep a usable height.
          var chips = true;
          if (!compact && tileFor(cardHeight) < 150) {
            cardHeight = columns == 4 ? 124.0 : 168.0;
            chips = false;
          }
          final tileHeight = compact ? 138.0 : tileFor(cardHeight).clamp(150.0, 320.0);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: compact ? 10 : gap,
                    crossAxisSpacing: compact ? 10 : gap,
                    mainAxisExtent: tileHeight,
                  ),
                  itemCount: grid.length,
                  itemBuilder: (context, i) => PulseEntrance(
                    index: i,
                    child: ToolTile(
                      tool: grid[i],
                      status: status[grid[i]] ?? ToolStatus(grid[i].empty),
                      large: !compact,
                      // Short tablet tiles (e.g. five rows in portrait) use a
                      // smaller badge and title so the content fits.
                      dense: !compact && tileHeight < 185,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, compact ? 10 : gap, pad, pad + inset),
                sliver: SliverToBoxAdapter(
                  child: PulseEntrance(
                    index: grid.length,
                    // Phones: as tall as its content. Tablets: fixed, so the
                    // grid above can fill the rest of the height.
                    child: compact
                        ? const RouterToolCard()
                        : SizedBox(
                            height: cardHeight,
                            child: RouterToolCard(large: true, lines: columns == 4 ? 2 : 3, chips: chips),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The Tools hub's wide Router card: what Pulse can do with the router, and
/// the router on this network once detected.
class RouterToolCard extends ConsumerWidget {
  const RouterToolCard({super.key, this.large = false, this.lines = 2, this.chips = true});
  final bool large;

  /// Feature chips under the description (left out when height is short).
  final bool chips;

  /// Description lines on the large (tablet) card.
  final int lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final router = ref.watch(routerProfileProvider).value;
    const t = kRouterTool;
    const features = ['Devices', 'Wi-Fi', 'Guest network', 'Internet type', 'Restart'];
    const blurb =
        'See every device, switch Wi-Fi and the guest network, change the internet connection and restart '
        'your router, right in Pulse.';
    final title = Text(
      'Router',
      maxLines: 1,
      style: pulseText(large ? 28 : 19, 800, wdth: large ? 115 : 110, height: 1.15).copyWith(color: c.onSurface),
    );
    final name = router == null
        ? null
        : Text(
            router.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.bodySmall!.copyWith(fontSize: large ? 15 : 13, color: c.onSurfaceVariant),
          );
    final pills = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final f in features) PulsePill(f, tone: PulsePillTone.outline)],
    );
    final chevron = PulseIcon(PulseIcons.chevR, size: 22, color: c.onSurfaceVariant);
    final body = large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PulseShapeBadge(shape: t.shape, tone: t.tone, icon: t.icon, size: 72),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: title),
                        if (name != null) ...[const SizedBox(width: 10), Flexible(child: name)],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blurb,
                      maxLines: lines,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.bodySmall!.copyWith(fontSize: 15, color: c.onSurfaceVariant),
                    ),
                    if (chips) ...[const Spacer(), pills],
                  ],
                ),
              ),
              chevron,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PulseShapeBadge(shape: t.shape, tone: t.tone, icon: t.icon, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, ?name]),
                  ),
                  chevron,
                ],
              ),
              const SizedBox(height: 10),
              Text(blurb, style: context.type.bodySmall!.copyWith(fontSize: 13, color: c.onSurfaceVariant)),
              const SizedBox(height: 12),
              pills,
            ],
          );
    return Semantics(
      button: true,
      label: 'Router${router == null ? '' : ', ${router.name}'}. $blurb',
      excludeSemantics: true,
      child: PulsePressable(
        onTap: () => context.push(t.route),
        radius: 28,
        color: c.surfaceContainer,
        child: Padding(padding: EdgeInsets.all(large ? 22 : 16), child: body),
      ),
    );
  }
}

/// A tool tile: badge top-left, name and last result at the bottom. Monitor is
/// pink with a blinking "LIVE" label while monitoring runs.
class ToolTile extends StatelessWidget {
  const ToolTile({super.key, required this.tool, required this.status, this.large = false, this.dense = false});

  final PulseTool tool;
  final ToolStatus status;
  final bool large;

  /// A large tile with less height: smaller badge, padding and title.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hot = status.live;
    final fg = hot ? c.onPrimaryFixed : c.onSurface;
    final sub = hot ? c.onPrimaryFixed : c.onSurfaceVariant;
    final badgeSize = large ? (dense ? 54.0 : 72.0) : 44.0;
    final radius = hot ? (large ? 36.0 : 32.0) : 28.0;
    return Semantics(
      button: true,
      label: '${tool.name}, ${status.last}${hot ? ', live' : ''}',
      excludeSemantics: true,
      child: PulsePressable(
        onTap: () => context.push(tool.route),
        radius: radius,
        color: hot ? c.primaryFixedDim : c.surfaceContainer,
        child: Padding(
          padding: large ? EdgeInsets.all(dense ? 18 : 22) : const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hot)
                    // On the pink tile the badge inverts: dark diamond, pink icon.
                    PulseContainerBadge(
                      shape: tool.shape,
                      icon: tool.icon,
                      color: c.onPrimaryFixed,
                      onColor: c.primaryFixedDim,
                      size: badgeSize,
                    )
                  else
                    PulseShapeBadge(shape: tool.shape, tone: tool.tone, icon: tool.icon, size: badgeSize),
                  const Spacer(),
                  if (hot)
                    Row(
                      children: [
                        PulseLiveDot(color: fg, size: 7),
                        const SizedBox(width: 6),
                        Text('LIVE', style: pulseText(large ? 13 : 12, 800).copyWith(color: fg)),
                      ],
                    )
                  else if (large)
                    PulseIcon(PulseIcons.chevR, size: 22, color: c.onSurfaceVariant),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: pulseText(
                      large ? (dense ? 24 : 28) : 19,
                      800,
                      wdth: large ? 115 : 110,
                      height: 1.15,
                    ).copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodySmall!.copyWith(fontSize: large ? 15 : 13, color: sub),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
