import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Quick actions

struct ActionsEntry: TimelineEntry {
  var date: Date
  var config: ActionsConfig
}

struct ActionsProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> ActionsEntry { ActionsEntry(date: .now, config: ActionsConfig()) }
  func snapshot(for config: ActionsConfig, in context: Context) async -> ActionsEntry { ActionsEntry(date: .now, config: config) }
  func timeline(for config: ActionsConfig, in context: Context) async -> Timeline<ActionsEntry> {
    Timeline(entries: [ActionsEntry(date: .now, config: config)], policy: .never)
  }
}

struct ActionsWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: ActionsEntry

  var body: some View {
    Themed { p in content(p).pulseBackground(entry.config.background) }
  }

  @ViewBuilder
  private func content(_ p: Palette) -> some View {
    let tools = entry.config.shown
    switch family {
    case .accessoryCircular:
      let t = tools.first ?? .ping
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: t.symbol).font(.system(size: 22, weight: .semibold))
      }
      .widgetURL(t.url)
      .accessibilityLabel(t.label)
    default:
      let (cols, rows): (Int, Int) = switch family {
      case .systemSmall: (2, 2)
      case .systemMedium: (4, 2)
      case .systemExtraLarge: (6, 3)
      default: (3, 3)
      }
      let shown = Array(tools.prefix(cols * rows))
      let tones: [(Color, Color)] = [(p.hero, p.onHero), (p.secondaryContainer, p.onSecondaryContainer), (p.surfaceHigh, p.onSurface)]
      Grid(horizontalSpacing: 6, verticalSpacing: 6) {
        ForEach(0..<Int((Double(shown.count) / Double(cols)).rounded(.up)), id: \.self) { r in
          GridRow {
            ForEach(0..<cols, id: \.self) { c in
              let i = r * cols + c
              if i < shown.count {
                let (bg, fg) = tones[i % tones.count]
                Link(destination: shown[i].url) {
                  VStack(spacing: 4) {
                    Image(systemName: shown[i].symbol).font(.system(size: 20, weight: .semibold))
                    if family != .systemSmall || shown.count <= 4 {
                      Text(shown[i].label).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                  }
                  .foregroundStyle(fg)
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
                  .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bg))
                }
              } else {
                Color.clear
              }
            }
          }
        }
      }
    }
  }
}

struct ActionsWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKinds.actions, intent: ActionsConfig.self, provider: ActionsProvider()) { entry in
      ActionsWidgetView(entry: entry)
    }
    .configurationDisplayName("Quick actions")
    .description("Shortcuts to Ping, Speed test, Traceroute, LAN scan and more.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular])
  }
}

// MARK: - Network

struct NetworkEntry: TimelineEntry {
  var date: Date
  var config: NetworkConfig
  var now: NetworkNow
  var router: PingSnapshot?
  var publicIp: PublicIp?
}

struct NetworkProvider: AppIntentTimelineProvider {
  private static let sampleNow = NetworkNow(kind: "wifi", ssid: "Home", localIp: "192.168.0.24", ipv6: nil, vpn: false, expensive: false, constrained: false)

  func placeholder(in context: Context) -> NetworkEntry {
    NetworkEntry(date: .now, config: NetworkConfig(), now: Self.sampleNow, router: .sample, publicIp: PublicIp(ip: "203.0.113.7", isp: "Example ISP"))
  }

  func snapshot(for config: NetworkConfig, in context: Context) async -> NetworkEntry {
    if context.isPreview { return placeholder(in: context) }
    return NetworkEntry(date: .now, config: config, now: await NetworkNow.read(), router: PulseStore.ping(gatewayHost), publicIp: PulseStore.publicIp)
  }

  func timeline(for config: NetworkConfig, in context: Context) async -> Timeline<NetworkEntry> {
    let minutes = Double(config.interval.rawValue)
    let now = await NetworkNow.read()
    if now.kind == "wifi" || now.kind == "ethernet",
       Date().timeIntervalSince(PulseStore.ping(gatewayHost)?.date ?? .distantPast) >= (minutes - 1) * 60 {
      await PulsePinger.refresh([gatewayHost], count: 3)
    }
    let entry = NetworkEntry(date: .now, config: config, now: now, router: PulseStore.ping(gatewayHost), publicIp: PulseStore.publicIp)
    return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(minutes * 60)))
  }
}

