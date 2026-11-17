import Darwin
import Foundation

/// ICMP echo from the widget extension, no Flutter involved. iOS allows
/// unprivileged ICMP over SOCK_DGRAM sockets (as Apple's SimplePing does);
/// replies on IPv4 sockets arrive with their IP header, IPv6 ones without.
enum PulsePinger {
  struct Round { var samples: [Double]; var error: String? }

  /// Sends [count] echoes 200 ms apart; each waits up to [timeout] seconds.
  static func ping(_ host: String, count: Int = 4, timeout: Double = 1.5) async -> Round {
    let target = host == gatewayHost ? PulseStore.gateway : host
    guard let target else { return Round(samples: [], error: "Open Pulse once on this network to find the router") }
    return await Task.detached(priority: .userInitiated) { () -> Round in
      guard let addr = resolve(target) else {
        return Round(samples: Array(repeating: -1, count: count), error: "Can't resolve \(target)")
      }
      let v6 = addr.ss_family == sa_family_t(AF_INET6)
      let fd = socket(v6 ? AF_INET6 : AF_INET, SOCK_DGRAM, v6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
      guard fd >= 0 else { return Round(samples: Array(repeating: -1, count: count), error: "ICMP isn't available") }
      defer { close(fd) }
      var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
      setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
      let ident = UInt16.random(in: 1...UInt16.max)
      var samples: [Double] = []
      for seq in 0..<count {
        samples.append(echo(fd: fd, addr: addr, v6: v6, ident: ident, seq: UInt16(seq), timeout: timeout))
        if seq < count - 1 { usleep(200_000) }
      }
      return Round(samples: samples, error: nil)
    }.value
  }

  /// Pings each host in parallel and stores the replies for the widgets.
  static func refresh(_ hosts: [String], count: Int) async {
    await withTaskGroup(of: (String, Round).self) { group in
      for h in Set(hosts) { group.addTask { (h, await ping(h, count: count)) } }
      for await (h, r) in group { PulseStore.addPings(h, r.samples, error: r.error) }
    }
  }

  private static func resolve(_ host: String) -> sockaddr_storage? {
    var hints = addrinfo(ai_flags: AI_V4MAPPED_CFG | AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_DGRAM,
                         ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var res: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
    defer { freeaddrinfo(res) }
    // Prefer IPv4 when both exist, as the app's prober does on "auto".
    var pick: UnsafeMutablePointer<addrinfo>? = first
    var p: UnsafeMutablePointer<addrinfo>? = first
    while let cur = p {
      if cur.pointee.ai_family == AF_INET { pick = cur; break }
      p = cur.pointee.ai_next
    }
    guard let a = pick?.pointee.ai_addr, let len = pick?.pointee.ai_addrlen else { return nil }
    var ss = sockaddr_storage()
    withUnsafeMutableBytes(of: &ss) { dst in
      dst.copyMemory(from: UnsafeRawBufferPointer(start: a, count: Int(len)))
    }
    return ss
  }

  private static func checksum(_ data: [UInt8]) -> UInt16 {
    var sum: UInt32 = 0
    var i = 0
    while i + 1 < data.count {
      sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
      i += 2
    }
    if i < data.count { sum += UInt32(data[i]) << 8 }
    while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
    return ~UInt16(sum & 0xFFFF)
  }

  /// One echo; returns the round trip in ms, or -1 when lost.
  private static func echo(fd: Int32, addr: sockaddr_storage, v6: Bool, ident: UInt16, seq: UInt16, timeout: Double) -> Double {
    var packet = [UInt8](repeating: 0, count: 8 + 32)
    packet[0] = v6 ? 128 : 8  // echo request
    packet[4] = UInt8(ident >> 8); packet[5] = UInt8(ident & 0xFF)
    packet[6] = UInt8(seq >> 8); packet[7] = UInt8(seq & 0xFF)
    for i in 8..<packet.count { packet[i] = UInt8(i & 0xFF) }
    if !v6 {  // the kernel fills in the ICMPv6 checksum
      let c = checksum(packet)
      packet[2] = UInt8(c >> 8); packet[3] = UInt8(c & 0xFF)
    }
    var dest = addr
    let len = socklen_t(v6 ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
    let start = DispatchTime.now().uptimeNanoseconds
    let sent = withUnsafePointer(to: &dest) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, packet, packet.count, 0, $0, len) }
    }
    guard sent == packet.count else { return -1 }
    var buf = [UInt8](repeating: 0, count: 1500)
    while true {
      let n = recv(fd, &buf, buf.count, 0)
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
      if n <= 0 || elapsed > timeout * 1000 { return -1 }
      var off = 0
      if !v6, n > 0, buf[0] >> 4 == 4 { off = Int(buf[0] & 0x0F) * 4 }
      guard n >= off + 8 else { continue }
      let type = buf[off]
      let rseq = UInt16(buf[off + 6]) << 8 | UInt16(buf[off + 7])
      if type == (v6 ? 129 : 0) && rseq == seq { return elapsed }
    }
  }
}
