import 'package:shared_preferences/shared_preferences.dart';

class TvPreferences {
  TvPreferences._();

  static const _lastChannelKey = 'tv_last_channel_id';
  static Future<SharedPreferences>? _pending;

  static Future<SharedPreferences> get _prefs =>
      _pending ??= SharedPreferences.getInstance();

  static Future<String?> lastChannelId() async =>
      (await _prefs).getString(_lastChannelKey);

  static Future<void> setLastChannelId(String id) async {
    await (await _prefs).setString(_lastChannelKey, id);
  }
}
