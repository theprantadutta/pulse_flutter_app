import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Speed test

struct SpeedEntry: TimelineEntry {
  var date: Date
  var config: SpeedConfig
  var snap: SpeedSnapshot?
}

/// The app writes results and reloads this widget after each test, so the
/// timeline only refreshes "x min ago" every half hour.
struct SpeedProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> SpeedEntry { SpeedEntry(date: .now, config: SpeedConfig(), snap: .sample) }

  func snapshot(for config: SpeedConfig, in context: Context) async -> SpeedEntry {
    SpeedEntry(date: .now, config: config, snap: context.isPreview ? .sample : PulseStore.speed ?? .sample)
  }

  func timeline(for config: SpeedConfig, in context: Context) async -> Timeline<SpeedEntry> {
    Timeline(entries: [SpeedEntry(date: .now, config: config, snap: PulseStore.speed)], policy: .after(.now.addingTimeInterval(1800)))
  }
}

struct SpeedWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: SpeedEntry

  var body: some View {
    Themed { p in content(p).pulseBackground(entry.config.background) }
      .widgetURL(PulseLink.url("speed"))
  }

  private var runURL: URL { PulseLink.url("speed", ["run": "1"]) }

  @ViewBuilder
  private func content(_ p: Palette) -> some View {
    let s = entry.snap
    let sub = s == nil ? "No test yet" : Fmt.ago(s?.date)
    switch family {
    case .accessoryInline:
      Text("\(Image(systemName: "arrow.down")) \(Fmt.mbps(s?.down)) \(Image(systemName: "arrow.up")) \(Fmt.mbps(s?.up)) Mbps")
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
          Text(Fmt.mbps(s?.down)).font(.system(size: 17, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5)
          Text("Mbps").font(.system(size: 8))
        }
      }
      .widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text("Speed test").font(.headline)
        Text("↓ \(Fmt.mbps(s?.down))  ↑ \(Fmt.mbps(s?.up)) Mbps").font(.system(.body, design: .rounded).weight(.semibold)).widgetAccentable()
        Text("\(Fmt.ms(s?.ping)) ms · \(sub)").font(.caption2).foregroundStyle(.secondary)
      }
    case .systemSmall:
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          VStack(alignment: .leading, spacing: 0) {
            Text("Speed").font(.system(size: 13, weight: .bold)).foregroundStyle(p.onSurface)
            Text(sub).font(.system(size: 10)).foregroundStyle(p.muted)
          }
          Spacer(minLength: 4)
          runButton(p, compact: true)
        }
        Spacer(minLength: 0)
        BigNumber(value: Fmt.mbps(s?.down), unit: "Mbps", color: p.onSurface, size: 34, palette: p)
        HStack(spacing: 10) {
          Label(Fmt.mbps(s?.up), systemImage: "arrow.up").foregroundStyle(p.onSurface)
          Label("\(Fmt.ms(s?.ping)) ms", systemImage: "waveform.path.ecg").foregroundStyle(p.latency(s?.ping))
        }
        .font(.system(size: 11, weight: .medium))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
      }
    default:
      let large = family == .systemLarge || family == .systemExtraLarge
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Badge(symbol: "speedometer", bg: p.hero, fg: p.onHero)
          VStack(alignment: .leading, spacing: 0) {
            Text("Speed test").font(.system(size: 14, weight: .bold)).foregroundStyle(p.onSurface)
            Text(s == nil ? sub : "\((s?.server ?? "").isEmpty ? "Last test" : s!.server!) · \(sub)")
              .font(.system(size: 10)).foregroundStyle(p.muted).lineLimit(1)
          }
          Spacer(minLength: 4)
          runButton(p, compact: false)
        }
        Spacer(minLength: 0)
        HStack(alignment: .bottom) {
          metric(p, "arrow.down", "Download", Fmt.mbps(s?.down), p.primary).frame(maxWidth: .infinity, alignment: .leading)
          metric(p, "arrow.up", "Upload", Fmt.mbps(s?.up), p.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack {
          Stat(value: "\(Fmt.ms(s?.ping)) ms", caption: "ping", palette: p, color: p.latency(s?.ping)).frame(maxWidth: .infinity, alignment: .leading)
          Stat(value: "\(Fmt.ms(s?.jitter)) ms", caption: "jitter", palette: p).frame(maxWidth: .infinity, alignment: .leading)
        }
        if large && entry.config.showHistory, let s, s.history.count > 1 {
          Text("Recent tests · download").font(.system(size: 10)).foregroundStyle(p.muted)
          history(p, s.history).frame(height: family == .systemExtraLarge ? 140 : 90)
        }
      }
    }
  }

  private func runButton(_ p: Palette, compact: Bool) -> some View {
    Link(destination: runURL) {
      HStack(spacing: 4) {
        Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
        if !compact { Text("Run").font(.system(size: 12, weight: .bold)) }
      }
      .foregroundStyle(p.onPrimary)
      .padding(.horizontal, compact ? 9 : 12)
      .padding(.vertical, 7)
      .background(Capsule().fill(p.primary))
    }
    .accessibilityLabel("Run a speed test")
  }

  private func metric(_ p: Palette, _ symbol: String, _ caption: String, _ value: String, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Label(caption, systemImage: symbol).font(.system(size: 11)).foregroundStyle(p.muted).labelStyle(.titleAndIcon)
      BigNumber(value: value, unit: "Mbps", color: p.onSurface, size: 30, palette: p)
    }
  }

  private func history(_ p: Palette, _ runs: [SpeedRun]) -> some View {
    let list = Array(runs.prefix(8).reversed())
    let peak = max(list.compactMap(\.down).max() ?? 1, 1)
    return GeometryReader { geo in
      HStack(alignment: .bottom, spacing: 6) {
        ForEach(Array(list.enumerated()), id: \.offset) { i, r in
          RoundedRectangle(cornerRadius: 6)
            .fill(i == list.count - 1 ? p.primary : p.secondaryContainer)
            .frame(height: max(4, geo.size.height * (r.down ?? 0) / peak))
            .frame(maxWidth: .infinity)
        }
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
  }
}

struct SpeedWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKinds.speed, intent: SpeedConfig.self, provider: SpeedProvider()) { entry in
      SpeedWidgetView(entry: entry)
    }
    .configurationDisplayName("Speed test")
    .description("Your latest download, upload and ping, and a button to run a new test.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

extension SpeedSnapshot {
  static let sample = SpeedSnapshot(
    at: Date().timeIntervalSince1970 * 1000 - 600_000, down: 248, up: 61, ping: 12, jitter: 2.1, server: "Cloudflare DAC",
    history: ([248, 231, 190, 260, 222, 240] as [Double]).enumerated().map { SpeedRun(at: Double($0.offset), down: $0.element, up: 60, ping: 12) })
}

// MARK: - Monitor

struct MonitorEntry: TimelineEntry {
  var date: Date
  var config: MonitorConfig
  var snap: MonitorSnapshot?
}

/// Pulse's monitor writes the snapshot and reloads this widget after checks
/// it runs in the app; the timeline re-reads it every 15 minutes.
struct MonitorProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> MonitorEntry { MonitorEntry(date: .now, config: MonitorConfig(), snap: .sample) }

  func snapshot(for config: MonitorConfig, in context: Context) async -> MonitorEntry {
    MonitorEntry(date: .now, config: config, snap: context.isPreview ? .sample : PulseStore.monitor ?? .sample)
  }

  func timeline(for config: MonitorConfig, in context: Context) async -> Timeline<MonitorEntry> {
    Timeline(entries: [MonitorEntry(date: .now, config: config, snap: PulseStore.monitor)], policy: .after(.now.addingTimeInterval(900)))
  }
}

