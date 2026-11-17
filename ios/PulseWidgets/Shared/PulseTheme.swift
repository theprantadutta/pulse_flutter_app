import SwiftUI
import WidgetKit

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: 1)
  }
}

/// Widget colours: Pulse's plum surfaces with the accent picked in Settings
/// (same hex values as lib/core/theme/pulse_theme.dart). Follows the system
/// appearance unless Pulse is set to Light or Dark.
struct Palette {
  var surface: Color
  var surfaceHigh: Color
  var onSurface: Color
  var muted: Color
  var primary: Color
  var onPrimary: Color
  var hero: Color
  var onHero: Color
  var secondary: Color
  var secondaryContainer: Color
  var onSecondaryContainer: Color
  var fast: Color
  var medium: Color
  var slow: Color
  var timeout: Color
  var error: Color
  var track: Color

  /// < 10 ms fast, ≤ 40 ms medium, slower or lost slow (as in the app).
  func latency(_ ms: Double?) -> Color {
    guard let ms, ms >= 0 else { return timeout }
    if ms < 10 { return fast }
    if ms <= 40 { return medium }
    return slow
  }

  private struct Family {
    var darkPrimary, darkOnPrimary, darkContainer, lightPrimary, lightContainer, lightOnContainer, fixedDim, onFixed: UInt32
  }

  private static let families: [String: Family] = [
    "PINK": Family(darkPrimary: 0xFFAFD0, darkOnPrimary: 0x5A1335, darkContainer: 0x7A2950, lightPrimary: 0x8E3A60, lightContainer: 0xFFD9E6, lightOnContainer: 0x3B0720, fixedDim: 0xFFAFD0, onFixed: 0x3B0720),
    "LAVENDER": Family(darkPrimary: 0xDDBCFF, darkOnPrimary: 0x3A1F57, darkContainer: 0x4B3466, lightPrimary: 0x6B4F8A, lightContainer: 0xF0DBFF, lightOnContainer: 0x25074A, fixedDim: 0xDDBCFF, onFixed: 0x25074A),
    "LIME": Family(darkPrimary: 0xCDEB74, darkOnPrimary: 0x2B3700, darkContainer: 0x3F5100, lightPrimary: 0x4A6200, lightContainer: 0xCDEB74, lightOnContainer: 0x141F00, fixedDim: 0xCDEB74, onFixed: 0x141F00),
    "BLUE": Family(darkPrimary: 0xA8C7FF, darkOnPrimary: 0x003062, darkContainer: 0x1F4778, lightPrimary: 0x3A5F94, lightContainer: 0xD6E3FF, lightOnContainer: 0x001B3E, fixedDim: 0xA8C7FF, onFixed: 0x001B3E),
  ]

  static func resolve(_ scheme: ColorScheme) -> Palette {
    let t = PulseStore.theme
    let dark: Bool = t.mode == "dark" ? true : t.mode == "light" ? false : scheme == .dark
    let f = families[t.accent] ?? families["PINK"]!
    func c(_ light: UInt32, _ darkV: UInt32) -> Color { Color(hex: dark ? darkV : light) }
    return Palette(
      surface: c(0xFFF7FA, 0x19121D),
      surfaceHigh: c(0xF1E4EA, 0x2F2535),
      onSurface: c(0x21181E, 0xF3E5F4),
      muted: c(0x524349, 0xD3C2D6),
      primary: c(f.lightPrimary, f.darkPrimary),
      onPrimary: c(0xFFFFFF, f.darkOnPrimary),
      hero: c(f.lightContainer, f.fixedDim),
      onHero: c(f.lightOnContainer, f.onFixed),
      secondary: c(0x6B4F8A, 0xDDBCFF),
      secondaryContainer: c(0xF0DBFF, 0x4B3466),
      onSecondaryContainer: c(0x25074A, 0xF0DBFF),
      fast: c(0x4F6B00, 0xCDEB74),
      medium: c(0x72519C, 0xDDBCFF),
      slow: c(0xB0306A, 0xFFAFD0),
      timeout: c(0x847379, 0x9C8BA0),
      error: c(0xBA1A1A, 0xFFB4AB),
      track: c(0xEBDEE4, 0x3A2F40))
  }
}

/// Reads the palette from the environment so every view follows light/dark.
struct Themed<Content: View>: View {
  @Environment(\.colorScheme) private var scheme
  let content: (Palette) -> Content
  var body: some View { content(Palette.resolve(scheme)) }
}

/// The widget's card. "Translucent" and "Clear" let the wallpaper show
/// through; tinted and clear Home Screen modes (iOS 18) drop it anyway.
struct PulseBackground: ViewModifier {
  @Environment(\.colorScheme) private var scheme
  var style: CardStyle

  func body(content: Content) -> some View {
    let p = Palette.resolve(scheme)
    content.containerBackground(for: .widget) {
      switch style {
      case .solid: p.surface
      case .translucent: p.surface.opacity(0.78)
      case .clear: Color.clear
      }
    }
  }
}

extension View {
  func pulseBackground(_ style: CardStyle) -> some View { modifier(PulseBackground(style: style)) }
}
