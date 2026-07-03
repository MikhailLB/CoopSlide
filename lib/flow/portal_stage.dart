import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/alert_hub.dart';
import '../core/net_sensor.dart';
import '../core/outbound_http.dart';
import '../core/session_store.dart';
import 'offline_gate.dart';

Future<void> warmPortalEngine() async {}

class PortalStage extends StatefulWidget {
  final String url;
  final SessionStore store;
  final AlertHub alerts;
  final NetSensor netSensor;

  const PortalStage({
    super.key,
    required this.url,
    required this.store,
    required this.alerts,
    required this.netSensor,
  });

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage> with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _spinning = true;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _offlineDebounce;
  bool _offlineVisible = false;
  String? _lastMainUrl;
  int _redirectAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(outboundHttp.agent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _spinning = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _spinning = false);
            _redirectAttempts = 0;
            _patchViewportInsets();
            _patchKeyboardFocus();
          },
          onWebResourceError: (err) {
            if (err.isForMainFrame != true) return;
            final blurb = err.description.toLowerCase();

            final loop = blurb.contains('too_many_redirects') ||
                blurb.contains('too many redirects') ||
                err.errorCode == -1007 ||
                err.errorCode == -9;
            if (loop && _lastMainUrl != null && _redirectAttempts < 3) {
              _redirectAttempts++;
              _web.loadRequest(Uri.parse(_lastMainUrl!));
              return;
            }

            if (mounted) setState(() => _spinning = true);

            final dnsFail = blurb.contains('name_not_resolved') ||
                blurb.contains('err_name_not_resolved') ||
                blurb.contains('internet_disconnected') ||
                blurb.contains('network_changed') ||
                err.errorCode == -105 ||
                err.errorCode == -106 ||
                err.errorCode == -21;

            if (dnsFail) {
              _routeOfflineDirect();
            } else {
              _routeOfflineIfNeeded();
            }
          },
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            final scheme = uri.scheme;
            if (scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'about' ||
                scheme == 'data' ||
                scheme == 'blob') {
              if (req.isMainFrame) _lastMainUrl = req.url;
              return NavigationDecision.navigate;
            }
            _openExternal(uri);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..enableZoom(false);

    _configureAndroidWebView();
    _web.loadRequest(Uri.parse(widget.url));

    widget.alerts.onWarmOpen = (url) {
      if (mounted) _web.loadRequest(Uri.parse(url));
    };

    _netSub = widget.netSensor.statusStream.listen((statuses) {
      final allDown = statuses.every((s) => s == ConnectivityResult.none);
      if (!allDown) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _routeOfflineDirect();
      });
    });
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  void _configureAndroidWebView() {
    if (!Platform.isAndroid) return;
    final platform = _web.platform;
    if (platform is! AndroidWebViewController) return;
    platform.setMediaPlaybackRequiresUserGesture(false);
    platform.setOnShowFileSelector(_pickFiles);
    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(platform, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (picked != null && picked.files.isNotEmpty) {
        return picked.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _routeOfflineIfNeeded() async {
    if (_offlineVisible) return;
    final ok = await widget.netSensor.isOnline();
    if (ok || !mounted) return;
    _routeOfflineDirect();
  }

  void _routeOfflineDirect() {
    if (_offlineVisible || !mounted) return;
    _offlineVisible = true;
    final current = _lastMainUrl ?? widget.url;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineGate(
          retryBuilder: (_) => PortalStage(
            url: current,
            store: widget.store,
            alerts: widget.alerts,
            netSensor: widget.netSensor,
          ),
        ),
      ),
    );
  }

  void _patchKeyboardFocus() {
    _web.runJavaScript('''
(function(){
  if(window.__csKb) return; window.__csKb=true;
  function isInput(el){return el&&(el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable);}
  function scrollActive(){
    var el=document.activeElement; if(!isInput(el)) return;
    el.scrollIntoView({behavior:'auto',block:'nearest'});
  }
  document.addEventListener('focusin',function(e){ if(isInput(e.target)) setTimeout(scrollActive,350); });
  if(window.visualViewport){
    var prev=window.visualViewport.height;
    window.visualViewport.addEventListener('resize',function(){
      var h=window.visualViewport.height;
      if(h<prev) setTimeout(scrollActive,120);
      prev=h;
    });
  }
})();
''');
  }

  void _patchViewportInsets() {
    _web.runJavaScript(r'''
(function(){
  if(window.__csInset) return; window.__csInset=true;
  var CSS_ID='__csInset';
  var CSS=':root{--safe-area-inset-top:0px!important;--safe-area-inset-bottom:0px!important;'
    +'--safe-area-inset-left:0px!important;--safe-area-inset-right:0px!important;}';
  function kbOpen(){
    if(!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }
  function apply(){
    if(kbOpen()) return;
    var head=document.head||document.documentElement; if(!head) return;
    var m=document.querySelector('meta[name="viewport"]');
    if(m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content')||'')){
      var c=(m.getAttribute('content')||'').replace(/,?\s*viewport-fit\s*=\s*\w+/ig,'').trim();
      m.setAttribute('content', c + (c?', ':'') + 'viewport-fit=contain');
    }
    var s=document.getElementById(CSS_ID);
    if(!s){ s=document.createElement('style'); s.id=CSS_ID; head.appendChild(s); }
    if(s.textContent!==CSS) s.textContent=CSS;
  }
  apply();
  setInterval(apply, 2500);
})();
''');
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _netSub?.cancel();
    _offlineDebounce?.cancel();
    widget.alerts.onWarmOpen = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // SafeArea keeps the WebView clear of system UI cutouts,
            // status bar and rounded corners in BOTH orientations
            // (previously landscape had top: 0 which let notches / camera
            // holes overlap the page content).
            SafeArea(
              top: true,
              bottom: true,
              left: true,
              right: true,
              child: WebViewWidget(controller: _web),
            ),
            if (_spinning)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFFA630),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
