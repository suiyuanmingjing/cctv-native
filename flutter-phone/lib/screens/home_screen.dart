import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/formatters.dart';
import '../core/native_system.dart';
import '../core/preferences.dart';
import '../data/channel_repository.dart';
import '../models/channel.dart';
import '../widgets/channel_card.dart';
import '../widgets/settings_sheet.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Channel>? _channels;
  Object? _loadError;
  String? _lastChannelId;
  bool _autoFullscreen = true;
  bool _keepScreenOn = true;
  String _webViewVersion = '';
  String _appVersion = '1.0.0';
  bool _checkedKernel = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLastChannel();
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait<Object?>([
        ChannelRepository.load(),
        AppPreferences.lastChannelId(),
        AppPreferences.autoFullscreen(),
        AppPreferences.keepScreenOn(),
        NativeSystem.webViewVersion(),
        NativeSystem.appVersion(),
      ]);
      if (!mounted) return;
      setState(() {
        _channels = results[0] as List<Channel>;
        _lastChannelId = results[1] as String?;
        _autoFullscreen = results[2] as bool;
        _keepScreenOn = results[3] as bool;
        _webViewVersion = results[4] as String;
        _appVersion = results[5] as String;
      });
      _maybeWarnKernel();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _refreshLastChannel() async {
    final id = await AppPreferences.lastChannelId();
    if (mounted && id != _lastChannelId) {
      setState(() => _lastChannelId = id);
    }
  }

  void _maybeWarnKernel() {
    if (_checkedKernel) return;
    _checkedKernel = true;
    final major = majorVersion(_webViewVersion);
    if (major <= 0 || major >= 88) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('浏览器内核版本偏低'),
          content: Text(
            '当前系统浏览器内核版本是 $_webViewVersion，建议 88 以上，'
            '否则可能无法正常播放或全屏。\n\n'
            '可以到应用商店更新「Android System WebView」或「Chrome」。',
            style: const TextStyle(height: 1.55),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('仍然尝试'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await NativeSystem.openWebViewStore();
              },
              child: const Text('去更新'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _openChannel(int index) async {
    final channels = _channels;
    if (channels == null || index < 0 || index >= channels.length) return;

    await AppPreferences.setLastChannelId(channels[index].id);
    if (!mounted) return;
    setState(() => _lastChannelId = channels[index].id);

    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, _) => PlayerScreen(
          channels: channels,
          initialIndex: index,
        ),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    _refreshLastChannel();
  }

  Future<void> _openSettings() async {
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
        },
        onOpenWebsite: () => _openExternal('https://tv.cctv.com/live/'),
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final ok = await NativeSystem.openUrl(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有找到可用的浏览器')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.homeBottom,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.homeTop,
                AppColors.homeMid,
                AppColors.homeBottom,
              ],
              stops: [0, 0.52, 1],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: -110,
                top: -150,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(bottom: false, child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return _ErrorView(error: _loadError, onRetry: _load);
    }
    final channels = _channels;
    if (channels == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.homeInk,
              ),
            ),
            SizedBox(height: 16),
            Text(
              '正在准备频道…',
              style: TextStyle(fontSize: 13, color: AppColors.homeInkSoft),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(channels),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100
                  ? 5
                  : width >= 860
                      ? 4
                      : width >= 560
                          ? 3
                          : 2;
              final extent = width < 380 ? 112.0 : 118.0;

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: extent,
                ),
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ChannelCard(
                    channel: channel,
                    isLast: channel.id == _lastChannelId,
                    onTap: () => _openChannel(index),
                  );
                },
              );
            },
          ),
        ),
        _buildFooter(channels.length),
      ],
    );
  }

  Widget _buildHeader(List<Channel> channels) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brandRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CCTV 直播',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: AppColors.homeInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${channels.length} 个频道 · 点击开播',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: AppColors.homeInkSoft.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
            color: AppColors.homeInk,
            tooltip: '设置',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.28),
              minimumSize: const Size(44, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int count) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 2, 20, 8 + bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 13,
            color: AppColors.homeInkSoft.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '内容来自央视网 tv.cctv.com · 不代理、不存储 · $count 个频道',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.homeInkSoft.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: AppColors.homeInk.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 14),
            const Text(
              '频道列表加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.homeInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.homeInkSoft.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
