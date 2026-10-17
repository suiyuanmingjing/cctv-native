import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_colors.dart';
import '../core/tv_preferences.dart';
import '../data/channel_repository.dart';
import '../models/channel.dart';
import '../widgets/tv_channel_card.dart';
import 'tv_player_screen.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> with WidgetsBindingObserver {
  List<Channel>? _channels;
  Object? _error;
  String? _lastChannelId;

  @override
  void initState() {
    super.initState();
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
      _refreshLast();
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>([
        ChannelRepository.load(),
        TvPreferences.lastChannelId(),
      ]);
      if (!mounted) return;
      setState(() {
        _channels = results[0] as List<Channel>;
        _lastChannelId = results[1] as String?;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _refreshLast() async {
    final id = await TvPreferences.lastChannelId();
    if (mounted && id != _lastChannelId) {
      setState(() => _lastChannelId = id);
    }
  }

  Future<void> _openChannel(int index) async {
    final channels = _channels;
    if (channels == null || index < 0 || index >= channels.length) return;
    await TvPreferences.setLastChannelId(channels[index].id);
    if (!mounted) return;
    setState(() => _lastChannelId = channels[index].id);

    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, animation, _) => TvPlayerScreen(
          channels: channels,
          initialIndex: index,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (!mounted) return;
    _refreshLast();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: TvColors.bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.65, -0.8),
              radius: 1.2,
              colors: [Color(0xFF2A1512), TvColors.bg],
            ),
          ),
          child: SafeArea(child: _buildBody()),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: TvColors.white54),
            const SizedBox(height: 16),
            const Text(
              '频道列表加载失败',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('$_error', style: const TextStyle(color: TvColors.white54)),
            const SizedBox(height: 24),
            FilledButton(
              autofocus: true,
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final channels = _channels;
    if (channels == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text(
              '正在准备频道…',
              style: TextStyle(fontSize: 18, color: TvColors.white54),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(channels),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1500
                  ? 6
                  : width >= 1200
                      ? 5
                      : width >= 900
                          ? 4
                          : 3;
              return FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    width >= 1200 ? 60 : 32,
                    10,
                    width >= 1200 ? 60 : 32,
                    8,
                  ),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    mainAxisExtent: 168,
                  ),
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return TvChannelCard(
                      channel: channel,
                      isLast: channel.id == _lastChannelId,
                      autofocus: index == 0,
                      onTap: () => _openChannel(index),
                    );
                  },
                ),
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
      padding: const EdgeInsets.fromLTRB(60, 34, 60, 12),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 54,
            decoration: BoxDecoration(
              color: TvColors.red,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: TvColors.red.withValues(alpha: 0.45),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CCTV 直播',
                  style: TextStyle(
                    fontSize: 44,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '电视版 · ${channels.length} 个频道 · Flutter UI + GeckoView',
                  style: const TextStyle(
                    fontSize: 16,
                    color: TvColors.white54,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: TvColors.white12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TvColors.white12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gamepad_rounded, size: 20, color: TvColors.white70),
                SizedBox(width: 8),
                Text(
                  '方向键选择 · 确定键播放',
                  style: TextStyle(fontSize: 14, color: TvColors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 4, 60, 22),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 16, color: TvColors.white24),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '内容来自央视网 tv.cctv.com · 内置 GeckoView 内核 · 不使用 WebView · $count 个频道',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: TvColors.white54),
            ),
          ),
          const Spacer(),
          const Text(
            '按返回键退出',
            style: TextStyle(fontSize: 13, color: TvColors.white24),
          ),
        ],
      ),
    );
  }
}
