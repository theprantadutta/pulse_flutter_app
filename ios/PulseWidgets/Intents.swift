import AppIntents
import WidgetKit

// Per-widget settings live in each widget's App Intent configuration (the
// "Edit Widget" sheet), and interactive buttons run intents in this
// extension (iOS 17+). Options mirror the Android configure screen.

enum CardStyle: String, AppEnum {
  case solid, translucent, clear
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
  static var caseDisplayRepresentations: [CardStyle: DisplayRepresentation] = [
    .solid: "Solid", .translucent: "Translucent", .clear: "Clear",
  ]
}

enum RefreshInterval: Int, AppEnum {
  case m15 = 15, m30 = 30, h1 = 60, h3 = 180
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Refresh"
  static var caseDisplayRepresentations: [RefreshInterval: DisplayRepresentation] = [
    .m15: "Every 15 minutes", .m30: "Every 30 minutes", .h1: "Every hour", .h3: "Every 3 hours",
  ]
}

/// Tools the Quick actions widget opens. Raw values match WidgetTool in Dart.
enum PulseTool: String, AppEnum, CaseIterable {
  case ping, speed, trace, lan, geo, ports, loss, monitor, network, history
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tool"
  static var caseDisplayRepresentations: [PulseTool: DisplayRepresentation] = [
    .ping: "Ping", .speed: "Speed test", .trace: "Traceroute", .lan: "LAN scan", .geo: "Geo IP",
    .ports: "Port scan", .loss: "Packet loss", .monitor: "Monitor", .network: "Network", .history: "History",
  ]

  var label: String {
    switch self {
    case .ping: "Ping"
    case .speed: "Speed"
    case .trace: "Trace"
    case .lan: "LAN"
    case .geo: "Geo IP"
    case .ports: "Ports"
    case .loss: "Loss"
    case .monitor: "Monitor"
    case .network: "Network"
    case .history: "History"
    }
  }

  var symbol: String {
    switch self {
    case .ping: "waveform.path.ecg"
    case .speed: "speedometer"
    case .trace: "point.topleft.down.to.point.bottomright.curvepath"
    case .lan: "network"
    case .geo: "globe"
    case .ports: "rectangle.connected.to.line.below"
    case .loss: "chart.bar.xaxis"
    case .monitor: "heart.text.square"
    case .network: "wifi"
    case .history: "clock.arrow.circlepath"
    }
  }

  var url: URL {
    switch self {
    case .ping: PulseLink.open("/ping")
    case .speed: PulseLink.url("speed", ["run": "1"])
    case .trace: PulseLink.open("/traceroute")
    case .lan: PulseLink.open("/lan")
    case .geo: PulseLink.open("/geo")
    case .ports: PulseLink.open("/ports")
    case .loss: PulseLink.open("/loss")
    case .monitor: PulseLink.open("/monitor")
    case .network: PulseLink.open("/network")
    case .history: PulseLink.open("/history")
    }
  }

  static let defaults: [PulseTool] = [.ping, .speed, .trace, .lan, .geo, .ports, .loss, .monitor]
}

/// A host to ping: the router, well-known resolvers, Pulse's saved targets,
/// or anything typed into the search field.
struct PulseHostEntity: AppEntity {
  var id: String  // the host
  var name: String?

  var target: PulseTarget { PulseTarget(host: id, name: name) }

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Host"
  static var defaultQuery = PulseHostQuery()

  var displayRepresentation: DisplayRepresentation {
    let t = target
    return DisplayRepresentation(
      title: "\(t.title)",
      subtitle: id == gatewayHost ? "Your current router" : (t.title == id ? nil : "\(id)"))
  }

  static let router = PulseHostEntity(id: gatewayHost, name: "Router")
  static let cloudflare = PulseHostEntity(id: "1.1.1.1", name: "Cloudflare")
  static let google = PulseHostEntity(id: "8.8.8.8", name: "Google")
  static let quad9 = PulseHostEntity(id: "9.9.9.9", name: "Quad9")
}

struct PulseHostQuery: EntityStringQuery {
  private func all() -> [PulseHostEntity] {
    var seen = Set<String>()
    let builtIn = [PulseHostEntity.router, .cloudflare, .google, .quad9]
    let saved = PulseStore.targets.map { PulseHostEntity(id: $0.host, name: $0.name) }
    return (builtIn + saved).filter { seen.insert($0.id.lowercased()).inserted }
  }

  func entities(for identifiers: [String]) async throws -> [PulseHostEntity] {
    let known = all()
    return identifiers.map { id in known.first { $0.id.caseInsensitiveCompare(id) == .orderedSame } ?? PulseHostEntity(id: id) }
  }

