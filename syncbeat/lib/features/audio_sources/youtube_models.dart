import 'youtube_channels.dart';

class YoutubeVideo {
  YoutubeVideo(this.metadata, {this.channelInfo}) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      throw const FormatException('ID video YouTube non valido');
    }
  }
  final Map<String, dynamic> metadata;
  final YoutubeChannelInfo? channelInfo;
  String? get channelId => metadata['channel_id'] as String?;
  Uri? get channelUrl =>
      channelId != null && RegExp(r'^UC[a-zA-Z0-9_-]{22}$').hasMatch(channelId!)
      ? Uri.https('www.youtube.com', '/channel/$channelId')
      : null;
  YoutubeVideo withChannelInfo(YoutubeChannelInfo info) =>
      YoutubeVideo(metadata, channelInfo: info);

  String get id => metadata['id'] as String? ?? '';
  String get title => metadata['title'] as String? ?? '';
  String get channel =>
      metadata['channel'] as String? ?? metadata['uploader'] as String? ?? '';
  int get duration => (metadata['duration'] as num?)?.round() ?? 0;
  String? get thumbnail {
    final direct = metadata['thumbnail'];
    if (direct is String && direct.isNotEmpty) return direct;
    // Flat search results expose thumbnails as a list instead of a single URL.
    final thumbnails = metadata['thumbnails'];
    if (thumbnails is List) {
      for (final item in thumbnails.reversed) {
        if (item is Map && item['url'] is String) return item['url'] as String;
      }
    }
    return null;
  }

  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': id});
  // A verified badge authenticates the channel, not the recording's rights.
  bool get isVerifiedChannel => metadata['channel_is_verified'] == true;
}
