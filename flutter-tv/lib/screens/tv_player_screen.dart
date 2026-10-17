import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/tv_colors.dart';
import '../core/tv_preferences.dart';
import '../core/tv_system.dart';
import '../models/channel.dart';
import '../models/video_state.dart';

/// 电视播放页：Flutter 控制层 + 原生 GeckoView 平台视图。
class TvPlayerScreen extends StatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
  });

  final List<Channel> channels;
  final int initialIndex;

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen>
    with WidgetsBindingObserver {
  late final List<Channel> _channels;
  late int _index;
  late Channel _channel;

  MethodChannel? _gecko;
  VideoState _video = VideoState.empty;
  bool _loading = true;
  String? _error;
  bool _resumeAfterBackground = false;

  bool _controlsVisible = true;
  bool _drawerOpen = false;
  int _drawerIndex = 0;

  final FocusNode _focusNode = FocusNode(debugLabel: 'tv-player');
  final ScrollController _drawerScroll = ScrollController();
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _channels = widget.channels;
    _index = _channels.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _channels.length - 1).toInt();
    _channel = _channels.first;
    if (_index > 0 && _index < _channels.length) {
      _channel = _channels[_index];
    }
    _drawerIndex = _index;

    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    unawaited(TvSystem.setKeepScreenOn(true));
    unawaited(TvSystem.requestAudioFocus());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onViewCreated(int id) {
    _gecko = MethodChannel('cctv/tv/gecko_$id');
    _gecko!.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (!mounted) return null;
    switch (call.method) {
      case 'state':
        _onStateJson(call.arguments as String?);
        break;
      case 'event':
        _onEventJson(call.arguments as String?);
        break;
      case 'pageStart':
        setState(() {
          _loading = true;
          _video = VideoState.empty;
          _error = null;
          _controlsVisible = true;
        });
        break;
      case 'title':
        break;
      case 'error':
        _showError(call.arguments as String? ?? '播放器错误');
        break;
      default:
        break;
    }
    return null;
  }

  void _onStateJson(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _applyState(VideoState.fromJson(map));
    } catch (_) {
      // 忽略格式错误。
    }
  }

  void _onEventJson(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final type = payload['type'] as String? ?? '';
      final data = (payload['data'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      switch (type) {
        case 'ready':
          setState(() {
            _loading = false;
            _error = null;
          });
          break;
        case 'noVideo':
          final message = (data['siteMessage'] as String?)?.trim() ?? '';
          _showError(message.isNotEmpty
              ? message
              : '没有找到直播画面。\n可能当前节目暂不可用，请稍后重试或切换频道。');
          break;
        case 'error':
          _showError((data['message'] as String?) ?? '播放器错误');
          break;
        case 'autoplayBlocked':
          setState(() {
            _loading = false;
            _controlsVisible = true;
          });
          break;
        default:
          break;
      }
    } catch (_) {
      // 忽略格式错误。
    }
  }

  void _applyState(VideoState next) {
    if (!mounted) return;
    setState(() {
      _video = next;
      if (next.hasPicture) {
        _loading = false;
        _error = null;
      }
      if (next.error.isNotEmpty) {
        _error = next.error;
        _loading = false;
        _controlsVisible = true;
      }
    });

    if (next.hasPicture) {
      if (next.paused) {
        _hideTimer?.cancel();
        if (!_controlsVisible) {
          setState(() => _controlsVisible = true);
        }
      } else if (_controlsVisible && !(_hideTimer?.isActive ?? false)) {
        _startHideTimer();
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() {
      _error = message.isEmpty ? '播放器错误' : message;
      _loading = false;
      _controlsVisible = true;
    });
  }

  void _command(String command) {
    unawaited(_gecko?.invokeMethod<void>('command', command));
  }

  void _togglePlay() {
    if (_error != null) {
      _retry();
      return;
    }
    _wakeControls();
    if (_video.hasPicture) {
      _command(_video.paused ? 'play' : 'pause');
      if (_video.paused) {
        setState(() => _controlsVisible = true);
      } else {
        _startHideTimer();
      }
    } else {
      _command('play');
    }
  }

  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= _channels.length) return;
    if (index == _index) {
      _closeDrawer();
      return;
    }
    setState(() {
      _index = index;
      _channel = _channels[index];
      _drawerIndex = index;
      _drawerOpen = false;
      _loading = true;
      _error = null;
      _video = VideoState.empty;
      _controlsVisible = true;
    });
    await TvPreferences.setLastChannelId(_channel.id);
    unawaited(_gecko?.invokeMethod<void>('loadUrl', _channel.webUrl));
    _startHideTimer();
  }

  void _retry() {
    if (_gecko == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _video = VideoState.empty;
      _controlsVisible = true;
    });
    unawaited(_gecko?.invokeMethod<void>('loadUrl', _channel.webUrl));
    _startHideTimer();
  }

  void _nextChannel(int delta) {
    if (_channels.isEmpty) return;
    final next = (_index + delta) % _channels.length;
    unawaited(_switchTo(next));
  }

  void _openDrawer() {
    _hideTimer?.cancel();
    setState(() {
      _drawerOpen = true;
      _drawerIndex = _index;
      _controlsVisible = true;
    });
    _scrollDrawerTo(_drawerIndex);
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() => _drawerOpen = false);
    _startHideTimer();
  }

  void _moveDrawer(int delta) {
    if (_channels.isEmpty) return;
    final next = (_drawerIndex + delta) % _channels.length;
    setState(() => _drawerIndex = next);
    _scrollDrawerTo(next);
  }

  void _scrollDrawerTo(int index) {
    if (!_drawerScroll.hasClients) return;
    const itemExtent = 68.0;
    final target = (index * itemExtent - itemExtent * 2)
        .clamp(0.0, _drawerScroll.position.maxScrollExtent);
    _drawerScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _wakeControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_drawerOpen || _error != null || _loading) return;
    if (!_video.hasPicture || _video.paused) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _drawerOpen || _error != null || _loading) return;
      if (!_video.hasPicture || _video.paused) return;
      setState(() => _controlsVisible = false);
    });
  }

  bool _isSelect(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    _wakeControls();

    if (_drawerOpen) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _moveDrawer(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveDrawer(1);
        return KeyEventResult.handled;
      }
      if (_isSelect(key)) {
        unawaited(_switchTo(_drawerIndex));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _closeDrawer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _nextChannel(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _nextChannel(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _openDrawer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _wakeControls();
      return KeyEventResult.handled;
    }
    if (_isSelect(key) || key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      _openDrawer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _resumeAfterBackground = _video.isPlaying;
        _command('pause');
        unawaited(TvSystem.abandonAudioFocus());
        break;
      case AppLifecycleState.resumed:
        unawaited(TvSystem.setKeepScreenOn(true));
        unawaited(TvSystem.requestAudioFocus());
        if (_resumeAfterBackground) {
          _resumeAfterBackground = false;
          _command('play');
        }
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    _focusNode.dispose();
    _drawerScroll.dispose();
    unawaited(TvSystem.setKeepScreenOn(false));
    unawaited(TvSystem.abandonAudioFocus());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_drawerOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _drawerOpen) _closeDrawer();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AndroidView(
                viewType: 'cctv/tv/geckoview',
                creationParams: <String, dynamic>{
                  'url': _channel.webUrl,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _onViewCreated,
              ),
              _buildLoadingOverlay(),
              _buildErrorOverlay(),
              _buildControls(),
              _buildDrawer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    final visible = _loading && _error == null;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 54,
                  decoration: BoxDecoration(
                    color: TvColors.red,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: TvColors.red.withValues(alpha: 0.5),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _channel.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: TvColors.white54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _channel.title,
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: TvColors.red,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '正在连接央视网直播…',
                  style: TextStyle(fontSize: 18, color: TvColors.white70),
                ),
                const SizedBox(height: 8),
                const Text(
                  'GeckoView 内置内核 · 不使用 WebView',
                  style: TextStyle(fontSize: 13, color: TvColors.white24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    final error = _error;
    if (error == null) return const SizedBox.shrink();
    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: TvColors.red.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 42,
                  color: TvColors.red,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                '暂时无法播放',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_channel.label} · ${_channel.title}',
                style: const TextStyle(fontSize: 17, color: TvColors.white54),
              ),
              const SizedBox(height: 22),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.55,
                  color: TvColors.white70,
                ),
              ),
              const SizedBox(height: 34),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _KeyHint(keyLabel: '确定键', action: '重试'),
                  SizedBox(width: 28),
                  _KeyHint(keyLabel: '返回键', action: '回主页'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final visible = _controlsVisible && _error == null;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Stack(
          children: [
            _buildTopBar(),
            _buildBottomBar(),
            _buildCenterStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
              Colors.black.withValues(alpha: 0.88),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(52, 34, 52, 40),
        child: Row(
          children: [
            const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 24,
              color: TvColors.white54,
            ),
            const SizedBox(width: 20),
            const _LiveDot(),
            const SizedBox(width: 12),
            Text(
              _channel.label,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _channel.title,
              style: const TextStyle(fontSize: 18, color: TvColors.white54),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: TvColors.white12,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TvColors.white12),
              ),
              child: const Text(
                'GeckoView',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: TvColors.white54,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
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
              Colors.black.withValues(alpha: 0.92),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(52, 70, 52, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 9),
                Text(
                  _video.hasPicture
                      ? (_video.paused ? '已暂停' : '直播中')
                      : '正在连接…',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '已观看 ${formatWatchTime(_video.currentTime)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: TvColors.white54,
                  ),
                ),
                const Spacer(),
                if (resolution.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: TvColors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      resolution,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TvColors.white70,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: Stack(
                  children: [
                    Container(color: TvColors.white24),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            TvColors.redDark,
                            TvColors.red,
                            TvColors.live,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                _KeyHint(keyLabel: '确定', action: '播放 / 暂停'),
                SizedBox(width: 24),
                _KeyHint(keyLabel: '↑ ↓', action: '换台'),
                SizedBox(width: 24),
                _KeyHint(keyLabel: '←', action: '频道列表'),
                SizedBox(width: 24),
                _KeyHint(keyLabel: '返回', action: '回主页'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterStatus() {
    if (_video.buffering && _video.hasPicture) {
      return const Center(
        child: SizedBox(
          width: 54,
          height: 54,
          child: CircularProgressIndicator(
            strokeWidth: 3.2,
            color: Colors.white,
          ),
        ),
      );
    }
    if (_video.hasPicture && _video.paused) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                shape: BoxShape.circle,
                border: Border.all(color: TvColors.white24),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 62,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                '按确定键播放',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildDrawer() {
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width * 0.42 < 480 ? width * 0.42 : 480.0;
    return Stack(
      children: [
        if (_drawerOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeDrawer,
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          right: _drawerOpen ? 0 : -panelWidth - 30,
          width: panelWidth,
          child: Material(
            color: TvColors.surface,
            elevation: 24,
            child: SafeArea(
              left: false,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: TvColors.surfaceHigh,
                    padding: const EdgeInsets.fromLTRB(28, 26, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '频道',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              '共 ${_channels.length} 个',
                              style: const TextStyle(
                                fontSize: 15,
                                color: TvColors.white54,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              '← 关闭',
                              style: TextStyle(
                                fontSize: 14,
                                color: TvColors.white54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '↑↓ 选择 · 确定键切换',
                          style: TextStyle(
                            fontSize: 14,
                            color: TvColors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _drawerScroll,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemExtent: 68,
                      itemCount: _channels.length,
                      itemBuilder: (context, index) {
                        final channel = _channels[index];
                        final selected = index == _drawerIndex;
                        final current = index == _index;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? TvColors.red.withValues(alpha: 0.20)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? TvColors.red
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  channel.number.toString().padLeft(2, '0'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? TvColors.red
                                        : TvColors.white24,
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
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? Colors.white
                                                : TvColors.white70,
                                          ),
                                        ),
                                        if (current) ...[
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: TvColors.red,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              '正在播放',
                                              style: TextStyle(
                                                fontSize: 10,
                                                height: 1.1,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      channel.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: TvColors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: TvColors.red,
                                  size: 22,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
                    child: const Row(
                      children: [
                        Icon(Icons.gamepad_rounded,
                            size: 16, color: TvColors.white24),
                        SizedBox(width: 8),
                        Text(
                          '方向键浏览 · 返回键退出列表',
                          style: TextStyle(
                            fontSize: 12,
                            color: TvColors.white24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: TvColors.live,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: TvColors.live.withValues(alpha: 0.6),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keyLabel, required this.action});

  final String keyLabel;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: TvColors.white12,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TvColors.white24),
          ),
          child: Text(
            keyLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: TvColors.white70,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          action,
          style: const TextStyle(fontSize: 13, color: TvColors.white54),
        ),
      ],
    );
  }
}
