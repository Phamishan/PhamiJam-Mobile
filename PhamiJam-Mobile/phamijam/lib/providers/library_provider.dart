import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:phamijam/services/liked_songs_service.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
import 'package:phamijam/services/playlist_cover_service.dart';
import 'package:phamijam/services/playlist_pin_service.dart';
import 'package:phamijam/services/youtube_service.dart';

const String kLikedSongsPlaylistId = 'liked-songs';
const String kLocalFilesPlaylistId = 'local-files';

class LibraryProvider extends ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;
  bool needsGoogleReconnect = false;
  List<Playlist> madeForYou = [];
  List<Playlist> topMixes = [];
  List<Track> recentlyPlayed = [];
  List<Playlist> userPlaylists = [];
  List<Track> likedSongs = [];
  List<Track> localFiles = [];
  bool hasConnectedDriveFolder = false;
  final Set<String> _likedVideoIds = {};
  List<String> _pinnedOrder = [];
  Set<String> get _pinnedIds => _pinnedOrder.toSet();
  bool isPinned(String playlistId) => _pinnedIds.contains(playlistId);

  List<String> get pinnedPlaylistIds => List.unmodifiable(_pinnedOrder);
  Map<String, String> _coverOverrides = {};

  Playlist get likedSongsPlaylist => Playlist(
    id: kLikedSongsPlaylistId,
    title: 'Liked Songs',
    subtitle: '${likedSongs.length} songs',
    thumbnailUrl: likedSongs.isNotEmpty ? likedSongs.first.thumbnailUrl : '',
    tracks: likedSongs,
    isFromYoutube: false,
  );

  Playlist get localFilesPlaylist => Playlist(
    id: kLocalFilesPlaylistId,
    title: 'Google Drive',
    subtitle: '${localFiles.length} songs',
    thumbnailUrl: '',
    tracks: localFiles,
    isFromYoutube: false,
  );

  bool isLiked(Track track) {
    final videoId = track.videoId;
    return videoId != null && _likedVideoIds.contains(videoId);
  }

  Future<void> refresh({bool silentOnly = false}) async {
    Log.i('library', 'refresh started (silentOnly=$silentOnly)');
    final refreshWatch = Stopwatch()..start();
    isLoading = true;
    errorMessage = null;
    needsGoogleReconnect = false;
    notifyListeners();

    await _loadPinnedOrder();
    await _loadCoverOverrides();
    _watchMixedPlaylists();
    await Future.wait([
      _refreshYoutubePlaylists(silentOnly: silentOnly),
      _refreshLikedSongs(),
      _refreshRecentlyPlayed(),
      refreshLocalFiles(),
    ]);

    Log.i(
      'library',
      'refresh finished in ${refreshWatch.elapsedMilliseconds} ms: '
          '${userPlaylists.length} playlists, ${likedSongs.length} liked, '
          '${recentlyPlayed.length} recent, ${localFiles.length} Drive songs'
          '${errorMessage == null ? '' : ', error: $errorMessage'}',
    );
    isLoading = false;
    notifyListeners();
  }

  Future<void> connectGoogleAccount() async {
    Log.i('library', 'connecting Google account from library');
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final token = await GoogleAuthService.ensureAccessToken(forceOnline: true);
    if (token == null || token.isEmpty) {
      Log.w('library', 'Google connect returned no access token');
      isLoading = false;
      errorMessage = 'Could not connect your Google account. Please try again.';
      notifyListeners();
      return;
    }

    needsGoogleReconnect = false;
    await _loadCoverOverrides();
    _watchMixedPlaylists();
    await Future.wait([
      _refreshYoutubePlaylists(),
      _refreshLikedSongs(),
      _refreshRecentlyPlayed(),
      refreshLocalFiles(),
    ]);
    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadPinnedOrder() async {
    try {
      _pinnedOrder = await PlaylistPinService.fetchAll();
    } catch (error, stackTrace) {
      Log.e('library', 'pinned playlists refresh failed', error, stackTrace);
    }
  }

  List<Playlist> mixedPlaylists = [];
  StreamSubscription<List<Playlist>>? _mixedPlaylistsSub;
  String? _mixedPlaylistsUid;

  Playlist _withCover(Playlist playlist) {
    final override = _coverOverrides[playlist.id];
    final withCover = override == null
        ? playlist.copyWith(clearCustomCover: true)
        : playlist.copyWith(customCoverUrl: override);
    return withCover.copyWith(isPinned: isPinned(playlist.id));
  }

  void _reapplyCoversToMixed() {
    mixedPlaylists = mixedPlaylists.map(_withCover).toList();
  }

  Playlist? mixedPlaylistById(String id) {
    for (final playlist in mixedPlaylists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  void _watchMixedPlaylists() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_mixedPlaylistsSub != null && _mixedPlaylistsUid == uid) return;
    _mixedPlaylistsSub?.cancel();
    _mixedPlaylistsUid = uid;
    _mixedPlaylistsSub = MixedPlaylistService.watchAll().listen(
      (playlists) {
        Log.i('library', 'mixed playlists updated: ${playlists.length}');
        mixedPlaylists = playlists.map(_withCover).toList();
        notifyListeners();
        for (final id in MixedPlaylistService.takePlaylistsNeedingRepair()) {
          unawaited(
            MixedPlaylistService.repairMissingMetadata(id).catchError((
              Object error,
            ) {
              Log.w('library', 'repairing a PhamiJam playlist failed', error);
            }),
          );
        }
      },
      onError: (Object error) {
        Log.e('library', 'mixed playlists watch failed', error);
      },
    );
  }

  void clearMixedPlaylists() {
    _mixedPlaylistsSub?.cancel();
    _mixedPlaylistsSub = null;
    _mixedPlaylistsUid = null;
    mixedPlaylists = [];
    notifyListeners();
  }

  Future<Playlist> createMixedPlaylist(String title) async {
    Log.i('library', 'creating PhamiJam playlist "$title"');
    final id = await MixedPlaylistService.create(title);
    return Playlist(
      id: id,
      title: title,
      subtitle: '0 songs',
      thumbnailUrl: '',
      isFromYoutube: false,
      isOwnedByUser: true,
      itemCount: 0,
      privacyStatus: 'private',
    );
  }

  Future<void> renameMixedPlaylist(Playlist playlist, String title) {
    Log.i('library', 'renaming PhamiJam playlist ${playlist.id}');
    return MixedPlaylistService.rename(playlist.id, title);
  }

  Future<void> deleteMixedPlaylist(Playlist playlist) async {
    Log.i('library', 'deleting PhamiJam playlist ${playlist.id}');
    await MixedPlaylistService.delete(playlist.id);
    if (_coverOverrides.containsKey(playlist.id)) {
      try {
        await PlaylistCoverService.remove(playlist.id);
      } catch (_) {}
    }
  }

  Future<int> addTracksToMixedPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    bool allowDuplicates = false,
  }) async {
    final added = await MixedPlaylistService.addTracks(
      playlist.id,
      tracks,
      allowDuplicates: allowDuplicates,
    );
    Log.i(
      'library',
      'added $added of ${tracks.length} songs to PhamiJam playlist ${playlist.id}',
    );
    return added;
  }

  Future<void> removeTrackFromMixedPlaylist(Playlist playlist, Track track) {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return Future.value();
    return MixedPlaylistService.removeVideoId(playlist.id, videoId);
  }

  StreamSubscription<Map<String, String>>? _coverOverridesSub;

  Future<void> _loadCoverOverrides() async {
    try {
      _coverOverrides = await PlaylistCoverService.fetchAll();
    } catch (error, stackTrace) {
      Log.e('library', 'cover overrides refresh failed', error, stackTrace);
    }
    _watchCoverOverrides();
  }

  void _watchCoverOverrides() {
    _coverOverridesSub?.cancel();
    _coverOverridesSub = PlaylistCoverService.watchAll().listen((overrides) {
      _coverOverrides = overrides;
      userPlaylists = userPlaylists.map((p) {
        final override = overrides[p.id];
        return p.copyWith(
          customCoverUrl: override,
          clearCustomCover: override == null,
        );
      }).toList();
      _splitPlaylists();
      _reapplyCoversToMixed();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _mixedPlaylistsSub?.cancel();
    _coverOverridesSub?.cancel();
    super.dispose();
  }

  List<Playlist> _applyPinState(List<Playlist> playlists) {
    final pinnedIds = _pinnedIds;
    final pinnedIndex = {
      for (var i = 0; i < _pinnedOrder.length; i++) _pinnedOrder[i]: i,
    };
    final withFlags = playlists
        .map(
          (p) => p.copyWith(
            isPinned: pinnedIds.contains(p.id),
            customCoverUrl: _coverOverrides[p.id],
          ),
        )
        .toList();
    final pinned = withFlags.where((p) => p.isPinned).toList()
      ..sort(
        (a, b) => (pinnedIndex[a.id] ?? 0).compareTo(pinnedIndex[b.id] ?? 0),
      );
    final rest = withFlags.where((p) => !p.isPinned).toList();
    return [...pinned, ...rest];
  }

  Playlist _findPlaylist(String playlistId) => userPlaylists.firstWhere(
    (p) => p.id == playlistId,
    orElse: () => throw StateError('Playlist not found: $playlistId'),
  );

  void _replaceInLists(Playlist updated) {
    userPlaylists = userPlaylists
        .map((p) => p.id == updated.id ? updated : p)
        .toList();
    _splitPlaylists();
  }

  Future<Playlist> setPlaylistCover(Playlist playlist, File imageFile) async {
    Log.i('library', 'uploading cover for playlist ${playlist.id}');
    final url = await PlaylistCoverService.upload(playlist.id, imageFile);
    _coverOverrides = {..._coverOverrides, playlist.id: url};
    final updated = playlist.copyWith(customCoverUrl: url);
    try {
      _replaceInLists(_findPlaylist(playlist.id).copyWith(customCoverUrl: url));
    } catch (_) {}
    _reapplyCoversToMixed();
    notifyListeners();
    return updated;
  }

  Future<Playlist> removePlaylistCover(Playlist playlist) async {
    Log.i('library', 'removing cover for playlist ${playlist.id}');
    await PlaylistCoverService.remove(playlist.id);
    _coverOverrides = {..._coverOverrides}..remove(playlist.id);
    final updated = playlist.copyWith(clearCustomCover: true);
    try {
      _replaceInLists(
        _findPlaylist(playlist.id).copyWith(clearCustomCover: true),
      );
    } catch (_) {}
    _reapplyCoversToMixed();
    notifyListeners();
    return updated;
  }

  Future<void> togglePin(Playlist playlist) async {
    final pinning = !isPinned(playlist.id);
    Log.i(
      'library',
      '${pinning ? 'pinning' : 'unpinning'} playlist ${playlist.id}',
    );
    if (pinning) {
      _pinnedOrder = [playlist.id, ..._pinnedOrder];
    } else {
      _pinnedOrder = _pinnedOrder.where((id) => id != playlist.id).toList();
    }
    userPlaylists = _applyPinState(userPlaylists);
    _splitPlaylists();
    _reapplyCoversToMixed();
    notifyListeners();

    try {
      if (pinning) {
        await PlaylistPinService.pin(playlist.id);
      } else {
        await PlaylistPinService.unpin(playlist.id);
      }
    } catch (error) {
      Log.e('library', 'pin change failed, reverting', error);
      if (pinning) {
        _pinnedOrder = _pinnedOrder.where((id) => id != playlist.id).toList();
      } else {
        _pinnedOrder = [playlist.id, ..._pinnedOrder];
      }
      userPlaylists = _applyPinState(userPlaylists);
      _splitPlaylists();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _refreshYoutubePlaylists({bool silentOnly = false}) async {
    if (silentOnly && !await YoutubeService.hasSilentAccess()) {
      Log.w('library', 'no silent Google access, library needs reconnect');
      needsGoogleReconnect = true;
      errorMessage = 'Connect your Google account to view your Library.';
      userPlaylists = [];
      madeForYou = [];
      topMixes = [];
      return;
    }

    try {
      userPlaylists = _applyPinState(await YoutubeService.fetchMyPlaylists());
      _splitPlaylists();
    } catch (error, stackTrace) {
      Log.e('library', 'YouTube playlists refresh failed', error, stackTrace);
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
      Log.e('library', 'liked songs refresh failed', error, stackTrace);
    }
  }

  Future<void> refreshLocalFiles() async {
    try {
      final files = await GoogleDriveService.listAudioFiles();
      Log.i(
        'drive',
        files == null
            ? 'no Drive folder connected'
            : 'Drive folder has ${files.length} audio files',
      );
      hasConnectedDriveFolder = files != null;
      localFiles = files ?? [];
      notifyListeners();
    } catch (error, stackTrace) {
      Log.e('drive', 'Drive files refresh failed', error, stackTrace);
    }
  }

  void clearDriveConnection() {
    Log.i('drive', 'Drive connection cleared in library');
    hasConnectedDriveFolder = false;
    localFiles = [];
    notifyListeners();
  }

  Future<void> _refreshRecentlyPlayed() async {
    try {
      final events = await ListeningHistoryService.recentEvents(limit: 100);
      final seen = <String>{};
      final tracks = <Track>[];
      for (final event in events) {
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
      Log.e('library', 'recently played refresh failed', error, stackTrace);
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
    Log.i('library', '${alreadyLiked ? 'unliking' : 'liking'} $videoId');

    _applyLikeState(videoId: videoId, track: track, liked: !alreadyLiked);
    notifyListeners();

    try {
      if (alreadyLiked) {
        await LikedSongsService.unlike(videoId);
      } else {
        await LikedSongsService.like(track);
      }
    } catch (error) {
      Log.e('library', 'like change failed for $videoId, reverting', error);
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
    Log.i('library', 'creating YouTube playlist "$title" ($privacyStatus)');
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
    Log.i('library', 'loading tracks for playlist ${playlist.id}');
    final tracks = await YoutubeService.fetchPlaylistTracks(playlist.id);
    Log.i('library', 'loaded ${tracks.length} tracks for ${playlist.id}');
    final hydrated = playlist.copyWith(tracks: tracks);
    _replacePlaylist(hydrated);
    return hydrated;
  }

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) {
      throw YoutubeApiException('This track cannot be added to a playlist.');
    }

    Log.i('library', 'adding $videoId to playlist ${playlist.id}');
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
    String? privacyStatus,
  }) async {
    Log.i(
      'library',
      'updating playlist ${playlist.id} (privacy $privacyStatus)',
    );
    await YoutubeService.updatePlaylist(
      playlist.id,
      title: title,
      description: description,
      privacyStatus: privacyStatus,
    );
    final subtitle = description.isEmpty
        ? '${playlist.itemCount} videos'
        : description;
    final updated = playlist.copyWith(
      title: title,
      subtitle: subtitle,
      privacyStatus: privacyStatus,
    );
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

    Log.i('library', 'removing item from playlist ${playlist.id}');
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
    Log.i('library', 'deleting playlist ${playlist.id}');
    await YoutubeService.deletePlaylist(playlist.id);
    userPlaylists = userPlaylists.where((p) => p.id != playlist.id).toList();
    _splitPlaylists();
    final wasPinned = _pinnedOrder.remove(playlist.id);
    notifyListeners();
    if (wasPinned) {
      try {
        await PlaylistPinService.unpin(playlist.id);
      } catch (error) {
        Log.e('library', 'unpin on delete failed', error);
      }
    }
  }

  void _replacePlaylist(Playlist updated) {
    Playlist swap(Playlist p) => p.id == updated.id ? updated : p;
    userPlaylists = userPlaylists.map(swap).toList();
    madeForYou = madeForYou.map(swap).toList();
    topMixes = topMixes.map(swap).toList();
    notifyListeners();
  }
}
