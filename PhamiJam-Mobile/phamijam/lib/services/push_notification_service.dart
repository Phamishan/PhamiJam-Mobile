import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:phamijam/services/log_service.dart';

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
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      Log.i(
        'push',
        'notification permission: ${settings.authorizationStatus.name}',
      );
    } catch (error) {
      Log.e('push', 'requesting notification permission failed', error);
    }

    unawaited(registerToken());
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      _saveToken,
      onError: (Object error) {
        Log.e('push', 'token refresh error', error);
      },
    );

    void handleTap(RemoteMessage message) {
      final friendUid = message.data['friendUid'];
      Log.i('push', 'notification opened (has friend: ${friendUid is String})');
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
      Log.e('push', 'reading launch notification failed', error);
    }
  }

  static Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      Log.i(
        'push',
        token == null ? 'no push token available' : 'got push token',
      );
      if (token != null) await _saveToken(token);
    } catch (error) {
      Log.e('push', 'registering push token failed', error);
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
      Log.e('push', 'saving push token failed', error);
    }
  }

  static Future<void> clearToken() async {
    Log.i('push', 'clearing push token');
    final tokens = _tokensCollection;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && tokens != null) {
        await tokens.doc(token).delete();
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      Log.e('push', 'clearing push token failed', error);
    }
  }
}
