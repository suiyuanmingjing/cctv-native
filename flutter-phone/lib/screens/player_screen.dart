import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/app_colors.dart';
import '../core/formatters.dart';
import '../core/native_system.dart';
import '../core/preferences.dart';
import '../models/channel.dart';
import '../models/video_state.dart';
import '../widgets/channel_panel.dart';
import '../widgets/settings_sheet.dart';

/// 播放页：系统 Chrome 内核 WebView + Flutter 原生播放器控制层。
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
  });

  final List<Channel> channels;
  final int initialIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  late final List<Channel> _channels;
  late int _index;
  late Channel _channel;

  WebViewController? _web;
  String _script = '';
  String _webViewVersion = '';
  String _appVersion = '1.0.0';

  VideoState _video = VideoState.empty;
  bool _initialLoading = true;
  bool _pageLoaded = false;
  int _progress = 0;
  String? _error;
  bool _autoplayBlocked = false;

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _drawerOpen = false;
  bool _autoFullscreen = true;
  bool _keepScreenOn = true;
  bool _didAutoFullscreen = false;
  bool _resumeAfterBackground = false;
  bool _pausedByFocus = false;

  double _volume = 0.5;
  double _brightness = 0.5;
  bool _muted = false;
  bool _fitCover = false;
  bool _userPaused = false;
  bool _appInBackground = false;
  final List<Timer> _autoplayTimers = <Timer>[];
  bool _volumeDragging = false;
  double _volumeBase = 0.5;
  double _brightnessBase = 0.5;
  String? _gestureSide;

  bool _hudVisible = false;
  _HudKind _hudKind = _HudKind.volume;
  double _hudValue = 0;

  final ScrollController _portraitScroll = ScrollController();

  Timer? _hideTimer;
  Timer? _autoFullscreenTimer;
  Timer? _hudTimer;
  int _lastVolumeSetMs = 0;
  int _lastBrightnessSetMs = 0;
  int _lastVolumeSyncMs = 0;

  bool get _showLoading => _initialLoading && _error == null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _channels = widget.channels;
    _index = _channels.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _channels.length - 1).toInt();
    _channel = _channels.first;
    if (_index > 0 && _index < _channels.length) {
      _channel = _channels[_index];
    }

    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    NativeSystem.setMethodCallHandler(_onNativeMethodCall);
    unawaited(NativeSystem.requestAudioFocus());

    _web = WebViewController();
    unawaited(_init());
  }

  Future<void> _init() async {
    final results = await Future.wait<Object?>([
      AppPreferences.autoFullscreen(),
      AppPreferences.keepScreenOn(),
      NativeSystem.getVolume(),
      NativeSystem.getBrightness(),
      NativeSystem.webViewVersion(),
      NativeSystem.appVersion(),
      rootBundle.loadString('assets/js/cctv_native.js'),
    ]);
    if (!mounted) return;

    setState(() {
      _autoFullscreen = results[0] as bool;
      _keepScreenOn = results[1] as bool;
      _volume = (results[2] as double).clamp(0.0, 1.0);
      _brightness = (results[3] as double).clamp(0.01, 1.0);
      _webViewVersion = results[4] as String;
      _appVersion = results[5] as String;
      _script = results[6] as String;
    });

    await NativeSystem.setKeepScreenOn(_keepScreenOn);
    if (!mounted) return;
    await _configureWebView();
  }

  Future<void> _configureWebView() async {
    final web = _web;
    if (web == null) return;

    await web.setJavaScriptMode(JavaScriptMode.unrestricted);
    await web.setBackgroundColor(Colors.black);
    await web.setUserAgent(_desktopUserAgent);
    await web.addJavaScriptChannel(
      'CctvEvents',
      onMessageReceived: _onJavaScriptMessage,
    );

    final platform = web.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
      await platform.setUseWideViewPort(false);
      await platform.enableZoom(false);
      await platform.setOverScrollMode(WebViewOverScrollMode.never);
      await platform.setTextZoom(100);
      await platform.setVerticalScrollBarEnabled(false);
      await platform.setHorizontalScrollBarEnabled(false);
    }

    await web.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            _pageLoaded = false;
          });
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() => _pageLoaded = true);
          await _injectScript();
        },
        onWebResourceError: (error) {
          if (!mounted) return;
          if (error.isForMainFrame != true) return;
          final description = error.description;
          if (description.contains('ERR_ABORTED') ||
              description.contains('ERR_BLOCKED_BY_CLIENT')) {
            return;
          }
          setState(() {
            _error = '网络错误：$description';
            _initialLoading = false;
          });
        },
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          return _shouldAllowNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    );

    await _loadChannel();
  }

  bool _shouldAllowNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    const allowedSchemes = {'http', 'https', 'about', 'data', 'blob'};
    if (!allowedSchemes.contains(uri.scheme)) return false;
    if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      return true;
    }
    final host = uri.host.toLowerCase();
    return host == 'tv.cctv.com' && uri.path.startsWith('/live/');
  }

  Future<void> _loadChannel() async {
    final web = _web;
    if (web == null || _channels.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _initialLoading = true;
      _progress = 0;
      _pageLoaded = false;
      _video = VideoState.empty;
      _error = null;
      _autoplayBlocked = false;
      _controlsVisible = true;
      _didAutoFullscreen = _isFullscreen;
      _muted = false;
      _userPaused = false;
    });

    unawaited(AppPreferences.setLastChannelId(_channel.id));
    _startHideTimer();
    await web.loadRequest(Uri.parse(_channel.webUrl));
  }

  Future<void> _injectScript() async {
    final web = _web;
    if (web == null || _script.isEmpty) return;
    const prefix =
        'window.__CCTV_CONFIG__ = {autoPlayMs: 15000, noVideoMs: 20000};\n';
    try {
      await web.runJavaScript(prefix + _script);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      // 第二次执行会走脚本内的 refresh 分支，处理播放器延迟创建的情况。
      await web.runJavaScript(prefix + _script);
      if (_fitCover) {
        await web.runJavaScript(
          'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.setFit("cover");',
        );
      }
      _scheduleAutoplayKicks();
    } catch (_) {
      // 页面仍在跳转时注入失败很正常，下一次 onPageFinished 会重试。
    }
  }

  void _scheduleAutoplayKicks() {
    for (final t in _autoplayTimers) {
      t.cancel();
    }
    _autoplayTimers.clear();
    for (final ms in <int>[600, 1600, 3200, 6000, 10000]) {
      _autoplayTimers.add(Timer(Duration(milliseconds: ms), () {
        if (!mounted || _userPaused || _appInBackground || _error != null) {
          return;
        }
        unawaited(_web?.runJavaScript(
          'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.autoplay();',
        ));
      }));
    }
  }
  void _onJavaScriptMessage(JavaScriptMessage message) {
    if (!mounted) return;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = payload['type'] as String? ?? '';
    final data = (payload['data'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    switch (type) {
      case 'state':
        _applyVideoState(VideoState.fromJson(data));
        break;
      case 'ready':
        _applyVideoState(VideoState.fromJson(data));
        _onFirstPicture();
        break;
      case 'playing':
        _onPlaying();
        break;
      case 'paused':
        _onPaused();
        break;
      case 'videoError':
        _onVideoError((data['message'] as String?) ?? '播放器错误');
        break;
      case 'noVideo':
        _onNoVideo((data['siteMessage'] as String?) ?? '');
        break;
      case 'autoplayBlocked':
        _onAutoplayBlocked();
        break;
      case 'tap':
        _toggleControls();
        break;
      case 'doubleTap':
        unawaited(_togglePlay());
        _wakeControls();
        break;
      case 'gesture':
        _onGesture(data);
        break;
      case 'openChannels':
        _openDrawer();
        break;
      case 'ended':
        _onPaused();
        break;
      default:
        break;
    }
  }

  void _applyVideoState(VideoState next) {
    if (!mounted) return;
    final hadPicture = _video.hasPicture;
    setState(() {
      _video = next;
      _muted = next.muted;
      if (next.hasPicture) {
        _initialLoading = false;
        _error = null;
        _autoplayBlocked = false;
      }
      if (next.error.isNotEmpty) {
        _error = next.error;
        _initialLoading = false;
        _controlsVisible = true;
      }
    });

    if (next.hasPicture && !hadPicture) {
      _onFirstPicture();
    }

    if (next.paused) {
      _hideTimer?.cancel();
    } else if (_controlsVisible && !(_hideTimer?.isActive ?? false)) {
      _startHideTimer();
    }
  }

  void _onFirstPicture() {
    if (!mounted) return;
    if (_initialLoading) {
      setState(() => _initialLoading = false);
    }
    _scheduleAutoFullscreen();
    unawaited(NativeSystem.requestAudioFocus());
  }

  void _onPlaying() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _autoplayBlocked = false;
      _initialLoading = false;
    });
    _scheduleAutoFullscreen();
    if (_controlsVisible) _startHideTimer();
  }

  void _onPaused() {
    if (!mounted) return;
    _hideTimer?.cancel();
    // 暂停不强制弹出控件；用户点一下画面即可显示。
  }

  void _onVideoError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message.isEmpty ? '播放器错误' : message;
      _initialLoading = false;
      _controlsVisible = true;
    });
  }

  void _onNoVideo(String siteMessage) {
    if (!mounted || _video.hasPicture) return;
    setState(() {
      _error = siteMessage.isNotEmpty
          ? siteMessage
          : '没有找到直播画面。\n可能是当前节目暂不可用，请稍后重试或切换频道。';
      _initialLoading = false;
      _controlsVisible = true;
    });
  }

  void _onAutoplayBlocked() {
    if (!mounted) return;
    setState(() {
      _autoplayBlocked = true;
      _controlsVisible = true;
    });
  }

  void _scheduleAutoFullscreen() {
    // 手机版不自动进入全屏；全屏只由用户点按钮触发。
    if (!mounted || _autoFullscreen || _didAutoFullscreen || _isFullscreen) {
      return;
    }
  }

  Future<void> _togglePlay() async {
    _wakeControls();
    final web = _web;
    if (web == null) return;
    if (_autoplayBlocked || _video.paused) {
      _userPaused = false;
      setState(() => _autoplayBlocked = false);
      await web.runJavaScript(
        'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.play();',
      );
    } else {
      _userPaused = true;
      await web.runJavaScript(
        'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.pause();',
      );
      setState(() => _controlsVisible = true);
    }
    _startHideTimer();
  }

  void _toggleFit() {
    setState(() => _fitCover = !_fitCover);
    final mode = _fitCover ? 'cover' : 'contain';
    unawaited(_web?.runJavaScript(
      'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.setFit("$mode");',
    ));
    _wakeControls();
  }
  Future<void> _toggleMute() async {
    _wakeControls();
    final shouldMute = !(_muted || _volume <= 0.01);
    setState(() => _muted = shouldMute);
    if (!shouldMute && _volume <= 0.01) {
      _applyVolume(0.5);
      setState(() => _volume = 0.5);
    }
    await _web?.runJavaScript(
      'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.setMuted('
      '${shouldMute ? 'true' : 'false'});',
    );
  }

  void _onVolumeChanged(double value) {
    setState(() => _volume = value);
    if (_muted && value > 0.01) {
      setState(() => _muted = false);
      unawaited(_web?.runJavaScript(
        'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.setMuted(false);',
      ));
    }
    _applyVolume(value);
  }

  void _onVolumeChangeEnd(double value) {
    unawaited(NativeSystem.setVolume(value));
    _volumeDragging = false;
    _startHideTimer();
  }

  void _applyVolume(double value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastVolumeSetMs < 40) return;
    _lastVolumeSetMs = now;
    unawaited(NativeSystem.setVolume(value));
  }

  void _onBrightnessChanged(double value) {
    setState(() => _brightness = value);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBrightnessSetMs < 40) return;
    _lastBrightnessSetMs = now;
    unawaited(NativeSystem.setBrightness(value));
  }

  void _onBrightnessChangeEnd(double value) {
    unawaited(NativeSystem.setBrightness(value));
    _startHideTimer();
  }

  void _syncVolumeIfNeeded({bool force = false}) {
    if (_volumeDragging) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastVolumeSyncMs < 2000) return;
    _lastVolumeSyncMs = now;
    unawaited(NativeSystem.getVolume().then((value) {
      if (!mounted) return;
      if ((value - _volume).abs() > 0.02) {
        setState(() => _volume = value);
      }
    }));
  }

  void _onGesture(Map<String, dynamic> data) {
    final phase = data['phase'] as String? ?? '';
    final side = data['side'] as String? ?? 'right';
    final dy = (data['dy'] as num?)?.toDouble() ?? 0;
    final isBrightness = side == 'left';

    switch (phase) {
      case 'start':
        _gestureSide = side;
        _volumeBase = _volume;
        _brightnessBase = _brightness;
        _showHud(
          isBrightness ? _HudKind.brightness : _HudKind.volume,
          isBrightness ? _brightness : _volume,
        );
        break;
      case 'move':
        if (_gestureSide == null) {
          _gestureSide = side;
          _volumeBase = _volume;
          _brightnessBase = _brightness;
        }
        final base = isBrightness ? _brightnessBase : _volumeBase;
        final value = (base + dy).clamp(0.0, 1.0);
        if (isBrightness) {
          _onBrightnessChanged(value);
        } else {
          _onVolumeChanged(value);
        }
        _showHud(
          isBrightness ? _HudKind.brightness : _HudKind.volume,
          value,
        );
        break;
      case 'end':
        if (isBrightness) {
          _onBrightnessChangeEnd(_brightness);
        } else {
          _onVolumeChangeEnd(_volume);
        }
        _gestureSide = null;
        _hideHudSoon();
        break;
      default:
        break;
    }
  }

  void _showHud(_HudKind kind, double value) {
    _hudTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _hudVisible = true;
      _hudKind = kind;
      _hudValue = value.clamp(0.0, 1.0);
    });
  }

  void _hideHudSoon() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  void _wakeControls({bool hideAfter = true}) {
    if (!mounted) return;
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (hideAfter) _startHideTimer();
    _syncVolumeIfNeeded();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_drawerOpen || _error != null || _showLoading) return;
    if (_video.paused) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _drawerOpen || _error != null || _showLoading) return;
      if (_video.paused) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
    }
  }

  void _toggleControls() {
    if (_showLoading || _error != null) return;
    if (_controlsVisible) {
      _hideControls();
    } else {
      _wakeControls();
    }
  }

  void _openDrawer() {
    if (!mounted || _channels.isEmpty) return;
    final size = MediaQuery.sizeOf(context);
    if (!_isFullscreen && size.height > size.width) {
      // 竖屏下方已经有频道列表，不再弹出抽屉。
      _wakeControls();
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _drawerOpen = true;
      _controlsVisible = true;
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() => _drawerOpen = false);
    _startHideTimer();
  }

  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= _channels.length) return;
    if (index == _index) {
      _closeDrawer();
      if (_error != null) unawaited(_retry());
      return;
    }
    setState(() {
      _index = index;
      _channel = _channels[index];
      _drawerOpen = false;
      _controlsVisible = true;
      _error = null;
      _initialLoading = true;
      _autoplayBlocked = false;
      _video = VideoState.empty;
      _didAutoFullscreen = _isFullscreen;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollPortraitTo(index);
    });
    await _loadChannel();
  }

  void _nextChannel(int delta) {
    if (_channels.isEmpty) return;
    final next = (_index + delta) % _channels.length;
    unawaited(_switchTo(next));
  }

  Future<void> _enterFullscreen({bool rotate = true}) async {
    if (!mounted) return;
    setState(() {
      _isFullscreen = true;
      _didAutoFullscreen = true;
      _controlsVisible = true;
    });
    if (rotate) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startHideTimer();
  }

  Future<void> _exitFullscreen() async {
    if (!mounted) return;
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    setState(() {
      _isFullscreen = false;
      _controlsVisible = true;
    });
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (isTablet) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      // 退出全屏后固定在竖屏，避免松手后又弹回横屏。
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    _startHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    _wakeControls();
    if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen(rotate: true);
    }
  }

  Future<void> _retry() async {
    _wakeControls();
    setState(() {
      _error = null;
      _autoplayBlocked = false;
      _initialLoading = true;
      _video = VideoState.empty;
      _didAutoFullscreen = _isFullscreen;
    });
    await _loadChannel();
  }

  Future<void> _openExternal(String url) async {
    final ok = await NativeSystem.openUrl(url);
    if (!ok && mounted) {
      _showSnack('没有找到可用的浏览器');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleBack() {
    if (_drawerOpen) {
      _closeDrawer();
      return;
    }
    if (_isFullscreen) {
      unawaited(_exitFullscreen());
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _openSettings() async {
    _wakeControls();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => SettingsSheet(
        autoFullscreen: _autoFullscreen,
        keepScreenOn: _keepScreenOn,
        webViewVersion: _webViewVersion,
        appVersion: _appVersion,
        onAutoFullscreenChanged: (value) {
          setState(() => _autoFullscreen = value);
          AppPreferences.setAutoFullscreen(value);
        },
        onKeepScreenOnChanged: (value) {
          setState(() => _keepScreenOn = value);
          AppPreferences.setKeepScreenOn(value);
          unawaited(NativeSystem.setKeepScreenOn(value));
        },
        onOpenWebsite: () => _openExternal(_channel.webUrl),
      ),
    );
  }

  Future<dynamic> _onNativeMethodCall(MethodCall call) async {
    if (call.method == 'audioFocus') {
      final value = call.arguments as String?;
      if (value == 'loss') {
        if (!_video.paused) {
          _pausedByFocus = true;
          await _web?.runJavaScript(
            'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.pause();',
          );
        }
      } else if (value == 'gain' && _pausedByFocus) {
        _pausedByFocus = false;
        await _web?.runJavaScript(
          'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.play();',
        );
      }
    }
    return null;
  }

  @override
  void didChangeMetrics() {
    if (_isFullscreen) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appInBackground = true;
        if (_isFullscreen) {
          unawaited(_exitFullscreen());
        }
        if (!_video.paused) {
          _resumeAfterBackground = true;
          unawaited(_web?.runJavaScript(
            'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.pause();',
          ));
        }
        unawaited(NativeSystem.abandonAudioFocus());
        break;
      case AppLifecycleState.resumed:
        _appInBackground = false;
        unawaited(NativeSystem.setKeepScreenOn(_keepScreenOn));
        unawaited(NativeSystem.requestAudioFocus());
        if (_resumeAfterBackground) {
          _resumeAfterBackground = false;
          unawaited(_web?.runJavaScript(
            'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.play();',
          ));
        }
        if (_isFullscreen) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
          );
        }
        _syncVolumeIfNeeded(force: true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _portraitScroll.dispose();
    _autoFullscreenTimer?.cancel();
    _hudTimer?.cancel();

    NativeSystem.setMethodCallHandler(null);
    unawaited(NativeSystem.setKeepScreenOn(false));
    unawaited(NativeSystem.resetBrightness());
    unawaited(NativeSystem.abandonAudioFocus());
    unawaited(_web?.runJavaScript(
      'window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.stop();',
    ));
    unawaited(SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPortrait = size.height > size.width && !_isFullscreen;

    return PopScope(
      canPop: !_drawerOpen && !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_drawerOpen) {
          _closeDrawer();
          return;
        }
        if (_isFullscreen) {
          unawaited(_exitFullscreen());
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: isPortrait
              ? _buildPortraitBody(size)
              : _buildLandscapeBody(size),
        ),
      ),
    );
  }

  Widget _buildLandscapeBody(Size size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_web != null) WebViewWidget(controller: _web!),
        _buildCenterSpinner(),
        if (_controlsVisible && !_showLoading && _error == null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hideControls,
            ),
          ),
        _buildControls(true),
        _buildLoadingOverlay(),
        _buildErrorOverlay(),
        _buildHud(),
        _buildDrawer(size),
      ],
    );
  }

  Widget _buildPortraitBody(Size size) {
    final videoHeight = (size.width * 9 / 16).clamp(180.0, size.height * 0.42);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            height: videoHeight,
            child: _buildPortraitVideo(),
          ),
          Expanded(child: _buildPortraitContent()),
        ],
      ),
    );
  }

  Widget _buildPortraitVideo() {
    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (_web != null) WebViewWidget(controller: _web!),
        _buildCenterSpinner(),
        _buildPortraitLoading(),
        _buildPortraitError(),
        _buildCompactOverlay(),
        _buildHud(),
      ],
    );
    if (_controlsVisible && !_showLoading && _error == null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hideControls,
        child: content,
      );
    }
    return content;
  }

  Widget _buildPortraitContent() {
    return Column(
      children: [
        _buildPortraitControlPanel(),
        _buildPortraitChannelHeader(),
        Expanded(child: _buildPortraitChannelList()),
      ],
    );
  }

  Widget _buildPortraitLoading() {
    if (!_showLoading) return const SizedBox.shrink();
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              '正在加载 ${_channel.label}',
              style: const TextStyle(fontSize: 13, color: AppColors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              _progress > 0 && _progress < 100
                  ? '已加载 $_progress%'
                  : '正在连接央视网直播…',
              style: const TextStyle(fontSize: 11, color: AppColors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitError() {
    final error = _error;
    if (error == null) return const SizedBox.shrink();
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.all(14),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 28, color: AppColors.brandRed),
            const SizedBox(height: 6),
            const Text(
              '暂时无法播放',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.white70),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => unawaited(_retry()),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactOverlay() {
    final visible = _controlsVisible && !_showLoading && _error == null;
    final effectiveMuted = _muted || _volume <= 0.01;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.78),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(2, 2, 4, 22),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: Colors.white,
                      tooltip: '返回',
                      visualDensity: VisualDensity.compact,
                    ),
                    const _LiveDot(),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_channel.label} ${_channel.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => unawaited(_toggleFullscreen()),
                      icon: const Icon(Icons.fullscreen_rounded, size: 20),
                      color: Colors.white,
                      tooltip: '全屏',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            Center(child: _buildCompactPlayButton()),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.82),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(10, 20, 6, 5),
                child: Row(
                  children: [
                    const _LiveDot(),
                    const SizedBox(width: 6),
                    Text(
                      _video.hasPicture
                          ? (_video.paused ? '已暂停' : '直播中')
                          : '正在连接…',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已观看 ${formatWatchTime(_video.currentTime)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.white54,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _toggleMute,
                      icon: Icon(
                        effectiveMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        size: 18,
                      ),
                      color: Colors.white,
                      tooltip: effectiveMuted ? '取消静音' : '静音',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () => unawaited(_retry()),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      color: Colors.white,
                      tooltip: '重新加载',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPlayButton() {
    if (!_video.found || _showLoading || _error != null || _video.buffering) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => unawaited(_togglePlay()),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(
            _video.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 30,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitControlPanel() {
    final effectiveMuted = _muted || _volume <= 0.01;
    return Container(
      color: const Color(0xFF0C0C12),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _toggleMute,
                icon: Icon(
                  effectiveMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  size: 20,
                ),
                color: Colors.white,
                tooltip: effectiveMuted ? '取消静音' : '静音',
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: Slider(
                    value: _volume.clamp(0.0, 1.0),
                    onChangeStart: (_) {
                      _volumeDragging = true;
                      _wakeControls(hideAfter: false);
                    },
                    onChanged: _onVolumeChanged,
                    onChangeEnd: _onVolumeChangeEnd,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.brightness_6_rounded,
                size: 18,
                color: AppColors.white70,
              ),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: Slider(
                    value: _brightness.clamp(0.01, 1.0),
                    onChangeStart: (_) => _wakeControls(hideAfter: false),
                    onChanged: _onBrightnessChanged,
                    onChangeEnd: _onBrightnessChangeEnd,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _iconButton(
                Icons.skip_previous_rounded,
                '上一个频道',
                () => _nextChannel(-1),
              ),
              _iconButton(
                _video.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                '播放 / 暂停',
                _togglePlay,
              ),
              _iconButton(
                Icons.skip_next_rounded,
                '下一个频道',
                () => _nextChannel(1),
              ),
              const Spacer(),
              _iconButton(
                Icons.aspect_ratio_rounded,
                _fitCover ? '适应画面' : '铺满画面',
                _toggleFit,
              ),
              _iconButton(Icons.refresh_rounded, '重新加载', _retry),
              _iconButton(
                _isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                _isFullscreen ? '退出全屏' : '全屏',
                _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitChannelHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          const Text(
            '频道',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_channels.length} 个',
            style: const TextStyle(fontSize: 11, color: AppColors.white54),
          ),
          const Spacer(),
          Text(
            '当前 ${_channel.label}',
            style: const TextStyle(fontSize: 11, color: AppColors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitChannelList() {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return ListView.builder(
      controller: _portraitScroll,
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + bottom),
      itemExtent: 58,
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final channel = _channels[index];
        final current = index == _index;
        return InkWell(
          onTap: () => unawaited(_switchTo(index)),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: current
                  ? AppColors.brandRed.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: current ? AppColors.brandRed : AppColors.white12,
                width: current ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    channel.number.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: current
                          ? AppColors.brandRed
                          : AppColors.white24,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            channel.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: current
                                  ? Colors.white
                                  : AppColors.white70,
                            ),
                          ),
                          if (current) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandRed,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '直播中',
                                style: TextStyle(
                                  fontSize: 9,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  current
                      ? Icons.graphic_eq_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: current ? AppColors.brandRed : AppColors.white12,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollPortraitTo(int index) {
    if (!_portraitScroll.hasClients) return;
    const extent = 58.0;
    final target = (index * extent - extent * 2)
        .clamp(0.0, _portraitScroll.position.maxScrollExtent);
    _portraitScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }
  Widget _buildLoadingOverlay() {
    final visible = _showLoading;
    final top = MediaQuery.viewPaddingOf(context).top;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 380),
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned(
                top: top + 4,
                left: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: AppColors.white70,
                  tooltip: '返回',
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.brandRed,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _channel.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.white54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _channel.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 30),
                      const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.brandRed,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _progress > 0 && _progress < 100
                            ? '正在加载 $_progress%'
                            : '正在连接央视网直播…',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '首次加载可能需要几秒',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    final error = _error;
    if (error == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.94),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.brandRed.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: AppColors.brandRed,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '暂时无法播放',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_channel.label} · ${_channel.title}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.white54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: AppColors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => unawaited(_retry()),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重试'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openDrawer,
                          icon: const Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 18,
                          ),
                          label: const Text('切换频道'),
                        ),
                        TextButton.icon(
                          onPressed: () => unawaited(
                            _openExternal(_channel.webUrl),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('在浏览器打开'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('返回'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterSpinner() {
    final visible = !_showLoading &&
        _error == null &&
        _pageLoaded &&
        (!_video.hasPicture || _video.buffering);
    if (!visible) return const SizedBox.shrink();

    return IgnorePointer(
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(11),
          child: const CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildControls(bool landscape) {
    final visible = _controlsVisible && !_showLoading && _error == null;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          children: [
            _buildTopBar(),
            _buildBottomBar(landscape),
            _buildCenterButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final top = MediaQuery.viewPaddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
        padding: EdgeInsets.fromLTRB(4, top + 4, 8, 26),
        child: Row(
          children: [
            IconButton(
              onPressed: _handleBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              color: Colors.white,
              tooltip: '返回',
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const _LiveDot(),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _channel.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _channel.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _video.hasPicture
                        ? (_video.paused ? '已暂停' : '正在直播')
                        : '正在连接…',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.white54,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'reload':
                    unawaited(_retry());
                    break;
                  case 'browser':
                    unawaited(_openExternal(_channel.webUrl));
                    break;
                  case 'settings':
                    unawaited(_openSettings());
                    break;
                  default:
                    break;
                }
              },
              icon: const Icon(Icons.more_vert_rounded),
              color: AppColors.surfaceHigh,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'reload',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('重新加载'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'browser',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('在浏览器打开'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('设置'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool landscape) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final effectiveMuted = _muted || _volume <= 0.01;
    final resolution = _video.resolutionLabel;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.9),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
        padding: EdgeInsets.fromLTRB(16, landscape ? 56 : 48, 16, 8 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 6),
                Text(
                  _video.paused ? '已暂停' : '直播中',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '已观看 ${formatWatchTime(_video.currentTime)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.white54,
                  ),
                ),
                const Spacer(),
                if (resolution.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      resolution,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white70,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: Stack(
                  children: [
                    Container(color: AppColors.white24),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.brandRedDark,
                            AppColors.brandRed,
                            AppColors.live,
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.live.withValues(alpha: 0.7),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(
                    effectiveMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 21,
                  ),
                  color: Colors.white,
                  tooltip: effectiveMuted ? '取消静音' : '静音',
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Semantics(
                    label: '音量',
                    child: SizedBox(
                      height: 32,
                      child: Slider(
                        value: _volume.clamp(0.0, 1.0),
                        onChangeStart: (_) {
                          _volumeDragging = true;
                          _wakeControls(hideAfter: false);
                        },
                        onChanged: _onVolumeChanged,
                        onChangeEnd: _onVolumeChangeEnd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Tooltip(
                  message: '亮度（上下滑动屏幕左侧也可调节）',
                  child: Icon(
                    Icons.brightness_6_rounded,
                    size: 19,
                    color: AppColors.white70,
                  ),
                ),
                Expanded(
                  child: Semantics(
                    label: '亮度',
                    child: SizedBox(
                      height: 32,
                      child: Slider(
                        value: _brightness.clamp(0.01, 1.0),
                        onChangeStart: (_) => _wakeControls(hideAfter: false),
                        onChanged: _onBrightnessChanged,
                        onChangeEnd: _onBrightnessChangeEnd,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                _iconButton(
                  Icons.skip_previous_rounded,
                  '上一个频道',
                  () => _nextChannel(-1),
                ),
                _iconButton(
                  Icons.skip_next_rounded,
                  '下一个频道',
                  () => _nextChannel(1),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openDrawer,
                  icon: const Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 18,
                  ),
                  label: const Text('频道'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 38),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _iconButton(
                  Icons.aspect_ratio_rounded,
                  _fitCover ? '适应画面' : '铺满画面',
                  _toggleFit,
                ),
                _iconButton(Icons.refresh_rounded, '重新加载', _retry),
                _iconButton(
                  _isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  _isFullscreen ? '退出全屏' : '全屏',
                  _toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      color: Colors.white,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildCenterButton() {
    if (!_video.found || _showLoading || _error != null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.44),
            shape: CircleBorder(
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => unawaited(_togglePlay()),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Icon(
                  _video.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  size: 44,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_autoplayBlocked) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '点击播放',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHud() {
    if (!_hudVisible) return const SizedBox.shrink();
    final isBrightness = _hudKind == _HudKind.brightness;
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBrightness
                    ? Icons.brightness_6_rounded
                    : (_hudValue <= 0.01
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded),
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 9),
              Text(
                isBrightness ? '亮度' : '音量',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.white54,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(_hudValue * 100).round()}%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(Size size) {
    final width = math.min(340.0, size.width * 0.86);
    return Stack(
      children: [
        if (_drawerOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeDrawer,
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          right: _drawerOpen ? 0 : -width - 24,
          width: width,
          child: ChannelPanel(
            channels: _channels,
            currentIndex: _index,
            onSelect: (index) => unawaited(_switchTo(index)),
            onClose: _closeDrawer,
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.live,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.live.withValues(alpha: 0.6),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

enum _HudKind { volume, brightness }
