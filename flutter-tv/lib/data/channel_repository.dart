import 'package:flutter/services.dart';

import '../models/channel.dart';

class ChannelRepository {
  ChannelRepository._();

  static List<Channel>? _cache;

  static Future<List<Channel>> load({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/channel-list.json');
    final channels = Channel.parseCatalog(raw);
    if (channels.isEmpty) {
      throw const FormatException('频道列表为空');
    }
    _cache = channels;
    return channels;
  }
}
