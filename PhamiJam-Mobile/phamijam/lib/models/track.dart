class Track {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;
  final String? videoId;
  final String? channelId;
  final String? playlistItemId;
  final int? viewCount;
  final DateTime? addedAt;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.duration = Duration.zero,
    this.videoId,
    this.channelId,
    this.playlistItemId,
    this.viewCount,
    this.addedAt,
  });

  Track withViewCount(int? views) => Track(
    id: id,
    title: title,
    artist: artist,
    thumbnailUrl: thumbnailUrl,
    duration: duration,
    videoId: videoId,
    channelId: channelId,
    playlistItemId: playlistItemId,
    viewCount: views,
    addedAt: addedAt,
  );

  bool get isDriveSourced => (videoId ?? '').startsWith('drive:');
}
