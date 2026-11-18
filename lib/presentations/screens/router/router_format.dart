import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../services/net/router/drivers/router_driver.dart';

String fmtRate(double? bps) {
  if (bps == null) return '—';
  final (v, u) = splitRate(bps);
  return '$v $u';
}

/// ("12.5", "Mbps") — the number and unit apart, for big numbers.
(String, String) splitRate(double bps) {
  if (bps >= 1e9) return ((bps / 1e9).toStringAsFixed(2), 'Gbps');
  if (bps >= 1e6) return ((bps / 1e6).toStringAsFixed(bps >= 1e8 ? 0 : 1), 'Mbps');
  if (bps >= 1e3) return ((bps / 1e3).toStringAsFixed(0), 'kbps');
  return (bps.toStringAsFixed(0), 'bps');
}

String fmtUptime(Duration d) {
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}

String fmtBytes(int b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String linkLabel(RouterClient d) => switch (d.link) {
  ClientLink.wired => 'Wired',
  ClientLink.wifi2g => d.guest ? 'Guest · 2.4 GHz' : 'Wi-Fi 2.4 GHz',
  ClientLink.wifi5g => d.guest ? 'Guest · 5 GHz' : 'Wi-Fi 5 GHz',
  ClientLink.wifi6g => d.guest ? 'Guest · 6 GHz' : 'Wi-Fi 6 GHz',
  ClientLink.guest => 'Guest Wi-Fi',
  ClientLink.unknown => 'Connected',
};

/// "Strong" / "Good" / "Fair" / "Weak" from dBm.
String? signalLabel(int? dbm) {
  if (dbm == null || dbm >= 0) return null;
  if (dbm >= -55) return 'Strong signal';
  if (dbm >= -67) return 'Good signal';
  if (dbm >= -75) return 'Fair signal';
  return 'Weak signal';
}

PulseIcons deviceIcon(RouterClient d) {
  final k = '${d.kind ?? ''} ${d.name ?? ''}'.toLowerCase();
  bool has(List<String> w) => w.any(k.contains);
  if (has(['phone', 'mobile', 'iphone', 'android', 'galaxy', 'pixel', 'redmi'])) return PulseIcons.phone;
  if (has(['tablet', 'ipad', 'tab '])) return PulseIcons.tablet;
  if (has(['tv', 'chromecast', 'roku', 'firestick', 'fire tv'])) return PulseIcons.tv;
  if (has(['printer', 'print'])) return PulseIcons.printer;
  if (has(['camera', 'cam'])) return PulseIcons.camera;
  if (has(['speaker', 'echo', 'sonos', 'homepod', 'nest audio'])) return PulseIcons.speaker;
  if (has(['server', 'nas', 'synology'])) return PulseIcons.server;
  if (has(['router', 'mesh', 'extender', 'deco'])) return PulseIcons.router;
  if (has(['pc', 'laptop', 'desktop', 'macbook', 'computer', 'windows'])) return PulseIcons.laptop;
  return d.link == ClientLink.wired ? PulseIcons.lan : PulseIcons.wifi;
}

/// A device's badge: guest devices pink, wired lavender, Wi-Fi lime-ish.
Widget deviceBadge(BuildContext context, RouterClient d, {double size = 40}) {
  final c = context.colors;
  final (bg, fg) = d.guest
      ? (c.primaryContainer, c.onPrimaryContainer)
      : d.link == ClientLink.wired
      ? (c.secondaryContainer, c.onSecondaryContainer)
      : (c.tertiaryContainer, c.onTertiaryContainer);
  return PulseContainerBadge(
    shape: d.guest ? PulseShape.cookie9 : PulseShape.circle,
    icon: deviceIcon(d),
    color: bg,
    onColor: fg,
    size: size,
  );
}
