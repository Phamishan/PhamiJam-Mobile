import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/models/track.dart';

class LikedSongsService {
  LikedSongsService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('likedSongs');
  }

  static String _docId(String videoId) =>
      videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<List<Track>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    final snapshot = await collection
        .orderBy('likedAt', descending: true)
        .get();
    return snapshot.docs.map(_trackFromData).whereType<Track>().toList();
  }

  static Future<void> like(Track track) async {
    final collection = _collection;
    final videoId = track.videoId;
    if (collection == null || videoId == null || videoId.isEmpty) return;
    await collection.doc(_docId(videoId)).set({
      'videoId': videoId,
      'title': track.title,
      'artist': track.artist,
      'thumbnailUrl': track.thumbnailUrl,
      'durationMs': track.duration.inMilliseconds,
      'channelId': track.channelId,
      'likedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unlike(String videoId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(videoId)).delete();
  }

  static Track? _trackFromData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final videoId = data['videoId'];
    if (videoId is! String || videoId.isEmpty) return null;
    return Track(
      id: 'yt-$videoId',
      title: data['title'] is String ? data['title'] as String : '',
      artist: data['artist'] is String ? data['artist'] as String : '',
      thumbnailUrl: data['thumbnailUrl'] is String
          ? data['thumbnailUrl'] as String
          : '',
      duration: Duration(
        milliseconds: data['durationMs'] is int ? data['durationMs'] as int : 0,
      ),
      videoId: videoId,
      channelId: data['channelId'] is String
          ? data['channelId'] as String
          : null,
    );
  }
}