struct NetworkWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: NetworkEntry

  var body: some View {
    Themed { p in content(p).pulseBackground(entry.config.background) }
      .widgetURL(PulseLink.open("/network"))
  }

  @ViewBuilder
  private func content(_ p: Palette) -> some View {
    let n = entry.now
    let symbol = switch n.kind {
    case "wifi": "wifi"
    case "cellular": "antenna.radiowaves.left.and.right"
    case "ethernet": "cable.connector"
    case "offline": "wifi.slash"
    default: "globe"
    }
    let kindName = switch n.kind {
    case "wifi": "Wi-Fi"
    case "cellular": "Mobile data"
    case "ethernet": "Ethernet"
    case "offline": "Offline"
    default: "Connected"
    }
    let title = n.ssid ?? kindName
    let subtitle = [n.ssid != nil ? kindName : nil, n.vpn ? "VPN on" : nil, n.constrained ? "Low Data Mode" : nil]
      .compactMap { $0 }.joined(separator: " · ")
    let local = entry.config.showLocalIp ? (n.localIp ?? "—") : Fmt.mask(n.localIp)
    let pub = entry.config.showPublicIp ? (entry.publicIp?.ip ?? "—") : Fmt.mask(entry.publicIp?.ip)
    let r = entry.router
    let routerText: String? = r.map { $0.lastLost ? "Lost" : "\(Fmt.ms($0.last)) ms" }
    let badgeBg = n.kind == "offline" ? p.error : p.hero
    let badgeFg = n.kind == "offline" ? p.surface : p.onHero

    switch family {
    case .accessoryInline:
      Text("\(Image(systemName: symbol)) \(title)")
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Label(title, systemImage: symbol).font(.headline).lineLimit(1).widgetAccentable()
        Text(local).font(.caption)
        if let routerText { Text("Router \(routerText)").font(.caption2).foregroundStyle(.secondary) }
      }
    case .systemSmall:
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Badge(symbol: symbol, bg: badgeBg, fg: badgeFg)
          Spacer(minLength: 4)
          RefreshButton(hosts: [gatewayHost], probes: 3, palette: p)
        }
        Spacer(minLength: 0)
        Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(p.onSurface).lineLimit(1)
        Text(local).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(p.onSurface).lineLimit(1).minimumScaleFactor(0.7)
        if let routerText {
          Text("Router · \(routerText)").font(.system(size: 10)).foregroundStyle(r?.lastLost == true ? p.error : p.muted)
        } else {
          Text(subtitle.isEmpty ? kindName : subtitle).font(.system(size: 10)).foregroundStyle(p.muted)
        }
      }
    default:
      let large = family == .systemLarge || family == .systemExtraLarge
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Badge(symbol: symbol, bg: badgeBg, fg: badgeFg)
          VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(p.onSurface)
            Text(subtitle.isEmpty ? kindName : subtitle).font(.system(size: 10)).foregroundStyle(p.muted)
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          RefreshButton(hosts: [gatewayHost], probes: 3, palette: p)
        }
        Spacer(minLength: 0)
        row(p, "Local IP", local, nil)
        if let gw = PulseStore.gateway { row(p, "Router", gw, routerText, extraColor: r?.lastLost == true ? p.error : p.latency(r?.last)) }
        row(p, "Public IP", pub, large ? entry.publicIp?.isp : nil)
        if large, let city = entry.publicIp?.city { row(p, "Location", [city, entry.publicIp?.country].compactMap { $0 }.joined(separator: ", "), nil) }
        if large, let v6 = n.ipv6 { row(p, "IPv6", entry.config.showLocalIp ? v6 : Fmt.mask(v6), nil) }
        if large { Spacer(minLength: 0) }
      }
    }
  }

  private func row(_ p: Palette, _ k: String, _ v: String, _ extra: String?, extraColor: Color? = nil) -> some View {
    HStack(spacing: 8) {
      Text(k).font(.system(size: 11)).foregroundStyle(p.muted).frame(width: 64, alignment: .leading)
      Text(v).font(.system(size: 12, weight: .medium)).foregroundStyle(p.onSurface).lineLimit(1).minimumScaleFactor(0.7)
      Spacer(minLength: 4)
      if let extra { Text(extra).font(.system(size: 11, weight: .medium)).foregroundStyle(extraColor ?? p.muted).lineLimit(1) }
    }
  }
}

struct NetworkWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKinds.network, intent: NetworkConfig.self, provider: NetworkProvider()) { entry in
      NetworkWidgetView(entry: entry)
    }
    .configurationDisplayName("Network")
    .description("Your connection: Wi-Fi, local and public address, and router latency.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
  }
}
