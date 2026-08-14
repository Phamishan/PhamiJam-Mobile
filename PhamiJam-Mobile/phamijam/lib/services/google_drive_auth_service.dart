import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _logTag = 'GoogleDriveAuthService';

class GoogleDriveAuthService {
  GoogleDriveAuthService._();

  static const String driveScope = 'https://www.googleapis.com/auth/drive.file';

  static const String _androidRedirectUri =
      'https://phamijam-share.phamijam.workers.dev/drive-oauth-callback';

  static const String _prefsRefreshTokenKey = 'phamijam.drive_refresh_token';

  static String? _accessToken;
  static String? _refreshToken;
  static DateTime? _expiresAt;
  static String? _pendingCodeVerifier;

  static String? get accessToken => _accessToken;

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static String get _clientId {
    final id = _isIOS
        ? dotenv.env['DRIVE_CLIENT_ID_IOS']
        : dotenv.env['DRIVE_CLIENT_ID_ANDROID'];
    return id ?? '';
  }

  static String? get _clientSecret {
    if (_isIOS) return null;
    final secret = dotenv.env['DRIVE_CLIENT_SECRET_ANDROID'];
    return (secret != null && secret.isNotEmpty) ? secret : null;
  }

  static String get redirectUri {
    if (_isIOS) {
      final idPrefix = _clientId.split('.').first;
      return 'com.googleusercontent.apps.$idPrefix:/oauth2redirect';
    }
    return _androidRedirectUri;
  }

  static String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _codeChallengeFromVerifier(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Uri buildAuthorizationUrl() {
    final verifier = _generateCodeVerifier();
    _pendingCodeVerifier = verifier;
    return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid profile email $driveScope',
      'code_challenge': _codeChallengeFromVerifier(verifier),
      'code_challenge_method': 'S256',
      'prompt': 'consent',
    });
  }

  static bool _isAccessTokenUsable() {
    if (_accessToken == null || _accessToken!.isEmpty) return false;
    if (_expiresAt == null) return true;
    return _expiresAt!.isAfter(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );
  }

  static Future<bool> exchangeCodeForTokens(String code) async {
    final clientId = _clientId;
    final verifier = _pendingCodeVerifier;
    if (clientId.isEmpty || verifier == null) return false;
    _pendingCodeVerifier = null;

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        if ((_clientSecret ?? '').isNotEmpty) 'client_secret': _clientSecret!,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: code exchange failed (${response.statusCode}): ${response.body}',
      );
      return false;
    }

    return _applyTokenResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<bool> _refreshAccessToken() async {
    final refreshToken = _refreshToken ??= await _loadStoredRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    final clientId = _clientId;
    if (clientId.isEmpty) return false;

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        if ((_clientSecret ?? '').isNotEmpty) 'client_secret': _clientSecret!,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: refresh failed (${response.statusCode}): ${response.body}',
      );
      return false;
    }

    return _applyTokenResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static bool _applyTokenResponse(Map<String, dynamic> payload) {
    final accessToken = payload['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) return false;

    _accessToken = accessToken;
    final expiresInSeconds = (payload['expires_in'] as num?)?.toInt();
    _expiresAt = expiresInSeconds == null
        ? null
        : DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds));

    final newRefreshToken = payload['refresh_token'] as String?;
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      _refreshToken = newRefreshToken;
      unawaited(_storeRefreshToken(newRefreshToken));
    }
    return true;
  }

  static Future<String?> _loadStoredRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsRefreshTokenKey);
  }

  static Future<void> _storeRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsRefreshTokenKey, token);
  }

  static Future<String?>? _pendingEnsure;

  static Future<String?> ensureAccessToken({bool forceRefresh = false}) {
    if (!forceRefresh && _isAccessTokenUsable()) {
      return Future.value(_accessToken);
    }

    final pending = _pendingEnsure;
    if (pending != null) return pending;

    final future = _refreshAccessToken().then((ok) => ok ? _accessToken : null);
    _pendingEnsure = future;
    future.whenComplete(() => _pendingEnsure = null);
    return future;
  }

  static Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsRefreshTokenKey);
  }
}
