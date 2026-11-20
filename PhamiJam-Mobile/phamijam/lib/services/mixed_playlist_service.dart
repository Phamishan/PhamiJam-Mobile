import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/youtube_service.dart';

const String kMixedPlaylistIdPrefix = 'mixed-';

class MixedPlaylistService {
  MixedPlaylistService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('mixedPlaylists');
  }

  static String _docId(String playlistId) =>
      playlistId.startsWith(kMixedPlaylistIdPrefix)
      ? playlistId.substring(kMixedPlaylistIdPrefix.length)
      : playlistId;

  static Stream<List<Playlist>> watchAll() {
    final collection = _collection;
    if (collection == null) return const Stream.empty();
    return collection.snapshots().map((snapshot) {
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          final aMs = aTime is Timestamp
              ? aTime.millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch;
          final bMs = bTime is Timestamp
              ? bTime.millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch;
          return bMs.compareTo(aMs);
        });
      return docs.map(_playlistFromDoc).toList();
    });
  }

  static Playlist _playlistFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawTracks = data['tracks'] is List
        ? (data['tracks'] as List).whereType<Map>().toList()
        : <Map>[];
    final tracks = <Track>[];
    var desktopOnly = 0;
    for (final raw in rawTracks) {
      final map = Map<String, dynamic>.from(raw);
      if (map['source'] == 'local') {
        desktopOnly++;
        continue;
      }
      final track = _trackFromMap(map);
      if (track != null) tracks.add(track);
      final source = (map['source'] as String?) ?? 'youtube';
      if (source == 'youtube' &&
          (((map['artist'] as String?) ?? '').isEmpty ||
              ((map['thumbnailUrl'] as String?) ?? '').isEmpty)) {
        _needsRepair.add(doc.id);
      }
    }

    final cover = tracks
        .map((t) => t.thumbnailUrl)
        .firstWhere((url) => url.isNotEmpty, orElse: () => '');
    final songLabel = '${tracks.length} song${tracks.length == 1 ? '' : 's'}';
    final subtitle = desktopOnly > 0
        ? '$songLabel · $desktopOnly desktop-only'
        : songLabel;

    return Playlist(
      id: '$kMixedPlaylistIdPrefix${doc.id}',
      title: (data['title'] as String?) ?? 'Untitled playlist',
      subtitle: subtitle,
      thumbnailUrl: cover,
      tracks: tracks,
      isFromYoutube: false,
      isOwnedByUser: true,
      itemCount: tracks.length,
      privacyStatus: 'private',
    );
  }

  static String _thumbnailFor(
    Map<String, dynamic> map,
    String videoId,
    bool isDrive,
  ) {
    final saved = (map['thumbnailUrl'] as String?) ?? '';
    if (saved.isNotEmpty || isDrive) return saved;
    return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
  }

  static final Set<String> _needsRepair = {};
  static final Set<String> _repairAttempted = {};

  static List<String> takePlaylistsNeedingRepair() {
    final ids = _needsRepair.toList();
    _needsRepair.clear();
    return ids;
  }

  static Future<void> repairMissingMetadata(String playlistId) async {
    final collection = _collection;
    if (collection == null) return;
    final doc = collection.doc(_docId(playlistId));
    final snapshot = await doc.get();
    final data = snapshot.data();
    if (data == null || data['tracks'] is! List) return;
    final tracks = (data['tracks'] as List)
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .toList();

    final details = <String, Track>{};
    for (final track in tracks) {
      final videoId = (track['videoId'] as String?) ?? '';
      final source = (track['source'] as String?) ?? 'youtube';
      if (videoId.isEmpty ||
          source != 'youtube' ||
          videoId.startsWith('drive:') ||
          _repairAttempted.contains(videoId)) {
        continue;
      }
      final artist = (track['artist'] as String?) ?? '';
      final thumb = (track['thumbnailUrl'] as String?) ?? '';
      if (artist.isNotEmpty && thumb.isNotEmpty) continue;
      if (details.length >= 25) break;
      _repairAttempted.add(videoId);
      try {
        final info = await YoutubeService.fetchVideoById(videoId);
        if (info != null) details[videoId] = info;
      } catch (error) {
        Log.w('library', 'looking up song details failed', error);
      }
    }
    if (details.isEmpty) return;

    var fixed = 0;
    for (final track in tracks) {
      final info = details[(track['videoId'] as String?) ?? ''];
      if (info == null) continue;
      var changed = false;
      if (((track['artist'] as String?) ?? '').isEmpty &&
          info.artist.isNotEmpty) {
        track['artist'] = info.artist;
        changed = true;
      }
      if (((track['thumbnailUrl'] as String?) ?? '').isEmpty &&
          info.thumbnailUrl.isNotEmpty) {
        track['thumbnailUrl'] = info.thumbnailUrl;
        changed = true;
      }
      if (((track['artistId'] as String?) ?? '').isEmpty &&
          (info.channelId ?? '').isNotEmpty) {
        track['artistId'] = info.channelId;
        changed = true;
      }
      if (changed) fixed++;
    }
    if (fixed == 0) return;
    await doc.update({
      'tracks': tracks,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Log.i(
      'library',
      'repaired details for $fixed songs in a PhamiJam playlist',
    );
  }

  static Track? _trackFromMap(Map<String, dynamic> map) {
    final videoId = map['videoId'];
    if (videoId is! String || videoId.isEmpty) return null;
    final isDrive = map['source'] == 'drive' || videoId.startsWith('drive:');
    final id = isDrive
        ? 'drive-${videoId.substring('drive:'.length)}'
        : 'yt-$videoId';
    final durationMs = map['durationMs'];
    final artistId = map['artistId'];
    return Track(
      id: id,
      title: (map['title'] as String?) ?? '',
      artist: (map['artist'] as String?) ?? '',
      thumbnailUrl: _thumbnailFor(map, videoId, isDrive),
      duration: Duration(milliseconds: durationMs is int ? durationMs : 0),
      videoId: videoId,
      channelId: artistId is String && artistId.isNotEmpty ? artistId : null,
    );
  }

  static Map<String, dynamic> _trackToMap(Track track) => {
    'source': track.isDriveSourced ? 'drive' : 'youtube',
    'videoId': track.videoId ?? '',
    'title': track.title,
    'artist': track.artist,
    'thumbnailUrl': track.thumbnailUrl,
    'durationMs': track.duration.inMilliseconds,
    'path': '',
    'artistId': track.channelId ?? '',
  };

  static Future<String> create(String title) async {
    final collection = _collection;
    if (collection == null) throw StateError('Not signed in.');
    final ref = await collection.add({
      'title': title,
      'description': '',
      'tracks': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return '$kMixedPlaylistIdPrefix${ref.id}';
  }

  static Future<void> rename(String playlistId, String title) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(playlistId)).update({
      'title': title,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> delete(String playlistId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(playlistId)).delete();
  }

  static Future<int> addTracks(String playlistId, List<Track> tracks) async {
    final collection = _collection;
    if (collection == null) throw StateError('Not signed in.');
    final ref = collection.doc(_docId(playlistId));
    return FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final existing = snapshot.data()?['tracks'] is List
          ? List<dynamic>.from(snapshot.data()!['tracks'] as List)
          : <dynamic>[];
      final knownIds = existing
          .whereType<Map>()
          .map((m) => m['videoId'])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      var added = 0;
      for (final track in tracks) {
        final videoId = track.videoId;
        if (videoId == null || videoId.isEmpty) continue;
        if (!knownIds.add(videoId)) continue;
        existing.add(_trackToMap(track));
        added++;
      }
      if (added > 0) {
        transaction.update(ref, {
          'tracks': existing,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return added;
    });
  }

  static Future<void> removeVideoId(String playlistId, String videoId) async {
    final collection = _collection;
    if (collection == null) return;
    final ref = collection.doc(_docId(playlistId));
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final existing = snapshot.data()?['tracks'] is List
          ? List<dynamic>.from(snapshot.data()!['tracks'] as List)
          : <dynamic>[];
      final filtered = existing
          .where((m) => !(m is Map && m['videoId'] == videoId))
          .toList();
      if (filtered.length == existing.length) return;
      transaction.update(ref, {
        'tracks': filtered,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
