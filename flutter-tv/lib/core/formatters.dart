/// 秒数格式化为 mm:ss / h:mm:ss。
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