  func suggestedEntities() async throws -> [PulseHostEntity] { all() }

  /// The Ping widget's starting host. (`@Parameter(default:)` only takes
  /// literals, so an entity default has to come from the query.)
  func defaultResult() async -> PulseHostEntity? { .cloudflare }

  /// Typing a host offers it as-is, so any address can be picked.
  func entities(matching string: String) async throws -> [PulseHostEntity] {
    let q = string.trimmingCharacters(in: .whitespaces)
    let hits = all().filter { $0.id.localizedCaseInsensitiveContains(q) || ($0.name ?? "").localizedCaseInsensitiveContains(q) }
    if q.isEmpty || hits.contains(where: { $0.id.caseInsensitiveCompare(q) == .orderedSame }) { return hits }
    return [PulseHostEntity(id: q)] + hits
  }
}

// MARK: - Widget configurations

struct PingConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Ping"
  static var description = IntentDescription("Live latency for one host.")

  @Parameter(title: "Host") var host: PulseHostEntity?
  @Parameter(title: "Refresh", default: .m30) var interval: RefreshInterval
  @Parameter(title: "Pings per refresh", default: 4, inclusiveRange: (1, 10)) var probes: Int
  @Parameter(title: "Reply chart", default: true) var showChart: Bool
  @Parameter(title: "Background", default: .solid) var background: CardStyle

  var target: PulseTarget { (host ?? .cloudflare).target }
}

struct MultiPingConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Multi-host ping"
  static var description = IntentDescription("Router, DNS and servers side by side.")

  @Parameter(
    title: "Hosts",
    size: [.systemSmall: 3, .systemMedium: 4, .systemLarge: 6, .systemExtraLarge: 6, .accessoryRectangular: 3])
  var hosts: [PulseHostEntity]  // empty until edited: `targets` falls back to the four defaults
  @Parameter(title: "Refresh", default: .m30) var interval: RefreshInterval
  @Parameter(title: "Pings per refresh", default: 4, inclusiveRange: (1, 10)) var probes: Int
  @Parameter(title: "Reply charts", default: true) var showChart: Bool
  @Parameter(title: "Background", default: .solid) var background: CardStyle

  var targets: [PulseTarget] { hosts.isEmpty ? [PulseHostEntity.router, .cloudflare, .google, .quad9].map(\.target) : hosts.map(\.target) }
}

struct SpeedConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Speed test"
  static var description = IntentDescription("Your latest result and a button to run a new test.")
  @Parameter(title: "Recent tests chart", default: true) var showHistory: Bool
  @Parameter(title: "Background", default: .solid) var background: CardStyle
}

struct MonitorConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Monitor"
  static var description = IntentDescription("What is up or down, uptime and the last 24 hours.")
  @Parameter(title: "Last 24 hours", default: true) var showBlocks: Bool
  @Parameter(title: "Background", default: .solid) var background: CardStyle
}

struct ActionsConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Quick actions"
  static var description = IntentDescription("Shortcuts into the tools you use most.")
  @Parameter(title: "Shortcuts", default: [.ping, .speed, .trace, .lan, .geo, .ports, .loss, .monitor]) var tools: [PulseTool]
  @Parameter(title: "Background", default: .solid) var background: CardStyle

  var shown: [PulseTool] { tools.isEmpty ? PulseTool.defaults : tools }
}

struct NetworkConfig: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Network"
  static var description = IntentDescription("Wi-Fi, addresses, router latency and DNS.")
  @Parameter(title: "Show local addresses", default: true) var showLocalIp: Bool
  @Parameter(title: "Show public IP address", default: false) var showPublicIp: Bool
  @Parameter(title: "Refresh", default: .m30) var interval: RefreshInterval
  @Parameter(title: "Background", default: .solid) var background: CardStyle
}

// MARK: - Interactive actions

/// The ↻ button: pings the widget's hosts right here in the extension, then
/// WidgetKit reloads the widget.
struct RefreshPingIntent: AppIntent {
  static var title: LocalizedStringResource = "Refresh ping"
  static var isDiscoverable = false

  @Parameter(title: "Hosts") var hosts: String
  @Parameter(title: "Pings", default: 4) var probes: Int

  init() {}

  init(hosts: [String], probes: Int) {
    self.hosts = hosts.joined(separator: ",")
    self.probes = probes
  }

  func perform() async throws -> some IntentResult {
    let list = hosts.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    await PulsePinger.refresh(list, count: max(1, min(probes, 10)))
    return .result()
  }
}
