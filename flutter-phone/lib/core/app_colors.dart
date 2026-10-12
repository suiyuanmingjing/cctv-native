import 'package:flutter/material.dart';

/// 全局配色：沿用原 Android 项目的暖褐色主页 + CCTV 红。
abstract final class AppColors {
  static const brandRed = Color(0xFFE53928);
  static const brandRedDark = Color(0xFFC62828);

  // 主页渐变
  static const homeTop = Color(0xFFA89683);
  static const homeMid = Color(0xFF9A8878);
  static const homeBottom = Color(0xFF8C7A6B);
  static const homeInk = Color(0xFF2E241C);
  static const homeInkSoft = Color(0xFF4A3B2F);

  // 频道卡片
  static const card = Color(0xFFFFFFFF);
  static const cardInk = Color(0xFF2B1B1B);
  static const cardMuted = Color(0xFF8A6A6A);

  // 播放页
  static const playerBg = Color(0xFF08080C);
  static const surface = Color(0xFF17171F);
  static const surfaceHigh = Color(0xFF242430);
  static const drawerBg = Color(0xFF1F1F29);
  static const drawerHeader = Color(0xFF2A2A38);

  static const white = Color(0xFFFFFFFF);
  static const white70 = Color(0xB3FFFFFF);
  static const white54 = Color(0x8AFFFFFF);
  static const white24 = Color(0x3DFFFFFF);
  static const white12 = Color(0x1FFFFFFF);
  static const black54 = Color(0x8A000000);
  static const live = Color(0xFFFF4D3D);
}
