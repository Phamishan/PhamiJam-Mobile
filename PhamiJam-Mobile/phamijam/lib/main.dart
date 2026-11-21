import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/firebase_options.dart';
import 'package:phamijam/pages/connect_google_page.dart';
import 'package:phamijam/pages/login.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/profile_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/audio_stream_resolver.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/services/phamijam_audio_handler.dart';
import 'package:phamijam/services/jamstats_widget_service.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/push_notification_service.dart';
import 'package:phamijam/services/unavailable_songs_service.dart';
import 'package:phamijam/theme/app_theme.dart';
import 'package:phamijam/widgets/app_shell.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.init();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom],
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  Log.i('startup', 'initializing Firebase');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseAuth.instance.authStateChanges().listen(
    (user) => LogService.instance.setUser(user?.uid),
    onError: (Object error) => Log.e('auth', 'auth state stream error', error),
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await dotenv.load(fileName: '.env');
  Log.i('startup', 'config loaded, starting audio service');

  final sharedResolver = AudioStreamResolver();
  final audioHandler = await AudioService.init(
    builder: () => PhamiJamAudioHandler(resolver: sharedResolver),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'phamishan.phamijam.audio',
      androidNotificationChannelName: 'PhamiJam playback',
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_launcher_foreground',
    ),
  );
  final downloadsProvider = DownloadsProvider(resolver: sharedResolver);
  audioHandler.resolveLocalPath = downloadsProvider.localPathFor;
  Log.i('startup', 'audio service ready, launching UI');

  unawaited(JamstatsWidgetService.refresh());
  unawaited(UnavailableSongs.instance.ensureLoaded());

  runApp(
    MyApp(audioHandler: audioHandler, downloadsProvider: downloadsProvider),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.audioHandler,
    required this.downloadsProvider,
  });

  final PhamiJamAudioHandler audioHandler;
  final DownloadsProvider downloadsProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(audioHandler: audioHandler),
        ),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => EditedSongsProvider()),
        ChangeNotifierProvider(create: (_) => SavedPlaylistsProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: downloadsProvider),
      ],
      child: Builder(
        builder: (context) {
          final themeProvider = context.watch<ThemeProvider>();
          return MaterialApp(
            title: 'PhamiJam',
            debugShowCheckedModeBanner: false,
            navigatorObservers: [LogNavigatorObserver()],
            themeMode: themeProvider.flutterThemeMode,
            theme: AppTheme.light(accentColor: themeProvider.accentColor),
            darkTheme: AppTheme.dark(accentColor: themeProvider.accentColor),
            home: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: kBrandGold,
                    body: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  );
                }

                if (snapshot.hasData) {
                  return _YoutubeConnectionGate(user: snapshot.data!);
                }
                if (snapshot.hasError) {
                  Log.e('auth', 'auth stream error', snapshot.error);
                }
                return const Login();
              },
            ),
          );
        },
      ),
    );
  }
}

class _YoutubeConnectionGate extends StatefulWidget {
  const _YoutubeConnectionGate({required this.user});

  final User user;

  @override
  State<_YoutubeConnectionGate> createState() => _YoutubeConnectionGateState();
}

class _YoutubeConnectionGateState extends State<_YoutubeConnectionGate> {
  bool? _isConnected;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  void _checkConnection() {
    final signedInWithGoogle = widget.user.providerData.any(
      (info) => info.providerId == 'google.com',
    );
    final providers = widget.user.providerData.map((i) => i.providerId);
    Log.i('auth', 'session restored, providers: ${providers.join(', ')}');
    if (signedInWithGoogle) {
      setState(() => _isConnected = true);
      return;
    }

    unawaited(_checkConnectionAsync());
  }

  Future<bool> _hasNetworkConnectivity() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkConnectionAsync() async {
    if (!await _hasNetworkConnectivity()) {
      Log.w('network', 'offline at startup, skipping Google reconnect check');
      if (!mounted) return;
      setState(() => _isConnected = true);
      return;
    }

    bool connected;
    try {
      connected = await GoogleAuthService.tryRestoreSilently();
    } catch (error) {
      debugPrint('_YoutubeConnectionGate: tryRestoreSilently threw: $error');
      connected = false;
    }
    Log.i(
      'auth',
      connected
          ? 'Google/YouTube connection restored silently'
          : 'Google/YouTube not connected, asking user to connect',
    );
    if (!mounted) return;
    setState(() => _isConnected = connected);
  }

  @override
  Widget build(BuildContext context) {
    switch (_isConnected) {
      case null:
        return const Scaffold(
          backgroundColor: kBrandGold,
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      case false:
        return ConnectGooglePage(
          onConnected: () => setState(() => _isConnected = true),
        );
      case true:
        return const AppShell();
    }
  }
}
