import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Ping (one host)

struct PingEntry: TimelineEntry {
  var date: Date
  var config: PingConfig
  var snap: PingSnapshot?
}

struct PingProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PingEntry {
    PingEntry(date: .now, config: PingConfig(), snap: .sample)
  }

  func snapshot(for config: PingConfig, in context: Context) async -> PingEntry {
    PingEntry(date: .now, config: config, snap: context.isPreview ? .sample : PulseStore.ping(config.target.host) ?? .sample)
  }

  /// Pings when the stored replies are older than the chosen interval, then
  /// asks to be reloaded after it (iOS decides the actual cadence).
  func timeline(for config: PingConfig, in context: Context) async -> Timeline<PingEntry> {
    let host = config.target.host
    let minutes = Double(config.interval.rawValue)
    let fresh = PulseStore.ping(host).map { Date().timeIntervalSince($0.date) < (minutes - 1) * 60 } ?? false
    if !fresh { await PulsePinger.refresh([host], count: config.probes) }
    let entry = PingEntry(date: .now, config: config, snap: PulseStore.ping(host))
    return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(minutes * 60)))
  }
}

struct PingWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: PingEntry

  var body: some View {
    Themed { p in content(p).pulseBackground(entry.config.background) }
      .widgetURL(PulseLink.ping(entry.config.target))
  }

  @ViewBuilder
  private func content(_ p: Palette) -> some View {
    let t = entry.config.target
    let s = entry.snap
    let lost = s?.lastLost == true
    let number = s == nil ? "—" : lost ? "Lost" : Fmt.ms(s?.last)
    let color = lost ? p.error : p.latency(s?.last)
    let status = s == nil ? "Tap ↻ to ping" : (s?.error != nil && s!.replies.isEmpty) ? s!.error! : lost ? "No reply · \(Fmt.ago(s?.date))" : Fmt.ago(s?.date)
    let refresh = RefreshButton(hosts: [t.host], probes: entry.config.probes, palette: p)

    switch family {
    case .accessoryInline:
      Text("\(Image(systemName: "waveform.path.ecg")) \(t.title) \(number)\(lost || s == nil ? "" : " ms")")
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          Text(number).font(.system(size: 18, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5)
          Text(lost ? "lost" : "ms").font(.system(size: 9))
        }
      }
      .widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(t.title).font(.headline).lineLimit(1)
          Spacer(minLength: 4)
          Text(number + (lost || s == nil ? "" : " ms")).font(.system(.headline, design: .rounded)).widgetAccentable()
        }
        if entry.config.showChart, let s { Sparkline(samples: s.samples, palette: p, maxBars: 16).frame(height: 18) }
        else { Text(status).font(.caption2).foregroundStyle(.secondary) }
      }
    case .systemSmall:
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 1) {
            Text(t.title).font(.system(size: 13, weight: .bold)).foregroundStyle(p.onSurface)
            if t.name != nil && t.host != gatewayHost { Text(t.host).font(.system(size: 10)).foregroundStyle(p.muted) }
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          refresh
        }
        Spacer(minLength: 0)
        BigNumber(value: number, unit: lost || s == nil ? nil : "ms", color: color, size: 38, palette: p)
        Text(status).font(.system(size: 10)).foregroundStyle(p.muted).lineLimit(1)
        if entry.config.showChart { Sparkline(samples: s?.samples ?? [], palette: p, maxBars: 16).frame(height: 20) }
      }
    default:  // medium, large, extra large
      let large = family == .systemLarge || family == .systemExtraLarge
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Badge(symbol: "waveform.path.ecg", bg: p.hero, fg: p.onHero)
          VStack(alignment: .leading, spacing: 1) {
            Text(t.title).font(.system(size: 14, weight: .bold)).foregroundStyle(p.onSurface)
            Text(t.title != t.host && t.host != gatewayHost ? "\(t.host) · \(status)" : status)
              .font(.system(size: 10)).foregroundStyle(p.muted)
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          refresh
        }
        Spacer(minLength: 0)
        if large {
          BigNumber(value: number, unit: lost || s == nil ? nil : "ms", color: color, size: 56, palette: p)
          if entry.config.showChart { Sparkline(samples: s?.samples ?? [], palette: p, maxBars: 30).frame(height: 80) }
        } else {
          HStack(alignment: .bottom) {
            BigNumber(value: number, unit: lost || s == nil ? nil : "ms", color: color, size: 40, palette: p)
            Spacer(minLength: 8)
            if entry.config.showChart { Sparkline(samples: s?.samples ?? [], palette: p, maxBars: 24).frame(width: 150, height: 38) }
          }
        }
        if let s {
          HStack {
            Stat(value: Fmt.ms(s.avg), caption: "avg ms", palette: p).frame(maxWidth: .infinity, alignment: .leading)
            Stat(value: "\(Fmt.ms(s.min))–\(Fmt.ms(s.max))", caption: "min–max", palette: p).frame(maxWidth: .infinity, alignment: .leading)
            Stat(value: Fmt.ms(s.jitter), caption: "jitter", palette: p).frame(maxWidth: .infinity, alignment: .leading)
            Stat(value: Fmt.pct(s.lossPct, digits: 0), caption: "loss", palette: p, color: (s.lossPct ?? 0) > 0 ? p.error : nil)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }
}

