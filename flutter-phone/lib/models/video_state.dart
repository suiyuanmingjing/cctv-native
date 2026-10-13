/// WebView 中 <video> 的实时状态，由注入脚本每 500ms 上报一次。
class VideoState {
  const VideoState({
    this.found = false,
    this.paused = true,
    this.muted = false,
    this.readyState = 0,
    this.buffering = false,
    this.currentTime = 0,
    this.width = 0,
    this.height = 0,
    this.error = '',
    this.siteMessage = '',
    this.stage = false,
  });

  static const empty = VideoState();

  final bool found;
  final bool paused;
  final bool muted;
  final int readyState;
  final bool buffering;
  final double currentTime;
  final int width;
  final int height;
  final String error;
  final String siteMessage;
  final bool stage;

  bool get hasPicture => found && readyState >= 2 && error.isEmpty;
  bool get isPlaying => hasPicture && !paused;

  String get resolutionLabel {
    if (height >= 2160) return '4K';
    if (height >= 1440) return '2K';
    if (height >= 1080) return '1080P';
    if (height >= 720) return '720P';
    if (height >= 540) return '540P';
    if (height >= 480) return '480P';
    if (height > 0) return '${height}P';
    return '';
  }

  factory VideoState.fromJson(Map<String, dynamic> json) {
    double asDouble(Object? value) =>
        (value as num?)?.toDouble() ?? 0.0;
    int asInt(Object? value) => (value as num?)?.toInt() ?? 0;

    return VideoState(
      found: json['found'] == true,
      paused: json['paused'] != false,
      muted: json['muted'] == true,
      readyState: asInt(json['readyState']),
      buffering: json['buffering'] == true,
      currentTime: asDouble(json['currentTime']),
      width: asInt(json['width']),
      height: asInt(json['height']),
      error: (json['error'] as String?)?.trim() ?? '',
      siteMessage: (json['siteMessage'] as String?)?.trim() ?? '',
      stage: json['stage'] == true,
    );
  }
}
