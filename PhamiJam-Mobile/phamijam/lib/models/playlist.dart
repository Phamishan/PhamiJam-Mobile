import 'package:phamijam/models/track.dart';

class Playlist {
  final String id;
  final String title;
  final String subtitle;
  final String thumbnailUrl;
  final List<Track> tracks;
  final bool isFromYoutube;
  final bool isPinned;
  final bool isOwnedByUser;
  final int itemCount;
  final String privacyStatus;

  const Playlist({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    this.tracks = const [],
    this.isFromYoutube = true,
    this.isPinned = false,
    this.isOwnedByUser = true,
    int? itemCount,
    this.privacyStatus = 'public',
  }) : itemCount = itemCount ?? tracks.length;

  bool get isPrivate => privacyStatus == 'private';

  Playlist copyWith({
    String? title,
    String? subtitle,
    List<Track>? tracks,
    int? itemCount,
    bool? isPinned,
    String? privacyStatus,
  }) => Playlist(
    id: id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    thumbnailUrl: thumbnailUrl,
    tracks: tracks ?? this.tracks,
    isFromYoutube: isFromYoutube,
    isPinned: isPinned ?? this.isPinned,
    isOwnedByUser: isOwnedByUser,
    itemCount: itemCount ?? this.itemCount,
    privacyStatus: privacyStatus ?? this.privacyStatus,
  );
}