struct PingWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKinds.ping, intent: PingConfig.self, provider: PingProvider()) { entry in
      PingWidgetView(entry: entry)
    }
    .configurationDisplayName("Ping")
    .description("Live latency for one host, with a reply chart and stats.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

// MARK: - Multi-host ping

struct MultiPingEntry: TimelineEntry {
  var date: Date
  var config: MultiPingConfig
  var snaps: [PingSnapshot?]
}

struct MultiPingProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> MultiPingEntry {
    MultiPingEntry(date: .now, config: MultiPingConfig(), snaps: [.sample, .sample, .sample, .sample])
  }

  func snapshot(for config: MultiPingConfig, in context: Context) async -> MultiPingEntry {
    MultiPingEntry(date: .now, config: config, snaps: config.targets.map { context.isPreview ? .sample : PulseStore.ping($0.host) })
  }

  func timeline(for config: MultiPingConfig, in context: Context) async -> Timeline<MultiPingEntry> {
    let minutes = Double(config.interval.rawValue)
    let stale = config.targets.filter { t in
      guard let s = PulseStore.ping(t.host) else { return true }
      return Date().timeIntervalSince(s.date) >= (minutes - 1) * 60
    }
    if !stale.isEmpty { await PulsePinger.refresh(stale.map(\.host), count: config.probes) }
    let entry = MultiPingEntry(date: .now, config: config, snaps: config.targets.map { PulseStore.ping($0.host) })
    return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(minutes * 60)))
  }
}

struct MultiPingWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: MultiPingEntry

  var body: some View {
    Themed { p in content(p).pulseBackground(entry.config.background) }
      .widgetURL(PulseLink.open("/ping"))
  }

  @ViewBuilder
  private func content(_ p: Palette) -> some View {
    let rows = Array(zip(entry.config.targets, entry.snaps))
    let newest = entry.snaps.compactMap { $0?.date }.max()
    switch family {
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        ForEach(rows.prefix(3), id: \.0) { t, s in
          HStack {
            Text(t.title).lineLimit(1)
            Spacer(minLength: 4)
            Text(s?.lastLost == true ? "Lost" : Fmt.ms(s?.last)).font(.system(.body, design: .rounded).weight(.bold))
          }
          .font(.caption)
        }
      }
    default:
      let maxRows = family == .systemSmall ? 3 : family == .systemMedium ? 4 : 6
      let wide = family != .systemSmall
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          if wide { Badge(symbol: "chart.bar.fill", bg: p.hero, fg: p.onHero, size: 26) }
          VStack(alignment: .leading, spacing: 0) {
            Text("Ping").font(.system(size: 14, weight: .bold)).foregroundStyle(p.onSurface)
            Text(newest == nil ? "Tap ↻ to ping" : Fmt.ago(newest)).font(.system(size: 10)).foregroundStyle(p.muted)
          }
          Spacer(minLength: 4)
          RefreshButton(hosts: entry.config.targets.map(\.host), probes: entry.config.probes, palette: p)
        }
        Spacer(minLength: 0)
        ForEach(rows.prefix(maxRows), id: \.0) { t, s in
          let lost = s?.lastLost == true
          Link(destination: PulseLink.ping(t)) {
            HStack(spacing: 8) {
              Circle().fill(s == nil ? p.timeout : lost ? p.error : p.latency(s?.last)).frame(width: 8, height: 8)
              VStack(alignment: .leading, spacing: 0) {
                Text(t.title).font(.system(size: 13, weight: .medium)).foregroundStyle(p.onSurface)
                if wide && family != .systemMedium && t.host != gatewayHost && t.title != t.host {
                  Text(t.host).font(.system(size: 10)).foregroundStyle(p.muted)
                }
              }
              .lineLimit(1)
              Spacer(minLength: 4)
              if wide && entry.config.showChart, let s {
                Sparkline(samples: s.samples, palette: p, maxBars: 12).frame(width: 80, height: 18)
              }
              Text(lost ? "Lost" : Fmt.ms(s?.last))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(lost ? p.error : p.latency(s?.last))
                .frame(minWidth: 34, alignment: .trailing)
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

struct MultiPingWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKinds.multiPing, intent: MultiPingConfig.self, provider: MultiPingProvider()) { entry in
      MultiPingWidgetView(entry: entry)
    }
    .configurationDisplayName("Multi-host ping")
    .description("Your router, DNS and servers side by side.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular])
  }
}

extension PingSnapshot {
  static let sample = PingSnapshot(
    host: "1.1.1.1", at: Date().timeIntervalSince1970 * 1000,
    samples: [14, 12, 15, 13, 18, 12, 11, 14, 22, 13, 12, 15, 14, 13, 12, 16], error: nil)
}
