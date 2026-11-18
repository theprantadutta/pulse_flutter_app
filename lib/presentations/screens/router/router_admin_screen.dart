import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/widgets/pulse/pulse.dart';
import '../../../providers/router_provider.dart';
import '../../../services/net/router/router_probe.dart';
import '../../navigation/destinations.dart';
import 'router_screen.dart' show editRouterLogin;

/// "Full router settings": the router's own admin page inside Pulse. Pulse
/// fills in the saved login (and answers HTTP Basic/Digest prompts with it),
/// offers to save a login typed into the page, and accepts the router's
/// self-signed certificate for its own address only. Windows and Linux have no
/// in-app web view, so there it opens the browser instead.
class RouterAdminScreen extends ConsumerWidget {
  const RouterAdminScreen({super.key});

  static bool get inApp => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(routerProfileProvider).value;
    if (profile == null) {
      return const PulsePage(
        title: 'Router settings',
        backTo: Routes.router,
        showBack: true,
        children: [
          SizedBox(height: 48),
          PulseEmptyState(
            title: 'No router here',
            message: 'Connect to Wi-Fi or Ethernet first.',
            icon: PulseIcons.router,
            shape: PulseShape.cookie9,
          ),
        ],
      );
    }
    if (!inApp) return _BrowserFallback(profile: profile);
    return _AdminWebView(profile: profile);
  }
}

class _AdminWebView extends ConsumerStatefulWidget {
  const _AdminWebView({required this.profile});
  final RouterProfile profile;

  @override
  ConsumerState<_AdminWebView> createState() => _AdminWebViewState();
}

class _AdminWebViewState extends ConsumerState<_AdminWebView> {
  late final WebViewController _web;
  double _progress = 0;
  String? _error;
  bool _filled = false;
  bool _offeredSave = false;
  String _host = '';

  RouterProfile get p => widget.profile;

