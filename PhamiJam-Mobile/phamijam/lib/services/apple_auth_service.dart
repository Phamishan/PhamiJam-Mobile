import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

const String _logTag = 'AppleAuthService';

class AppleAuthService {
  AppleAuthService._();

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static Future<AppleSignInResult?> signIn() async {
    final rawNonce = _generateNonce();
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );

      final idToken = appleCredential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('$_logTag: signIn() got no identityToken back.');
        return null;
      }

      final oauthCredential = OAuthProvider(
        'apple.com',
      ).credential(idToken: idToken, rawNonce: rawNonce);

      final displayName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((part) => (part ?? '').trim().isNotEmpty).join(' ').trim();

      return AppleSignInResult(
        credential: oauthCredential,
        displayName: displayName.isEmpty ? null : displayName,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        debugPrint('$_logTag: user canceled the Apple sign-in sheet.');
        return null;
      }
      rethrow;
    }
  }
}

class AppleSignInResult {
  const AppleSignInResult({required this.credential, this.displayName});
  final OAuthCredential credential;
  final String? displayName;
}
