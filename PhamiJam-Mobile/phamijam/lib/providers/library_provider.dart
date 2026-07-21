import 'package:flutter/foundation.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/youtube_service.dart';

class LibraryProvider extends ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;

  List<Playlist> madeForYou = [];
  List<Playlist> topMixes = [];
  List<Track> recentlyPlayed = [];
  List<Playlist> userPlaylists = [];
  List<Track> likedSongs = [];

  String? _likedPlaylistId;

  Playlist get likedSongsPlaylist => Playlist(
    id: _likedPlaylistId ?? 'liked-songs',
    title: 'Liked Songs',
    subtitle: '${likedSongs.length} liked videos',
    thumbnailUrl: likedSongs.isNotEmpty ? likedSongs.first.thumbnailUrl : '',
    tracks: likedSongs,
  );

  Future<void> refresh() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        YoutubeService.fetchMyPlaylists(),
        _likedPlaylistId != null
            ? Future.value(_likedPlaylistId)
            : YoutubeService.fetchLikedVideosPlaylistId(),
      ]);
      final playlists = results[0] as List<Playlist>;
      _likedPlaylistId = results[1] as String?;
      final liked = _likedPlaylistId == null
          ? <Track>[]
          : await YoutubeService.fetchPlaylistTracks(_likedPlaylistId!);

      userPlaylists = playlists;
      _splitPlaylists();
      likedSongs = liked;
      recentlyPlayed = liked.take(10).toList();
    } catch (error, stackTrace) {
      debugPrint('LibraryProvider: refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage =
          "Couldn't load your YouTube library. Pull to refresh to try again.";
      userPlaylists = [];
      madeForYou = [];
      topMixes = [];
      likedSongs = [];
      recentlyPlayed = [];
    }

    isLoading = false;
    notifyListeners();
  }

  void _splitPlaylists() {
    final half = (userPlaylists.length / 2).ceil();
    madeForYou = userPlaylists.take(half).toList();
    topMixes = userPlaylists.skip(half).toList();
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
