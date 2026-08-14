import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:phamijam/services/apple_auth_service.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:provider/provider.dart';

const Duration _authTimeout = Duration(seconds: 25);

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _userId;
  bool _isLoading = false;

  Future<UserCredential?> _firebaseSignInFromGoogleCredentials(
    GoogleSignInCredentials credentials,
  ) async {
    final hasIdToken = (credentials.idToken ?? '').isNotEmpty;
    final hasAccessToken = credentials.accessToken.isNotEmpty;

    if (!hasIdToken && !hasAccessToken) {
      return null;
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: hasAccessToken ? credentials.accessToken : null,
      idToken: hasIdToken ? credentials.idToken : null,
    );

    return _auth.signInWithCredential(credential);
  }

  String get _authDebugContext =>
      'platform: ${defaultTargetPlatform.name}\n'
      'clientId: ${dotenv.env['CLIENT_ID']}';

  void _showAuthDebugDialog(String title, String content) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final credentials = await GoogleAuthService.signIn().timeout(
        _authTimeout,
      );

      if (credentials == null) {
        debugPrint(
          'Login: GoogleAuthService.signIn() returned null credentials.',
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        _showAuthDebugDialog(
          'Google sign-in returned nothing',
          'signInOnline() completed after ${stopwatch.elapsed.inSeconds}s '
              'but returned null credentials.\n\n'
              'Note: the plugin catches every exception inside '
              'signInOnline() (a user cancel and a real failure both '
              'become null), so this could be either.\n\n'
              '$_authDebugContext',
        );
        return;
      }

      var userCredential = await _firebaseSignInFromGoogleCredentials(
        credentials,
      );

      if (userCredential == null) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Google sign-in did not return usable tokens.',
        );
      }

      if (!mounted) return;
      setState(() {
        _userId = userCredential.user?.email;
        _isLoading = false;
      });
    } on TimeoutException {
      debugPrint('Error signing in with Google: timed out');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showAuthDebugDialog(
        'Google sign-in timed out',
        'No response after ${_authTimeout.inSeconds}s inside '
            'googleSignIn.signInOnline(). This usually means it hung on '
            'the native side (e.g. stuck on accounts.google.com) rather '
            'than throwing an error Dart could catch.\n\n'
            '$_authDebugContext',
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'invalid-credential') {
        try {
          final refreshedCredentials = await GoogleAuthService.signInFresh()
              .timeout(_authTimeout);
          if (refreshedCredentials != null) {
            final retriedUserCredential =
                await _firebaseSignInFromGoogleCredentials(
                  refreshedCredentials,
                );

            if (retriedUserCredential != null && mounted) {
              setState(() {
                _userId = retriedUserCredential.user?.email;
                _isLoading = false;
              });
              return;
            }
          }
        } catch (_) {}
      }

      debugPrint('Error signing in with Google: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showAuthDebugDialog(
        'Google sign-in failed',
        'error: ${error.code} — ${error.message}\n'
            'elapsed: ${stopwatch.elapsed.inSeconds}s\n\n'
            '$_authDebugContext',
      );
    } catch (error) {
      debugPrint('Error signing in with Google: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showAuthDebugDialog(
        'Google sign-in failed',
        'error: $error\n'
            'elapsed: ${stopwatch.elapsed.inSeconds}s\n\n'
            '$_authDebugContext',
      );
    }
  }

  Future<void> _signInWithApple() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final stopwatch = Stopwatch()..start();
    AppleSignInResult? result;
    try {
      result = await AppleAuthService.signIn().timeout(_authTimeout);
      if (result == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final userCredential = await _auth.signInWithCredential(
        result.credential,
      );
      final user = userCredential.user;
      if (user != null &&
          result.displayName != null &&
          (user.displayName ?? '').isEmpty) {
        await user.updateDisplayName(result.displayName);
      }

      if (!mounted) return;
      setState(() {
        _userId = user?.email;
        _isLoading = false;
      });
    } on TimeoutException {
      debugPrint('Error signing in with Apple: timed out');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showAuthDebugDialog(
        'Apple sign-in timed out',
        'No response after ${_authTimeout.inSeconds}s. This usually means '
            'it hung on the native side rather than throwing an error Dart '
            'could catch.\n\n'
            '$_authDebugContext',
      );
    } catch (error) {
      debugPrint('Error signing in with Apple: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      final idToken = result?.idToken;
      final claims = idToken == null
          ? null
          : AppleAuthService.decodeIdTokenClaims(idToken);
      _showAuthDebugDialog(
        'Apple sign-in failed',
        'error: $error\n'
            'elapsed: ${stopwatch.elapsed.inSeconds}s\n'
            '${claims == null ? '' : 'aud: ${claims['aud']}\niss: ${claims['iss']}\nexp: ${claims['exp']}\n'}'
            '\n$_authDebugContext',
      );
    }
  }

  Future<void> _signOut() async {
    await GoogleAuthService.signOut();
    await GoogleDriveAuthService.signOut();
    await DriveFolderService.clearFolderId();
    await _auth.signOut();
    if (!mounted) return;
    context.read<LibraryProvider>().clearDriveConnection();
    setState(() {
      _userId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _userId != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.35),
              colorScheme.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24.0,
                        horizontal: 20.0,
                      ),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 360.0),
                        padding: const EdgeInsets.all(28.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: colorScheme.surfaceContainer,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            Image.asset(
                              "assets/images/p-trans.png",
                              height: 84,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 22),
                            Text(
                              "Welcome to PhamiJam",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _userId != null
                                  ? "Logged in as $_userId"
                                  : "Sign in to sync your YouTube playlists and start listening.",
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),
                            if (_isLoading)
                              CircularProgressIndicator(
                                color: colorScheme.primary,
                              )
                            else
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (isSignedIn) {
                                      await _signOut();
                                    } else {
                                      await _signInWithGoogle();
                                    }
                                  },
                                  icon: ClipOval(
                                    child: Image.asset(
                                      "assets/images/google_icon.jpg",
                                      width: 22,
                                      height: 22,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  label: Text(
                                    isSignedIn
                                        ? 'Sign Out'
                                        : 'Continue with Google',
                                  ),
                                ),
                              ),
                            if (!_isLoading &&
                                !isSignedIn &&
                                defaultTargetPlatform == TargetPlatform.iOS)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: SignInWithAppleButton(
                                    onPressed: _signInWithApple,
                                    style:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? SignInWithAppleButtonStyle.white
                                        : SignInWithAppleButtonStyle.black,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
