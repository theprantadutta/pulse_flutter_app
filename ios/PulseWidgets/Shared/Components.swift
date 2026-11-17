import AppIntents
import SwiftUI
import WidgetKit

/// Bars for recent replies; lost ones are full-height track bars.
struct Sparkline: View {
  var samples: [Double]
  var palette: Palette
  var maxBars: Int = 24

  var body: some View {
    let values = Array(samples.suffix(maxBars))
    let peak = max(values.filter { $0 >= 0 }.max() ?? 1, 1)
    GeometryReader { geo in
      let slot = geo.size.width / CGFloat(max(maxBars, 1))
      let w = max(2, min(8, slot * 0.62))
      HStack(alignment: .bottom, spacing: max(1, slot - w)) {
        ForEach(Array(values.enumerated()), id: \.offset) { _, v in
          let lost = v < 0
          let h = lost ? geo.size.height : max(3, geo.size.height * (0.18 + 0.82 * v / peak))
          Capsule()
            .fill(lost ? palette.track : palette.latency(v))
            .frame(width: w, height: h)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
    .overlay {
      if values.isEmpty { Text("No replies yet").font(.caption2).foregroundStyle(palette.muted) }
    }
    .accessibilityLabel(values.isEmpty ? "No replies yet" : "Recent replies chart")
  }
}

struct Badge: View {
  var symbol: String
  var bg: Color
  var fg: Color
  var size: CGFloat = 28

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(fg)
      .frame(width: size, height: size)
      .background(Circle().fill(bg))
      .widgetAccentable()
  }
}

/// Round ↻ button that runs [RefreshPingIntent] in the background.
struct RefreshButton: View {
  var hosts: [String]
  var probes: Int
  var palette: Palette
  var size: CGFloat = 30

  var body: some View {
    Button(intent: RefreshPingIntent(hosts: hosts, probes: probes)) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: size * 0.45, weight: .bold))
        .foregroundStyle(palette.onSurface)
        .frame(width: size, height: size)
        .background(Circle().fill(palette.surfaceHigh))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Ping now")
  }
}

struct Stat: View {
  var value: String
  var caption: String
  var palette: Palette
  var color: Color?

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(color ?? palette.onSurface)
      Text(caption).font(.system(size: 10)).foregroundStyle(palette.muted)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }
}

/// The last 24 hours of a monitor target, one block per hour.
struct HourBlocks: View {
  var blocks: String
  var palette: Palette

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(blocks.suffix(24).enumerated()), id: \.offset) { _, c in
        RoundedRectangle(cornerRadius: 2)
          .fill(c == "1" ? palette.fast : c == "2" ? palette.slow : c == "3" ? palette.error : palette.track)
      }
    }
    .frame(height: 9)
  }
}

/// "14 ms" with a small unit.
struct BigNumber: View {
  var value: String
  var unit: String?
  var color: Color
  var size: CGFloat
  var palette: Palette

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 3) {
      Text(value)
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .foregroundStyle(color)
        .contentTransition(.numericText())
      if let unit { Text(unit).font(.system(size: max(10, size * 0.34), weight: .medium)).foregroundStyle(palette.muted) }
    }
    .lineLimit(1)
    .minimumScaleFactor(0.5)
  }
}
