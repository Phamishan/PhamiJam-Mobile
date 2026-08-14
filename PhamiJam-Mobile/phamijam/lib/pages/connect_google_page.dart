import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/services/google_auth_service.dart';

class ConnectGooglePage extends StatefulWidget {
  const ConnectGooglePage({super.key, required this.onConnected});

  final VoidCallback onConnected;

  @override
  State<ConnectGooglePage> createState() => _ConnectGooglePageState();
}

class _ConnectGooglePageState extends State<ConnectGooglePage> {
  bool _isLoading = false;

  Future<void> _connect() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final credentials = await GoogleAuthService.signIn();
      if (credentials == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
      if (!mounted) return;
      widget.onConnected();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppFlushbar.error(context, "Couldn't connect Google: $error");
    }
  }

  Future<void> _signOut() async {
    await GoogleAuthService.signOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
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
                    Icon(
                      Icons.smart_display_rounded,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "Connect your YouTube account",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "PhamiJam streams from your YouTube account, so it "
                      "needs a connected Google account to load your "
                      "playlists and library.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_isLoading)
                      CircularProgressIndicator(color: colorScheme.primary)
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _connect,
                          icon: ClipOval(
                            child: Image.asset(
                              "assets/images/google_icon.jpg",
                              width: 22,
                              height: 22,
                              fit: BoxFit.cover,
                            ),
                          ),
                          label: const Text('Connect Google'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _signOut,
                        child: const Text('Sign out instead'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
