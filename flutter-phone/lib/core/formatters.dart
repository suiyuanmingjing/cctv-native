/// 秒数格式化为 00:00 / 00:00:00。
String formatWatchTime(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) seconds = 0;
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 从版本号字符串中取主版本，例如 131.0.6778.135 -> 131。
int majorVersion(String version) {
  final match = RegExp(r'^\s*(\d+)').firstMatch(version);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}
