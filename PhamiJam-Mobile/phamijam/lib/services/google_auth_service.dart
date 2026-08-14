import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

const String _logTag = 'GoogleAuthService';

class GoogleAuthCredentials {
  const GoogleAuthCredentials({
    required this.accessToken,
    required this.scopes,
    this.idToken,
  });

  final String accessToken;
  final List<String> scopes;
  final String? idToken;
}

class GoogleAuthService {
  GoogleAuthService._();

  static const String _youtubeScope = 'https://www.googleapis.com/auth/youtube';
  static const List<String> _scopes = [_youtubeScope];

  static Future<void>? _initFuture;
  static GoogleSignInAccount? _account;
  static String? _accessToken;

  static String? get accessToken => _accessToken;

  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  static Future<void> _ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize(
      serverClientId: dotenv.env['CLIENT_ID'],
    );
  }

  static Future<GoogleSignInAccount?> _tryRestoringAccount() async {
    final future = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (future == null) return null;
    try {
      final account = await future;
      if (account != null) _account = account;
      return account;
    } on GoogleSignInException catch (error) {
      debugPrint(
        '$_logTag: attemptLightweightAuthentication threw: '
        '${error.code} ${error.description}',
      );
      return null;
    }
  }

  static Future<GoogleAuthCredentials?> _authorizeSilently(
    GoogleSignInAccount account,
  ) async {
    final authz = await account.authorizationClient.authorizationForScopes(
      _scopes,
    );
    if (authz == null) return null;
    _account = account;
    _accessToken = authz.accessToken;
    return GoogleAuthCredentials(
      accessToken: authz.accessToken,
      scopes: _scopes,
      idToken: account.authentication.idToken,
    );
  }

  static Future<GoogleAuthCredentials> _authorizeInteractively(
    GoogleSignInAccount account,
  ) async {
    final authz = await account.authorizationClient.authorizeScopes(_scopes);
    _account = account;
    _accessToken = authz.accessToken;
    return GoogleAuthCredentials(
      accessToken: authz.accessToken,
      scopes: _scopes,
      idToken: account.authentication.idToken,
    );
  }

  static Future<String?>? _pendingEnsure;

  static Future<String?> ensureAccessToken({
    bool forceOnline = false,
    bool forceRefresh = false,
  }) {
    if (!forceOnline &&
        !forceRefresh &&
        _accessToken != null &&
        _accessToken!.isNotEmpty) {
      return Future.value(_accessToken);
    }

    final pending = _pendingEnsure;
    if (pending != null) return pending;

    final future = _ensureAccessTokenUncached(
      forceOnline: forceOnline,
      forceRefresh: forceRefresh,
    );
    _pendingEnsure = future;
    future.whenComplete(() => _pendingEnsure = null);
    return future;
  }

  static Future<String?> _ensureAccessTokenUncached({
    bool forceOnline = false,
    bool forceRefresh = false,
  }) async {
    await _ensureInitialized();

    if (!forceOnline) {
      final account = _account ?? await _tryRestoringAccount();
      if (account != null) {
        if (forceRefresh && _accessToken != null) {
          await account.authorizationClient.clearAuthorizationToken(
            accessToken: _accessToken!,
          );
        }

        final silent = await _authorizeSilently(account);
        if (silent != null) return silent.accessToken;
      }
    }

    debugPrint('$_logTag: falling back to authenticate() for a fresh token.');
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      final credentials = await _authorizeInteractively(account);
      return credentials.accessToken;
    } on GoogleSignInException catch (error) {
      debugPrint(
        '$_logTag: ensureAccessToken authenticate() failed: '
        '${error.code} ${error.description}',
      );
      return null;
    }
  }

  static Future<bool> tryRestoreSilently() async {
    await _ensureInitialized();
    final account = await _tryRestoringAccount();
    if (account == null) return false;
    final credentials = await _authorizeSilently(account);
    return credentials != null;
  }

  static Future<GoogleAuthCredentials?> signIn() async {
    await _ensureInitialized();
    debugPrint('$_logTag: signIn() -> authenticate()');
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      final credentials = await _authorizeInteractively(account);
      debugPrint(
        '$_logTag: signIn() succeeded. scopes=${credentials.scopes} '
        'hasIdToken=${(credentials.idToken ?? '').isNotEmpty}',
      );
      return credentials;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('$_logTag: signIn() canceled by user.');
        return null;
      }
      debugPrint(
        '$_logTag: signIn() threw ${error.code}: ${error.description}',
      );
      rethrow;
    }
  }

  static Future<GoogleAuthCredentials?> signInFresh() async {
    debugPrint('$_logTag: signInFresh() -> signOut() then authenticate()');
    await signOut();
    return signIn();
  }

  static Future<void> signOut() async {
    debugPrint('$_logTag: signOut()');
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
    _account = null;
    _accessToken = null;
  }
}
