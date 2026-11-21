import Darwin
import Foundation
import Network
import NetworkExtension

/// The connection right now, read in the widget extension each time the
/// Network widget's timeline is built.
struct NetworkNow {
  var kind: String  // wifi, cellular, ethernet, offline, other
  var ssid: String?
  var localIp: String?
  var ipv6: String?
  var vpn: Bool
  var expensive: Bool
  var constrained: Bool

  static func read() async -> NetworkNow {
    let path = await currentPath()
    let kind: String
    if path?.status != .satisfied {
      kind = "offline"
    } else if path?.usesInterfaceType(.wifi) == true {
      kind = "wifi"
    } else if path?.usesInterfaceType(.cellular) == true {
      kind = "cellular"
    } else if path?.usesInterfaceType(.wiredEthernet) == true {
      kind = "ethernet"
    } else {
      kind = "other"
    }
    let (v4, v6, vpn) = addresses(preferWifi: kind != "cellular")
    // Needs the "Access Wi-Fi Information" entitlement on the extension and
    // location permission granted to Pulse; otherwise nil (shown as "Wi-Fi").
    var ssid: String?
    if kind == "wifi" { ssid = await NEHotspotNetwork.fetchCurrent()?.ssid }
    return NetworkNow(
      kind: kind, ssid: ssid, localIp: v4, ipv6: v6, vpn: vpn,
      expensive: path?.isExpensive ?? false, constrained: path?.isConstrained ?? false)
  }

  private static func currentPath() async -> Network.NWPath? {
    await withCheckedContinuation { (cont: CheckedContinuation<Network.NWPath?, Never>) in
      let monitor = NWPathMonitor()
      let queue = DispatchQueue(label: "pulse.widgets.path")
      // A class box: the handlers below are @Sendable, so they can't mutate a
      // captured var. Both run on the same serial queue.
      final class Once { var done = false }
      let once = Once()
      monitor.pathUpdateHandler = { path in
        guard !once.done else { return }
        once.done = true
        monitor.cancel()
        cont.resume(returning: path)
      }
      monitor.start(queue: queue)
      queue.asyncAfter(deadline: .now() + 1.5) {
        guard !once.done else { return }
        once.done = true
        monitor.cancel()
        cont.resume(returning: nil)
      }
    }
  }

  /// IPv4/IPv6 of Wi-Fi (en0) or cellular (pdp_ip0), and whether a VPN tunnel is up.
  private static func addresses(preferWifi: Bool) -> (String?, String?, Bool) {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return (nil, nil, false) }
    defer { freeifaddrs(ifap) }
    var v4: [String: String] = [:]
    var v6: [String: String] = [:]
    var vpn = false
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = p {
      let name = String(cString: cur.pointee.ifa_name)
      let flags = Int32(cur.pointee.ifa_flags)
      if let sa = cur.pointee.ifa_addr, flags & IFF_UP != 0 {
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") {
          if sa.pointee.sa_family == sa_family_t(AF_INET) { vpn = true }
        }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(sa.pointee.sa_family == sa_family_t(AF_INET6) ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        if getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
          let s = String(cString: host)
          if sa.pointee.sa_family == sa_family_t(AF_INET) {
            v4[name] = s
          } else if sa.pointee.sa_family == sa_family_t(AF_INET6), !s.hasPrefix("fe80") {
            v6[name] = s.components(separatedBy: "%").first
          }
        }
      }
      p = cur.pointee.ifa_next
    }
    let order = preferWifi ? ["en0", "en1", "pdp_ip0"] : ["pdp_ip0", "en0"]
    let a = order.compactMap { v4[$0] }.first
    let b = order.compactMap { v6[$0] }.first
    return (a, b, vpn)
  }
}
