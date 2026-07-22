import 'package:flutter/foundation.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/liked_songs_service.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/youtube_service.dart';

const String kLikedSongsPlaylistId = 'liked-songs';

class LibraryProvider extends ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;

  List<Playlist> madeForYou = [];
  List<Playlist> topMixes = [];
  List<Track> recentlyPlayed = [];
  List<Playlist> userPlaylists = [];
  List<Track> likedSongs = [];

  final Set<String> _likedVideoIds = {};

  Playlist get likedSongsPlaylist => Playlist(
    id: kLikedSongsPlaylistId,
    title: 'Liked Songs',
    subtitle: '${likedSongs.length} songs',
    thumbnailUrl: likedSongs.isNotEmpty ? likedSongs.first.thumbnailUrl : '',
    tracks: likedSongs,
    isFromYoutube: false,
  );

  bool isLiked(Track track) {
    final videoId = track.videoId;
    return videoId != null && _likedVideoIds.contains(videoId);
  }

  Future<void> refresh() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    await Future.wait([
      _refreshYoutubePlaylists(),
      _refreshLikedSongs(),
      _refreshRecentlyPlayed(),
    ]);

    isLoading = false;
    notifyListeners();
  }

  Future<void> _refreshYoutubePlaylists() async {
    try {
      userPlaylists = await YoutubeService.fetchMyPlaylists();
      _splitPlaylists();
    } catch (error, stackTrace) {
      debugPrint('LibraryProvider: playlist refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage =
          "Couldn't load your YouTube playlists. Pull to refresh to try again.";
      userPlaylists = [];
      madeForYou = [];
      topMixes = [];
    }
  }

  Future<void> _refreshLikedSongs() async {
    try {
      final liked = await LikedSongsService.fetchAll();
      likedSongs = liked;
      _likedVideoIds
        ..clear()
        ..addAll(liked.map((t) => t.videoId).whereType<String>());
    } catch (error, stackTrace) {
      debugPrint('LibraryProvider: liked songs refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _refreshRecentlyPlayed() async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 180));
      final events = await ListeningHistoryService.eventsSince(since);
      final seen = <String>{};
      final tracks = <Track>[];
      for (final event in events.reversed) {
        if (!seen.add(event.videoId)) continue;
        tracks.add(
          Track(
            id: 'yt-${event.videoId}',
            title: event.title,
            artist: event.artist,
            thumbnailUrl: event.thumbnailUrl,
            videoId: event.videoId,
            channelId: event.channelId,
          ),
        );
        if (tracks.length >= 15) break;
      }
      recentlyPlayed = tracks;
    } catch (error, stackTrace) {
      debugPrint('LibraryProvider: recently played refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _splitPlaylists() {
    final half = (userPlaylists.length / 2).ceil();
    madeForYou = userPlaylists.take(half).toList();
    topMixes = userPlaylists.skip(half).toList();
  }

  Future<void> toggleLike(Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;
    final alreadyLiked = _likedVideoIds.contains(videoId);

    _applyLikeState(videoId: videoId, track: track, liked: !alreadyLiked);
    notifyListeners();

    try {
      if (alreadyLiked) {
        await LikedSongsService.unlike(videoId);
      } else {
        await LikedSongsService.like(track);
      }
    } catch (error) {
      _applyLikeState(videoId: videoId, track: track, liked: alreadyLiked);
      notifyListeners();
      rethrow;
    }
  }

  void _applyLikeState({
    required String videoId,
    required Track track,
    required bool liked,
  }) {
    if (liked) {
      _likedVideoIds.add(videoId);
      if (likedSongs.any((t) => t.videoId == videoId)) return;
      likedSongs = [track, ...likedSongs];
    } else {
      _likedVideoIds.remove(videoId);
      likedSongs = likedSongs.where((t) => t.videoId != videoId).toList();
    }
  }

  Future<Playlist> createPlaylist(
    String title, {
    String description = '',
    String privacyStatus = 'private',
  }) async {
    final playlist = await YoutubeService.createPlaylist(
      title,
      description: description,
      privacyStatus: privacyStatus,
    );
    userPlaylists = [playlist, ...userPlaylists];
    _splitPlaylists();
    notifyListeners();
    return playlist;
  }

  Future<Playlist> loadTracks(Playlist playlist) async {
    if (playlist.tracks.isNotEmpty) return playlist;
    final tracks = await YoutubeService.fetchPlaylistTracks(playlist.id);
    final hydrated = playlist.copyWith(tracks: tracks);
    _replacePlaylist(hydrated);
    return hydrated;
  }

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) {
      throw YoutubeApiException('This track cannot be added to a playlist.');
    }

    await YoutubeService.addVideoToPlaylist(playlist.id, videoId);

    final current = userPlaylists.firstWhere(
      (p) => p.id == playlist.id,
      orElse: () => playlist,
    );
    final updated = current.tracks.isEmpty
        ? current.copyWith(itemCount: current.itemCount + 1)
        : current.copyWith(
            tracks: [...current.tracks, track],
            itemCount: current.itemCount + 1,
          );
    _replacePlaylist(updated);
  }

  Future<Playlist> updatePlaylist(
    Playlist playlist, {
    required String title,
    required String description,
  }) async {
    await YoutubeService.updatePlaylist(
      playlist.id,
      title: title,
      description: description,
    );
    final subtitle = description.isEmpty
        ? '${playlist.itemCount} videos'
        : description;
    final updated = playlist.copyWith(title: title, subtitle: subtitle);
    _replacePlaylist(updated);
    return updated;
  }

  Future<Playlist> removeTrackFromPlaylist(
    Playlist playlist,
    Track track,
  ) async {
    final itemId = track.playlistItemId;
    if (itemId == null || itemId.isEmpty) {
      throw YoutubeApiException(
        'This track cannot be removed from the playlist.',
      );
    }

    await YoutubeService.removeVideoFromPlaylist(itemId);

    final current = userPlaylists.firstWhere(
      (p) => p.id == playlist.id,
      orElse: () => playlist,
    );
    final updated = current.copyWith(
      tracks: current.tracks.where((t) => t.id != track.id).toList(),
      itemCount: (current.itemCount - 1).clamp(0, current.itemCount),
    );
    _replacePlaylist(updated);
    return updated;
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    await YoutubeService.deletePlaylist(playlist.id);
    userPlaylists = userPlaylists.where((p) => p.id != playlist.id).toList();
    _splitPlaylists();
    notifyListeners();
  }

  void _replacePlaylist(Playlist updated) {
    Playlist swap(Playlist p) => p.id == updated.id ? updated : p;
    userPlaylists = userPlaylists.map(swap).toList();
    madeForYou = madeForYou.map(swap).toList();
    topMixes = topMixes.map(swap).toList();
    notifyListeners();
  }
}
