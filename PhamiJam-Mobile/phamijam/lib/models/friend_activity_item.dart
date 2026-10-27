import 'package:phamijam/models/friend.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/models/track.dart';

class FriendActivityItem {
  final Friend friend;
  final PlayEvent event;

  const FriendActivityItem({required this.friend, required this.event});

  Track toTrack() => Track(
    id: 'yt-${event.videoId}',
    title: event.title,
    artist: event.artist,
    thumbnailUrl: event.thumbnailUrl,
    videoId: event.videoId,
    channelId: event.channelId,
  );
}