struct MonitorWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: MonitorEntry

  var body: some View {
    Themed { p in content(p).pulseBackground(entry.config.background) }
      .widgetURL(PulseLink.open("/monitor"))
  }

  @ViewBuilder
  private func content(_ p: Palette) -> some View {
    let m = entry.snap
    let targets = m?.targets ?? []
    let down = m?.down ?? 0
    let degraded = targets.contains { $0.incident }
    let color = targets.isEmpty ? p.timeout : down > 0 ? p.error : degraded ? p.slow : p.fast
    let headline = targets.isEmpty ? "No targets" : down > 0 ? "\(down) down" : degraded ? "Degraded" : "All up"
    let sub = targets.isEmpty ? "Add targets in Pulse" : (m?.live == false ? "Paused · \(Fmt.ago(m?.date))" : "Checked \(Fmt.ago(m?.date))")
    switch family {
    case .accessoryInline:
      Text("\(Image(systemName: "heart.text.square")) \(headline) · \(Fmt.pct(m?.uptime, digits: 1))")
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          Text(targets.isEmpty ? "—" : "\(targets.count - down)/\(targets.count)").font(.system(size: 16, weight: .heavy, design: .rounded))
          Text("up").font(.system(size: 9))
        }
      }
      .widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text("Monitor · \(headline)").font(.headline).lineLimit(1).widgetAccentable()
        Text("\(Fmt.pct(m?.uptime, digits: 2)) uptime").font(.caption)
        Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    case .systemSmall:
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Badge(symbol: "heart.text.square.fill", bg: color, fg: p.surface, size: 26)
          Text("Monitor").font(.system(size: 13, weight: .bold)).foregroundStyle(p.onSurface)
        }
        Spacer(minLength: 0)
        Text(headline).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        if let u = m?.uptime { Text("\(Fmt.pct(u, digits: 2)) uptime").font(.system(size: 12, weight: .medium)).foregroundStyle(p.onSurface) }
        Text(sub).font(.system(size: 10)).foregroundStyle(p.muted).lineLimit(2)
      }
    default:
      let large = family == .systemLarge || family == .systemExtraLarge
      let blocks = large && entry.config.showBlocks
      let fit = family == .systemMedium ? 3 : blocks ? 6 : 9
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Badge(symbol: "heart.text.square.fill", bg: color, fg: p.surface)
          VStack(alignment: .leading, spacing: 0) {
            Text("Monitor · \(headline)").font(.system(size: 14, weight: .bold)).foregroundStyle(p.onSurface)
            Text(sub).font(.system(size: 10)).foregroundStyle(p.muted)
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          if let u = m?.uptime { Stat(value: Fmt.pct(u, digits: 2), caption: "uptime", palette: p) }
        }
        if targets.isEmpty {
          Spacer(minLength: 0)
          Text("Add a host to Monitor in Pulse to see its uptime and incidents here.").font(.system(size: 12)).foregroundStyle(p.muted)
        }
        ForEach(targets.prefix(fit), id: \.self) { t in
          let c = t.down ? p.error : t.incident ? p.slow : p.latency(t.ms)
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
              Circle().fill(c).frame(width: 8, height: 8)
              Text(t.name.isEmpty ? t.host : t.name).font(.system(size: 12, weight: .medium)).foregroundStyle(p.onSurface).lineLimit(1)
              Spacer(minLength: 4)
              Text(Fmt.pct(t.uptime)).font(.system(size: 11)).foregroundStyle(p.muted)
              Text(t.down ? "Down" : "\(Fmt.ms(t.ms)) ms").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(c)
                .frame(minWidth: 48, alignment: .trailing)
            }
            if blocks && !t.blocks.isEmpty { HourBlocks(blocks: t.blocks, palette: p) }
          }
        }
        if targets.count > fit { Text("+\(targets.count - fit) more").font(.system(size: 10)).foregroundStyle(p.muted) }
        Spacer(minLength: 0)
      }
    }
  }
}

struct MonitorWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKinds.monitor, intent: MonitorConfig.self, provider: MonitorProvider()) { entry in
      MonitorWidgetView(entry: entry)
    }
    .configurationDisplayName("Monitor")
    .description("What is up or down, uptime and the last 24 hours.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

extension MonitorSnapshot {
  static let sample = MonitorSnapshot(
    at: Date().timeIntervalSince1970 * 1000 - 60_000, live: true, uptime: 99.82, incidents: 0,
    targets: [
      MonitorTarget(name: "Router", host: "192.168.0.1", down: false, ms: 3, uptime: 100, incident: false, blocks: String(repeating: "1", count: 24)),
      MonitorTarget(name: "Cloudflare", host: "1.1.1.1", down: false, ms: 14, uptime: 99.9, incident: false, blocks: String(repeating: "1", count: 20) + "2111"),
      MonitorTarget(name: "Home server", host: "nas.local", down: false, ms: 6, uptime: 99.5, incident: false, blocks: String(repeating: "1", count: 18) + "311111"),
    ])
}
