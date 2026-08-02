import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/firebase_options.dart';
import 'package:phamijam/pages/login.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/audio_stream_resolver.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/phamijam_audio_handler.dart';
import 'package:phamijam/services/wrapphamied_widget_service.dart';
import 'package:phamijam/theme/app_theme.dart';
import 'package:phamijam/widgets/app_shell.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom],
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: '.env');

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

  unawaited(WrapphamiedWidgetService.refresh());

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
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: downloadsProvider),
      ],
      child: Builder(
        builder: (context) {
          final themeProvider = context.watch<ThemeProvider>();
          return MaterialApp(
            title: 'PhamiJam',
            debugShowCheckedModeBanner: false,
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
                  return const AppShell();
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
