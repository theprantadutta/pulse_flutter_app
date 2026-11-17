import AppIntents
import SwiftUI
import WidgetKit

/// Pulse's widget extension: Home Screen and Lock Screen widgets (iOS 17+)
/// and, on iOS 18+, Control Center / Lock Screen controls.
@main
struct PulseWidgetsBundle: WidgetBundle {
  var body: some Widget {
    PingWidget()
    MultiPingWidget()
    SpeedWidget()
    MonitorWidget()
    NetworkWidget()
    ActionsWidget()
    if #available(iOS 18.0, *) {
      PulseSpeedControl()
      PulseToolControl()
    }
  }
}

// MARK: - Controls (iOS 18): Control Center, Lock Screen and the Action button

@available(iOS 18.0, *)
struct OpenPulseToolIntent: AppIntent {
  static var title: LocalizedStringResource = "Open a Pulse tool"
  static var description = IntentDescription("Opens Pulse on the tool you pick.")
  static var openAppWhenRun = true

  @Parameter(title: "Tool", default: .ping) var tool: PulseTool

  init() {}
  init(tool: PulseTool) { self.tool = tool }

  @MainActor
  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(tool.url))
  }
}

@available(iOS 18.0, *)
struct PulseSpeedControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "PulseSpeedControl") {
      ControlWidgetButton(action: OpenPulseToolIntent(tool: .speed)) {
        Label("Speed test", systemImage: "speedometer")
      }
    }
    .displayName("Run a speed test")
    .description("Opens Pulse and starts a speed test.")
  }
}

@available(iOS 18.0, *)
struct ToolControlConfig: ControlConfigurationIntent {
  static var title: LocalizedStringResource = "Pulse tool"
  @Parameter(title: "Tool", default: .ping) var tool: PulseTool
}

@available(iOS 18.0, *)
struct PulseToolControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    AppIntentControlConfiguration(kind: "PulseToolControl", intent: ToolControlConfig.self) { config in
      ControlWidgetButton(action: OpenPulseToolIntent(tool: config.tool)) {
        Label(config.tool.label, systemImage: config.tool.symbol)
      }
    }
    .displayName("Pulse tool")
    .description("Opens Ping, Traceroute, LAN scan or any other Pulse tool.")
  }
}
