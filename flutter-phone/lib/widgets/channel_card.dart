import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/channel.dart';

/// 主页频道卡片：上行小字 label，下行大字 title，右上角频道号。
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.isLast,
    required this.onTap,
  });

  final Channel channel;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final borderColor = isLast
        ? AppColors.brandRed
        : Colors.black.withValues(alpha: 0.07);

    return Material(
      color: AppColors.card,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.brandRed.withValues(alpha: 0.08),
        highlightColor: AppColors.brandRed.withValues(alpha: 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: borderColor,
              width: isLast ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(15, 12, 13, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      channel.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: isLast
                            ? AppColors.brandRed
                            : AppColors.cardMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    channel.number.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.black.withValues(alpha: 0.22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                channel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cardInk,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    isLast
                        ? Icons.play_circle_fill_rounded
                        : Icons.play_arrow_rounded,
                    size: 15,
                    color: isLast
                        ? AppColors.brandRed
                        : AppColors.cardMuted.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isLast ? '上次观看' : '点击播放',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: isLast
                          ? AppColors.brandRed
                          : AppColors.cardMuted.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
