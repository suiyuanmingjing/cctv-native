import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/channel.dart';

/// 播放页右侧频道抽屉。
class ChannelPanel extends StatelessWidget {
  const ChannelPanel({
    super.key,
    required this.channels,
    required this.currentIndex,
    required this.onSelect,
    required this.onClose,
  });

  final List<Channel> channels;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.drawerBg,
      elevation: 24,
      shadowColor: Colors.black,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.drawerHeader,
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '频道',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.white70,
                        tooltip: '关闭频道列表',
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 ${channels.length} 个频道 · 点击切换',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 16),
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  final selected = index == currentIndex;
                  return InkWell(
                    onTap: () => onSelect(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? AppColors.white12 : Colors.transparent,
                        border: Border(
                          left: BorderSide(
                            color: selected
                                ? AppColors.brandRed
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(15, 11, 14, 11),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              channel.number.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? AppColors.brandRed
                                    : AppColors.white24,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        channel.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.white70,
                                        ),
                                      ),
                                    ),
                                    if (selected) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.brandRed,
                                          borderRadius:
                                              BorderRadius.circular(4),
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
                                const SizedBox(height: 3),
                                Text(
                                  channel.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? AppColors.white54
                                        : AppColors.white24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.graphic_eq_rounded,
                              size: 18,
                              color: AppColors.brandRed,
                            )
                          else
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppColors.white12,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
