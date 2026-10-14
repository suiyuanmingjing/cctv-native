import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// 设置底部弹窗：播放偏好、内核版本、关于。
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.autoFullscreen,
    required this.keepScreenOn,
    required this.webViewVersion,
    required this.appVersion,
    required this.onAutoFullscreenChanged,
    required this.onKeepScreenOnChanged,
    required this.onOpenWebsite,
  });

  final bool autoFullscreen;
  final bool keepScreenOn;
  final String webViewVersion;
  final String appVersion;
  final ValueChanged<bool> onAutoFullscreenChanged;
  final ValueChanged<bool> onKeepScreenOnChanged;
  final VoidCallback onOpenWebsite;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late bool _autoFullscreen = widget.autoFullscreen;
  late bool _keepScreenOn = widget.keepScreenOn;

  String get _kernelLabel {
    final version = widget.webViewVersion.trim();
    if (version.isEmpty) return '系统 WebView';
    final major = RegExp(r'^(\d+)').firstMatch(version)?.group(1);
    return major == null ? version : 'Chrome $major';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.drawerBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: AppColors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    '设置',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.white70,
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _SwitchTile(
                icon: Icons.screen_rotation_rounded,
                title: '自动横屏全屏',
                subtitle: '直播画面就绪后自动旋转到横屏，隐藏系统栏',
                value: _autoFullscreen,
                onChanged: (value) {
                  setState(() => _autoFullscreen = value);
                  widget.onAutoFullscreenChanged(value);
                },
              ),
              _SwitchTile(
                icon: Icons.light_mode_rounded,
                title: '保持屏幕常亮',
                subtitle: '观看直播时不自动锁屏',
                value: _keepScreenOn,
                onChanged: (value) {
                  setState(() => _keepScreenOn = value);
                  widget.onKeepScreenOnChanged(value);
                },
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const _TileIcon(icon: Icons.memory_rounded),
                title: const Text(
                  '浏览器内核',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('使用系统 Chrome / Android System WebView'),
                trailing: Text(
                  _kernelLabel,
                  style: const TextStyle(
                    color: AppColors.white70,
                    fontSize: 12.5,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const _TileIcon(icon: Icons.open_in_new_rounded),
                title: const Text(
                  '在浏览器中打开央视网',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('tv.cctv.com/live'),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.white54,
                ),
                onTap: widget.onOpenWebsite,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const _TileIcon(icon: Icons.info_outline_rounded),
                title: const Text(
                  '关于 CCTV 直播',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Flutter 手机版 v${widget.appVersion}'),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.white54,
                ),
                onTap: () => _showAbout(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('CCTV 直播'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Flutter 手机版 v${widget.appVersion}',
                style: const TextStyle(color: AppColors.white70),
              ),
              const SizedBox(height: 14),
              const Text(
                '本应用只打开央视网（tv.cctv.com）的公开直播页面，'
                '不解析、不代理、不保存任何视频内容。',
                style: TextStyle(height: 1.55),
              ),
              const SizedBox(height: 10),
              const Text(
                '频道数据取自央视网公开导航。播放依赖设备自带的 Chrome / '
                'Android System WebView 内核，建议 Android 9 及以上。',
                style: TextStyle(height: 1.55, color: AppColors.white70),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: _TileIcon(icon: icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.brandRed,
      onChanged: onChanged,
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.white12,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: AppColors.white70),
    );
  }
}
