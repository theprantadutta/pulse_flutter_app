import Foundation
import SwiftUI
import WidgetKit

// Data shared with the Flutter app through the App Group's UserDefaults.
// home_widget's `HomeWidget.saveWidgetData` writes the same keys from Dart
// (lib/services/widgets/home_widgets.dart); Android reads them in
// WidgetStore.kt. Every value is a JSON string.

enum PulseGroup {
  /// Must match PulseWidgets.appGroup in Dart and both targets' App Groups capability.
  static let id = "group.com.pranta.pulse"
  static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

enum PulseKeys {
  static let theme = "w.theme"
  static let targets = "w.targets"
  static let speed = "w.speed"
  static let monitor = "w.monitor"
  static let publicIp = "w.net.public"
  static let gateway = "w.gateway"
  static func ping(_ host: String) -> String { "w.ping.\(host.lowercased())" }
}

/// The router: resolved to the gateway the app last saw (iOS has no public API for it).
let gatewayHost = "gateway"

enum WidgetKinds {
  static let ping = "PulsePingWidget"
  static let multiPing = "PulseMultiPingWidget"
  static let speed = "PulseSpeedWidget"
  static let monitor = "PulseMonitorWidget"
  static let actions = "PulseActionsWidget"
  static let network = "PulseNetworkWidget"
}

struct PulseTarget: Codable, Hashable {
  var host: String
  var name: String?

  var title: String {
    if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
    return host == gatewayHost ? "Router" : host
  }
}

/// Recent replies to one host; lost replies are stored as -1.
struct PingSnapshot: Codable {
  var host: String
  var at: Double
  var samples: [Double]
  var error: String?

  var replies: [Double] { samples.filter { $0 >= 0 } }
  var last: Double? { samples.last.flatMap { $0 >= 0 ? $0 : nil } }
  var lastLost: Bool { (samples.last ?? 0) < 0 && !samples.isEmpty }
  var avg: Double? { replies.isEmpty ? nil : replies.reduce(0, +) / Double(replies.count) }
  var min: Double? { replies.min() }
  var max: Double? { replies.max() }
  var lossPct: Double? { samples.isEmpty ? nil : Double(samples.filter { $0 < 0 }.count) * 100 / Double(samples.count) }
  var jitter: Double? {
    let r = replies
    guard r.count > 1 else { return nil }
    return zip(r, r.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(r.count - 1)
  }
  var date: Date { Date(timeIntervalSince1970: at / 1000) }

  static let keep = 30
}

struct SpeedRun: Codable { var at: Double; var down: Double?; var up: Double?; var ping: Double? }

struct SpeedSnapshot: Codable {
  var at: Double
  var down: Double?
  var up: Double?
  var ping: Double?
  var jitter: Double?
  var server: String?
  var history: [SpeedRun]
  var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

struct MonitorTarget: Codable, Hashable {
  var name: String
  var host: String
  var down: Bool
  var ms: Double?
  var uptime: Double?
  var incident: Bool
  /// One char per hour, oldest first: 0 empty, 1 healthy, 2 degraded, 3 down.
  var blocks: String
}

struct MonitorSnapshot: Codable {
  var at: Double
  var live: Bool
  var uptime: Double?
  var incidents: Int
  var targets: [MonitorTarget]
  var down: Int { targets.filter(\.down).count }
  var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

struct PublicIp: Codable { var ip: String?; var isp: String?; var city: String?; var country: String? }

struct ThemePrefs: Codable {
  var accent: String = "PINK"
  var dynamic: Bool = false
  var mode: String = "system"
}

enum PulseStore {
  private static func decode<T: Decodable>(_ key: String, as: T.Type) -> T? {
    guard let s = PulseGroup.defaults.string(forKey: key), let d = s.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: d)
  }

  static func ping(_ host: String) -> PingSnapshot? { decode(PulseKeys.ping(host), as: PingSnapshot.self) }
  static var speed: SpeedSnapshot? { decode(PulseKeys.speed, as: SpeedSnapshot.self) }
  static var monitor: MonitorSnapshot? { decode(PulseKeys.monitor, as: MonitorSnapshot.self) }
  static var publicIp: PublicIp? { decode(PulseKeys.publicIp, as: PublicIp.self) }
  static var theme: ThemePrefs { decode(PulseKeys.theme, as: ThemePrefs.self) ?? ThemePrefs() }
  static var targets: [PulseTarget] { decode(PulseKeys.targets, as: [PulseTarget].self) ?? [] }
  static var gateway: String? {
    guard let s = decode(PulseKeys.gateway, as: String.self), !s.isEmpty else { return nil }
    return s
  }

  /// Appends a round of replies, keeping the last [PingSnapshot.keep].
  static func addPings(_ host: String, _ fresh: [Double], error: String?) {
    let old = ping(host)?.samples ?? []
    let snap = PingSnapshot(
      host: host, at: Date().timeIntervalSince1970 * 1000,
      samples: Array((old + fresh).suffix(PingSnapshot.keep)), error: error)
    if let d = try? JSONEncoder().encode(snap), let s = String(data: d, encoding: .utf8) {
      PulseGroup.defaults.set(s, forKey: PulseKeys.ping(host))
    }
  }
}

// MARK: - Formatting

enum Fmt {
  static func ms(_ v: Double?) -> String {
    guard let v, v >= 0 else { return "—" }
    if v < 1 { return "<1" }
    if v < 10 { return String(format: "%.1f", v) }
    return String(Int(v.rounded()))
  }

  static func mbps(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v < 10 ? String(format: "%.1f", v) : String(Int(v.rounded()))
  }

  static func pct(_ v: Double?, digits: Int = 1) -> String {
    guard let v else { return "—" }
    if v >= 99.995 { return "100%" }
    return String(format: "%.\(digits)f%%", v)
  }

  static func ago(_ date: Date?) -> String {
    guard let date else { return "never" }
    let s = Date().timeIntervalSince(date)
    if s < 45 { return "just now" }
    if s < 3600 { return "\(max(1, Int(s / 60))) min ago" }
    if s < 86_400 { return "\(Int(s / 3600)) h ago" }
    return "\(Int(s / 86_400)) d ago"
  }

  /// Hides most of an address unless the person chose to show it.
  static func mask(_ ip: String?) -> String {
    guard let ip, !ip.isEmpty else { return "—" }
    if ip.contains(":") { return ip.split(separator: ":").prefix(2).joined(separator: ":") + ":••••" }
    let p = ip.split(separator: ".")
    return p.count == 4 ? "\(p[0]).••.••.\(p[3])" : "••••"
  }
}

// MARK: - Links into the app

enum PulseLink {
  /// `homeWidget` marks the URL for home_widget, which forwards it to Dart (WidgetLink.parse).
  static func url(_ path: String, _ query: [String: String] = [:]) -> URL {
    var c = URLComponents()
    c.scheme = "pulse"
    c.host = path
    c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "homeWidget", value: nil)]
    return c.url ?? URL(string: "pulse://open?homeWidget")!
  }

  static func ping(_ t: PulseTarget) -> URL { url("ping", ["host": t.host, "name": t.title]) }
  static func open(_ route: String) -> URL { url("open", ["to": route]) }
}
