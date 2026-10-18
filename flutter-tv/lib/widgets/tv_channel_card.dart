import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_colors.dart';
import '../models/channel.dart';

class TvChannelCard extends StatefulWidget {
  const TvChannelCard({
    super.key,
    required this.channel,
    required this.isLast,
    required this.autofocus,
    this.focusNode,    this.onFocusChange,    required this.onTap,
  });

  final Channel channel;
  final bool isLast;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback onTap;

  @override
  State<TvChannelCard> createState() => _TvChannelCardState();
}

class _TvChannelCardState extends State<TvChannelCard> {
  bool _focused = false;
  FocusNode? _internalNode;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalNode = FocusNode(debugLabel: 'tv-channel-card');
    }
  }

  @override
  void dispose() {
    _internalNode?.dispose();
    super.dispose();
  }

  bool _isSelect(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: '${widget.channel.label} ${widget.channel.title}',
      child: Focus(
        focusNode: widget.focusNode ?? _internalNode,
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) {
          setState(() => _focused = hasFocus);
          widget.onFocusChange?.call(hasFocus);
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && _isSelect(event.logicalKey)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: _focused ? 1.045 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: _focused ? TvColors.cardFocused : TvColors.card,
              borderRadius: radius,
              border: Border.all(
                color: _focused ? TvColors.red : TvColors.white12,
                width: _focused ? 3 : 1,
              ),
              boxShadow: [
                if (_focused)
                  BoxShadow(
                    color: TvColors.red.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 18, 14),
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      top: -10,
                      child: Text(
                        widget.channel.number.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 40,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: _focused
                              ? TvColors.red.withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channel.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _focused ? TvColors.red : TvColors.white54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.channel.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 27,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              widget.isLast
                                  ? Icons.play_circle_fill_rounded
                                  : Icons.live_tv_rounded,
                              size: 18,
                              color: widget.isLast
                                  ? TvColors.red
                                  : TvColors.white54,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isLast ? '上次观看' : '直播',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: widget.isLast
                                    ? TvColors.red
                                    : TvColors.white54,
                              ),
                            ),
                          ],
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
}
