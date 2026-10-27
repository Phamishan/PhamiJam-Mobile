import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService._();

  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _openedAppSub;

  static CollectionReference<Map<String, dynamic>>? get _tokensCollection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens');
  }

  static Future<void> init({
    required void Function(String friendUid) onActivityNotificationTapped,
  }) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (error) {
      debugPrint('PushNotificationService: requestPermission failed: $error');
    }

    unawaited(registerToken());
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      _saveToken,
      onError: (Object error) {
        debugPrint('PushNotificationService: onTokenRefresh error: $error');
      },
    );

    void handleTap(RemoteMessage message) {
      final friendUid = message.data['friendUid'];
      if (friendUid is String && friendUid.isNotEmpty) {
        onActivityNotificationTapped(friendUid);
      }
    }

    _openedAppSub?.cancel();
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(handleTap);

    try {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) handleTap(initialMessage);
    } catch (error) {
      debugPrint('PushNotificationService: getInitialMessage failed: $error');
    }
  }

  static Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (error) {
      debugPrint('PushNotificationService: registerToken failed: $error');
    }
  }

  static Future<void> _saveToken(String token) async {
    final tokens = _tokensCollection;
    if (tokens == null) return;
    try {
      await tokens.doc(token).set({
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('PushNotificationService: saveToken failed: $error');
    }
  }

  static Future<void> clearToken() async {
    final tokens = _tokensCollection;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && tokens != null) {
        await tokens.doc(token).delete();
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('PushNotificationService: clearToken failed: $error');
    }
  }
}
