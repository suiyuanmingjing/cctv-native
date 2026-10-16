import 'dart:convert';

class Channel {
  const Channel({
    required this.id,
    required this.number,
    required this.label,
    required this.title,
    required this.name,
    required this.webKey,
    required this.webUrl,
  });

  final String id;
  final int number;
  final String label;
  final String title;
  final String name;
  final String webKey;
  final String webUrl;

  String get displayName => name.isNotEmpty ? name : '$label $title';

  factory Channel.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim() ?? '';
    var label = (json['label'] as String?)?.trim() ?? '';
    var title = (json['title'] as String?)?.trim() ?? '';

    if (label.isEmpty || title.isEmpty) {
      final space = name.indexOf(' ');
      if (space > 0) {
        if (label.isEmpty) label = name.substring(0, space);
        if (title.isEmpty) title = name.substring(space + 1);
      } else if (label.isEmpty) {
        label = name;
      }
    }

    final webKey = (json['webKey'] as String?)?.trim() ?? '';
    var webUrl = (json['webUrl'] as String?)?.trim() ?? '';
    if (webUrl.isEmpty && webKey.isNotEmpty) {
      webUrl = 'https://tv.cctv.com/live/$webKey/';
    }

    return Channel(
      id: (json['id'] as String?)?.trim() ?? '',
      number: (json['number'] as num?)?.toInt() ?? 0,
      label: label,
      title: title,
      name: name,
      webKey: webKey,
      webUrl: webUrl,
    );
  }

  static List<Channel> parseCatalog(String raw) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final items = (root['channels'] as List<dynamic>?) ?? const <dynamic>[];
    final result = <Channel>[];

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      if (item['enabled'] == false) continue;
      final channel = Channel.fromJson(item);
      if (channel.id.isEmpty || channel.webUrl.isEmpty) continue;
      result.add(channel);
    }

    result.sort((a, b) => a.number.compareTo(b.number));
    return result;
  }
}
