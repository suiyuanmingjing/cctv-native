import 'dart:io';

import 'package:cctv_tv_flutter/core/formatters.dart';
import 'package:cctv_tv_flutter/models/channel.dart';
import 'package:cctv_tv_flutter/models/video_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('电视频道列表', () {
    late List<Channel> channels;

    setUpAll(() {
      final raw = File('assets/channel-list.json').readAsStringSync();
      channels = Channel.parseCatalog(raw);
    });

    test('解析出 18 个频道', () {
      expect(channels.length, 18);
      expect(channels.first.id, 'cctv1');
      expect(channels.last.id, 'cctv17');
    });

    test('CCTV-9 / CCTV-14 保留官网特殊 slug', () {
      final cctv9 = channels.firstWhere((c) => c.id == 'cctv9');
      final cctv14 = channels.firstWhere((c) => c.id == 'cctv14');
      expect(cctv9.webUrl, 'https://tv.cctv.com/live/cctvjilu/');
      expect(cctv14.webUrl, 'https://tv.cctv.com/live/cctvchild/');
    });
  });

  group('格式化', () {
    test('观看时长', () {
      expect(formatWatchTime(0), '00:00');
      expect(formatWatchTime(65), '01:05');
      expect(formatWatchTime(3661), '1:01:01');
    });
  });

  group('视频状态', () {
    test('readyState >= 2 才算有画面', () {
      final state = VideoState.fromJson({
        'found': true,
        'readyState': 4,
        'paused': false,
        'currentTime': 12.0,
        'width': 1920,
        'height': 1080,
      });
      expect(state.hasPicture, isTrue);
      expect(state.isPlaying, isTrue);
      expect(state.resolutionLabel, '1080P');
    });
  });
}
