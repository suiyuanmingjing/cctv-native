import 'dart:io';

import 'package:cctv_flutter/core/formatters.dart';
import 'package:cctv_flutter/models/channel.dart';
import 'package:cctv_flutter/models/video_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('频道列表', () {
    late List<Channel> channels;

    setUpAll(() {
      final raw = File('assets/channel-list.json').readAsStringSync();
      channels = Channel.parseCatalog(raw);
    });

    test('解析出 18 个频道并按 number 排序', () {
      expect(channels.length, 18);
      expect(channels.first.id, 'cctv1');
      expect(channels.last.id, 'cctv17');
      for (var i = 1; i < channels.length; i++) {
        expect(
          channels[i].number,
          greaterThan(channels[i - 1].number),
        );
      }
    });

    test('CCTV-9 与 CCTV-14 使用官网特殊 slug', () {
      final cctv9 = channels.firstWhere((c) => c.id == 'cctv9');
      final cctv14 = channels.firstWhere((c) => c.id == 'cctv14');
      expect(cctv9.webKey, 'cctvjilu');
      expect(cctv9.webUrl, 'https://tv.cctv.com/live/cctvjilu/');
      expect(cctv14.webKey, 'cctvchild');
      expect(cctv14.webUrl, 'https://tv.cctv.com/live/cctvchild/');
    });

    test('每个频道都有可用的官方直播地址', () {
      for (final channel in channels) {
        expect(channel.id, isNotEmpty);
        expect(channel.label, isNotEmpty);
        expect(channel.title, isNotEmpty);
        expect(Uri.tryParse(channel.webUrl)?.host, 'tv.cctv.com');
        expect(channel.webUrl, startsWith('https://tv.cctv.com/live/'));
      }
    });

    test('缺少 label/title 时可以从 name 拆分', () {
      final channel = Channel.fromJson({
        'id': 'demo',
        'number': 1,
        'name': 'CCTV-1 综合',
        'webKey': 'cctv1',
        'webUrl': 'https://tv.cctv.com/live/cctv1/',
      });
      expect(channel.label, 'CCTV-1');
      expect(channel.title, '综合');
    });
  });

  group('格式化', () {
    test('观看时长', () {
      expect(formatWatchTime(0), '00:00');
      expect(formatWatchTime(59.9), '00:59');
      expect(formatWatchTime(65), '01:05');
      expect(formatWatchTime(3661), '1:01:01');
      expect(formatWatchTime(double.nan), '00:00');
    });

    test('内核主版本', () {
      expect(majorVersion('131.0.6778.135'), 131);
      expect(majorVersion(''), 0);
      expect(majorVersion('WebView 120'), 0);
    });
  });

  group('VideoState', () {
    test('解析注入脚本上报的状态', () {
      final state = VideoState.fromJson({
        'found': true,
        'paused': false,
        'muted': false,
        'readyState': 4,
        'buffering': false,
        'currentTime': 12.5,
        'width': 1280,
        'height': 720,
        'error': '',
        'siteMessage': '',
        'stage': true,
      });
      expect(state.hasPicture, isTrue);
      expect(state.isPlaying, isTrue);
      expect(state.resolutionLabel, '720P');
      expect(state.currentTime, 12.5);
    });

    test('错误状态不算有画面', () {
      final state = VideoState.fromJson({
        'found': true,
        'readyState': 0,
        'error': '网络错误',
      });
      expect(state.hasPicture, isFalse);
      expect(state.isPlaying, isFalse);
    });
  });
}
