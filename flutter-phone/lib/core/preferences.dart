import 'package:shared_preferences/shared_preferences.dart';

/// 本地偏好：上次频道、自动全屏、保持常亮。
class AppPreferences {
  AppPreferences._();

  static const _lastChannelKey = 'last_channel_id';
  static const _autoFullscreenKey = 'auto_fullscreen';
  static const _keepScreenOnKey = 'keep_screen_on';

  static Future<SharedPreferences>? _pending;

  static Future<SharedPreferences> get _prefs =>
      _pending ??= SharedPreferences.getInstance();

  static Future<String?> lastChannelId() async =>
      (await _prefs).getString(_lastChannelKey);

  static Future<void> setLastChannelId(String id) async {
    await (await _prefs).setString(_lastChannelKey, id);
  }

  static Future<bool> autoFullscreen() async =>
      (await _prefs).getBool(_autoFullscreenKey) ?? false;

  static Future<void> setAutoFullscreen(bool value) async {
    await (await _prefs).setBool(_autoFullscreenKey, value);
  }

  static Future<bool> keepScreenOn() async =>
      (await _prefs).getBool(_keepScreenOnKey) ?? true;

  static Future<void> setKeepScreenOn(bool value) async {
    await (await _prefs).setBool(_keepScreenOnKey, value);
  }
}
