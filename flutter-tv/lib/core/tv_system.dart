import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 电视端原生能力：屏幕常亮、音频焦点、退出。
class TvSystem {
  TvSystem._();

  static const MethodChannel _channel = MethodChannel('cctv/tv/system');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<void> _invoke(String method, [Object? args]) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 非 Android 环境或测试。
    } on PlatformException {
      // 忽略。
    }
  }

  static Future<void> setKeepScreenOn(bool enabled) =>
      _invoke('setKeepScreenOn', enabled);

  static Future<void> requestAudioFocus() => _invoke('requestAudioFocus');

  static Future<void> abandonAudioFocus() => _invoke('abandonAudioFocus');

  static Future<void> finish() => _invoke('finish');
}
