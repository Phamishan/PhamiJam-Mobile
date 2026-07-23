import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/components/app_flushbar.dart';

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

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final credentials = await GoogleAuthService.signIn();

      if (credentials == null) {
        debugPrint(
          'Login: GoogleAuthService.signIn() returned null credentials.',
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        if (kDebugMode) {
          AppFlushbar.info(
            context,
            'Google sign-in was canceled. Please try again.',
          );
        }
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
    } on FirebaseAuthException catch (error) {
      if (error.code == 'invalid-credential') {
        try {
          final refreshedCredentials = await GoogleAuthService.signInFresh();
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppFlushbar.error(
          context,
          error.code == 'invalid-credential'
              ? 'Google sign-in token expired. Please try again.'
              : 'Failed to sign in: ${error.message ?? error.code}',
        );
      }
    } catch (error) {
      debugPrint('Error signing in with Google: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppFlushbar.error(context, 'Failed to sign in: $error');
      }
    }
  }

  Future<void> _signOut() async {
    await GoogleAuthService.signOut();
    await _auth.signOut();
    if (!mounted) return;
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
                                  : "Sign in with your Google account to sync your YouTube playlists and start listening.",
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
