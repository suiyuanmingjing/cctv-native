import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 与 Android 原生层通信：媒体音量、窗口亮度、屏幕常亮、内核版本、外部浏览器、音频焦点。
class NativeSystem {
  NativeSystem._();

  static const MethodChannel _channel = MethodChannel('com.cctv.live/system');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<String> webViewVersion() async =>
      (await _invoke<String>('getWebViewVersion')) ?? '';

  static Future<String> appVersion() async =>
      (await _invoke<String>('getAppVersion')) ?? '1.0.0';

  static Future<double> getVolume() async =>
      (await _invoke<double>('getVolume')) ?? 0.5;

  static Future<void> setVolume(double value) =>
      _invoke<void>('setVolume', value.clamp(0.0, 1.0));

  static Future<double> getBrightness() async =>
      (await _invoke<double>('getBrightness')) ?? 0.5;

  static Future<void> setBrightness(double value) =>
      _invoke<void>('setBrightness', value.clamp(0.01, 1.0));

  static Future<void> resetBrightness() =>
      _invoke<void>('resetBrightness');

  static Future<void> setKeepScreenOn(bool enabled) =>
      _invoke<void>('setKeepScreenOn', enabled);

  static Future<bool> openUrl(String url) async =>
      (await _invoke<bool>('openUrl', url)) ?? false;

  static Future<bool> openWebViewStore() async =>
      (await _invoke<bool>('openWebViewStore')) ?? false;

  static Future<void> requestAudioFocus() =>
      _invoke<void>('requestAudioFocus');

  static Future<void> abandonAudioFocus() =>
      _invoke<void>('abandonAudioFocus');

  /// 原生层会以 `audioFocus` 方法回调 `loss` / `gain`。
  static void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    if (!isAndroid) return;
    _channel.setMethodCallHandler(handler);
  }
}