  @override
  void initState() {
    super.initState();
    _host = p.adminUrl.host;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('PulseVault', onMessageReceived: (m) => _onTypedLogin(m.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (v) {
            if (mounted) setState(() => _progress = v / 100);
          },
          onUrlChange: (c) {
            final h = Uri.tryParse(c.url ?? '')?.host;
            if (h != null && h.isNotEmpty) _host = h;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onPageFinished: (_) => _afterLoad(),
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) {
              if (mounted) setState(() => _error = e.description);
            }
          },
          onHttpAuthRequest: _onHttpAuth,
          onSslAuthError: (e) {
            // Routers use self-signed certificates: trust them for the router's
            // own address only, never for any other site.
            _host == p.gateway || _host == p.adminUrl.host ? e.proceed() : e.cancel();
          },
          onNavigationRequest: (r) {
            final uri = Uri.tryParse(r.url);
            // Links that leave the LAN (vendor cloud, help pages) open in the browser.
            if (uri != null &&
                uri.hasScheme &&
                (uri.scheme == 'http' || uri.scheme == 'https') &&
                !_isLocal(uri.host)) {
              unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(p.adminUrl);
  }

  bool _isLocal(String host) {
    if (host == p.gateway || host == p.adminUrl.host) return true;
    final a = InternetAddress.tryParse(host);
    if (a == null) return host.endsWith('.local') || host.endsWith('.lan') || !host.contains('.');
    if (a.isLoopback || a.isLinkLocal) return true;
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4) {
      return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168);
    }
    return (b[0] & 0xfe) == 0xfc; // fc00::/7
  }

  Future<RouterCredential?> _saved() => RouterVault.read(p.id);

  Future<void> _onHttpAuth(HttpAuthRequest request) async {
    final saved = await _saved();
    if (saved != null) {
      request.onProceed(WebViewCredential(user: saved.username, password: saved.password));
      return;
    }
    if (!mounted) return request.onCancel();
    final user = TextEditingController();
    final pass = TextEditingController();
    var remember = false; // saving is opt-in
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Sign in to ${request.host}'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (request.realm != null)
                Text(request.realm!, style: context.type.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
              TextField(
                controller: user,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              CheckboxListTile(
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: const Text('Remember on this device'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign in')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final login = RouterCredential(user.text.trim(), pass.text);
      if (remember) {
        await RouterVault.write(p.id, login);
      } else {
        ref.read(sessionRouterLoginProvider.notifier).put(p.id, login);
      }
      ref.invalidate(routerCredentialProvider);
      request.onProceed(WebViewCredential(user: user.text.trim(), password: pass.text));
    } else {
      request.onCancel();
    }
    user.dispose();
    pass.dispose();
  }

  /// Hooks login forms (to offer saving what the person types) and fills the
  /// saved login into the first visible password field and the field before it.
  Future<void> _afterLoad() async {
    try {
      await _web.runJavaScript(_hookJs);
      final saved = await _saved();
      if (saved == null || saved.password.isEmpty) return;
      final r = await _web.runJavaScriptReturningResult(
        '$_fillJs(${jsonEncode(saved.username)}, ${jsonEncode(saved.password)})',
      );
      if ('$r'.contains('filled') && mounted && !_filled) {
        setState(() => _filled = true);
        showPulseToast(context, 'Filled in your saved login', icon: PulseIcons.check);
      }
    } on Object {
      // Pages without JavaScript access (rare) just don't get autofill.
    }
  }

  Future<void> _onTypedLogin(String message) async {
    if (_offeredSave) return;
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(message) as Map<String, dynamic>;
    } on Object {
      return;
    }
    final user = '${j['u'] ?? ''}'.trim();
    final pass = '${j['p'] ?? ''}';
    if (pass.isEmpty) return;
    final saved = await _saved();
    if (saved != null && saved.username == user && saved.password == pass) return;
    _offeredSave = true;
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          persist: false,
          content: Text(saved == null ? 'Save this router login in Pulse?' : 'Update the saved router login?'),
          action: SnackBarAction(
            label: 'Save',
            onPressed: () async {
              await RouterVault.write(p.id, RouterCredential(user, pass));
              ref.invalidate(routerCredentialProvider);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          context.canPop() ? context.pop() : context.go(Routes.router);
        }
      },
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    PulseBackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.router)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: context.type.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            p.adminUrl.toString(),
                            style: context.type.bodySmall!.copyWith(color: c.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    PulseIconButton(
                      icon: PulseIcons.shield,
                      tooltip: 'Router login',
                      onPressed: () async {
                        final current = await _saved();
                        if (!context.mounted) return;
                        await editRouterLogin(context, ref, p, current);
                        unawaited(_afterLoad());
                      },
                    ),
                    PulseIconButton(icon: PulseIcons.refresh, tooltip: 'Reload', onPressed: () => _web.reload()),
                    PulseIconButton(
                      icon: PulseIcons.export,
                      tooltip: 'Open in browser',
                      onPressed: () => launchUrl(p.adminUrl, mode: LaunchMode.externalApplication),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              SizedBox(
                height: 3,
                child: _progress < 1 ? LinearProgressIndicator(value: _progress, color: c.primary) : null,
              ),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: PulseErrorBanner(
                            title: "Couldn't open the router page",
                            message: '$_error\n\nCheck you are on the router\'s network.',
                            onRetry: () => _web.loadRequest(p.adminUrl),
                          ),
                        ),
                      )
                    : WebViewWidget(controller: _web),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Windows/Linux: no in-app web view, so open the browser and let the person
/// copy the saved login.
class _BrowserFallback extends ConsumerWidget {
  const _BrowserFallback({required this.profile});
  final RouterProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cred = ref.watch(routerCredentialProvider).value;
    final c = context.colors;
    return PulsePage(
      title: 'Router settings',
      backTo: Routes.router,
      showBack: true,
      children: [
        PulseCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name, style: context.type.titleLarge),
              const SizedBox(height: 6),
              Text(
                'On this computer the router page opens in your browser.',
                style: context.type.bodyMedium!.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              PulseButton(
                label: 'Open ${profile.adminUrl.host}',
                icon: PulseIcons.export,
                style: PulseButtonStyle.pink,
                onPressed: () => launchUrl(profile.adminUrl, mode: LaunchMode.externalApplication),
              ),
              if (cred != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (cred.username.isNotEmpty)
                      IntrinsicWidth(
                        child: PulseButton(
                          label: 'Copy username',
                          icon: PulseIcons.copy,
                          style: PulseButtonStyle.tonal,
                          size: PulseButtonSize.small,
                          onPressed: () => Clipboard.setData(ClipboardData(text: cred.username)),
                        ),
                      ),
                    IntrinsicWidth(
                      child: PulseButton(
                        label: 'Copy password',
                        icon: PulseIcons.copy,
                        style: PulseButtonStyle.tonal,
                        size: PulseButtonSize.small,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: cred.password));
                          showPulseToast(context, 'Password copied', icon: PulseIcons.copy);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Finds the visible password field (also inside same-origin frames, which
/// older router UIs use) and the text field before it, and sets both the way
/// a person typing would, so page scripts see the values.
const _fillJs = r'''
(function(u, p) {
  function vis(e) { return !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length); }
  var docs = [document];
  try { document.querySelectorAll('iframe,frame').forEach(function(f) { if (f.contentDocument) docs.push(f.contentDocument); }); } catch (e) {}
  function set(el, v) {
    var proto = Object.getPrototypeOf(el);
    var d = Object.getOwnPropertyDescriptor(proto, 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    d.set.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  for (var k = 0; k < docs.length; k++) {
    var d = docs[k];
    var inputs = Array.prototype.slice.call(d.querySelectorAll('input')).filter(vis);
    var pw = inputs.filter(function(i) { return (i.type || '').toLowerCase() === 'password'; })[0];
    if (!pw) continue;
    var idx = inputs.indexOf(pw), user = null;
    for (var j = idx - 1; j >= 0; j--) {
      var t = (inputs[j].type || 'text').toLowerCase();
      if (t === 'text' || t === 'email' || t === 'tel') { user = inputs[j]; break; }
    }
    if (user && u) set(user, u);
    set(pw, p);
    return 'filled';
  }
  return 'none';
})
''';

/// Posts what was typed into a login form to PulseVault when the person
/// submits it (button click, Enter or form submit), so Pulse can offer to save it.
const _hookJs = r'''
(function() {
  if (window.__pulseHooked) return;
  window.__pulseHooked = true;
  function vis(e) { return !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length); }
  function grab() {
    var docs = [document];
    try { document.querySelectorAll('iframe,frame').forEach(function(f) { if (f.contentDocument) docs.push(f.contentDocument); }); } catch (e) {}
    for (var k = 0; k < docs.length; k++) {
      var inputs = Array.prototype.slice.call(docs[k].querySelectorAll('input')).filter(vis);
      var pw = inputs.filter(function(i) { return (i.type || '').toLowerCase() === 'password'; })[0];
      if (!pw || !pw.value) continue;
      var idx = inputs.indexOf(pw), user = '';
      for (var j = idx - 1; j >= 0; j--) {
        var t = (inputs[j].type || 'text').toLowerCase();
        if (t === 'text' || t === 'email' || t === 'tel') { user = inputs[j].value; break; }
      }
      PulseVault.postMessage(JSON.stringify({ u: user, p: pw.value }));
      return;
    }
  }
  document.addEventListener('click', function(e) {
    if (e.target.closest && e.target.closest('button,input[type=submit],input[type=button],a,[role=button],.button,.btn')) grab();
  }, true);
  document.addEventListener('keydown', function(e) { if (e.key === 'Enter') grab(); }, true);
  document.addEventListener('submit', grab, true);
})();
''';
