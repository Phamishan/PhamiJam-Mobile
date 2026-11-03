import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:phamijam/models/track.dart';

class FriendNowPlaying {
  final List<Track> queue;
  final int queueIndex;
  final Duration position;
  final bool isPlaying;
  final DateTime updatedAt;
  final Duration? trimStart;
  final Duration? trimEnd;

  const FriendNowPlaying({
    required this.queue,
    required this.queueIndex,
    required this.position,
    required this.isPlaying,
    required this.updatedAt,
    this.trimStart,
    this.trimEnd,
  });

  Track? get currentTrack =>
      (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null;

  bool get isLive =>
      currentTrack != null &&
      DateTime.now().difference(updatedAt) < const Duration(minutes: 2);
}

class ListenAlongService {
  ListenAlongService._();

  static DocumentReference<Map<String, dynamic>>? get _ownDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('status')
        .doc('nowPlaying');
  }

  static DocumentReference<Map<String, dynamic>> _friendDoc(String friendUid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(friendUid)
          .collection('status')
          .doc('nowPlaying');

  static Map<String, dynamic> _trackToJson(Track track) => {
    'v': track.videoId,
    't': track.title,
    'a': track.artist,
    'c': track.channelId,
    'd': track.duration.inMilliseconds,
  };

  static Track? _trackFromJson(dynamic json) {
    if (json is! Map) return null;
    final videoId = json['v'];
    if (videoId is! String || videoId.isEmpty) return null;
    return Track(
      id: 'yt-$videoId',
      title: json['t'] is String ? json['t'] as String : '',
      artist: json['a'] is String ? json['a'] as String : '',
      thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      duration: Duration(milliseconds: json['d'] is int ? json['d'] as int : 0),
      videoId: videoId,
      channelId: json['c'] is String ? json['c'] as String : null,
    );
  }

  static Future<void> pushNowPlaying({
    required List<Track> queue,
    required int queueIndex,
    required Duration position,
    required bool isPlaying,
    Duration? trimStart,
    Duration? trimEnd,
  }) async {
    final doc = _ownDoc;
    if (doc == null) return;
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    if (queue[queueIndex].videoId == null) return;

    final syncableQueue = queue.where((t) => t.videoId != null).toList();
    final syncableIndex = syncableQueue.indexOf(queue[queueIndex]);
    if (syncableIndex < 0) return;

    try {
      await doc.set({
        'queue': syncableQueue.map(_trackToJson).toList(),
        'queueIndex': syncableIndex,
        'positionMs': position.inMilliseconds,
        'isPlaying': isPlaying,
        'trimStartMs': trimStart?.inMilliseconds,
        'trimEndMs': trimEnd?.inMilliseconds,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('ListenAlongService: push failed: $error');
    }
  }

  static Future<void> clearNowPlaying() async {
    final doc = _ownDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'queue': [],
        'isPlaying': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('ListenAlongService: clear failed: $error');
    }
  }

  static Stream<FriendNowPlaying?> watchFriendNowPlaying(String friendUid) {
    return _friendDoc(friendUid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;

      final queue = ((data['queue'] as List?) ?? [])
          .map(_trackFromJson)
          .whereType<Track>()
          .toList();
      if (queue.isEmpty) return null;
      final queueIndex = data['queueIndex'] as int? ?? 0;
      if (queueIndex < 0 || queueIndex >= queue.length) return null;

      final updatedAt = data['updatedAt'];
      if (updatedAt is! Timestamp) return null;

      final trimStartMs = data['trimStartMs'] as int?;
      final trimEndMs = data['trimEndMs'] as int?;

      return FriendNowPlaying(
        queue: queue,
        queueIndex: queueIndex,
        position: Duration(milliseconds: data['positionMs'] as int? ?? 0),
        isPlaying: data['isPlaying'] as bool? ?? false,
        updatedAt: updatedAt.toDate(),
        trimStart: trimStartMs != null ? Duration(milliseconds: trimStartMs) : null,
        trimEnd: trimEndMs != null ? Duration(milliseconds: trimEndMs) : null,
      );
    });
  }
}
