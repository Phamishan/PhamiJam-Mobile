import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/wrapped_stats.dart';

const String _appGroupId = 'group.phamishan.phamijam.widget';

const String _androidMinutesSmallReceiver =
    'phamishan.phamijam.MinutesWidgetSmallProvider';
const String _androidMinutesLargeReceiver =
    'phamishan.phamijam.MinutesWidgetLargeProvider';
const String _androidNowPlayingReceiver =
    'phamishan.phamijam.NowPlayingWidgetProvider';
const String _androidStreakReceiver = 'phamishan.phamijam.StreakWidgetProvider';
const String _androidTopSongReceiver =
    'phamishan.phamijam.TopSongWidgetProvider';

const String _iOSMinutesWidgetName = 'PhamiJamMinutesWidget';
const String _iOSNowPlayingWidgetName = 'PhamiJamNowPlayingWidget';
const String _iOSStreakWidgetName = 'PhamiJamStreakWidget';
const String _iOSTopSongWidgetName = 'PhamiJamTopSongWidget';

const String _minutesKey = 'minutes_played';
const String _yearKey = 'wrapped_year';
const String _accentColorKey = 'accent_color';
const String _streakDaysKey = 'streak_days';
const String _topSongTitleKey = 'top_song_title';
const String _topSongArtistKey = 'top_song_artist';
const String _nowPlayingTitleKey = 'now_playing_title';
const String _nowPlayingArtistKey = 'now_playing_artist';
const String _nowPlayingLabelKey = 'now_playing_label';

class JamstatsWidgetService {
  JamstatsWidgetService._();

  static DateTime? _lastRefreshAt;
  static const Duration _refreshCooldown = Duration(minutes: 15);

  static Future<void> refresh({int? accentColor}) async {
    final now = DateTime.now();
    final last = _lastRefreshAt;
    if (last != null && now.difference(last) < _refreshCooldown) {
      return;
    }
    _lastRefreshAt = now;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);

      final year = DateTime.now().year;
      final yearEvents = await ListeningHistoryService.eventsSince(
        DateTime(year),
        until: DateTime(year + 1),
      );
      final yearStats = WrappedStats.fromEvents(yearEvents);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
      final weekEvents = await ListeningHistoryService.eventsSince(
        startOfWeek,
        until: today.add(const Duration(days: 1)),
      );
      final weekStats = WrappedStats.fromEvents(weekEvents);
      final topSong = weekStats.topTracks.isNotEmpty
          ? weekStats.topTracks.first
          : null;

      await HomeWidget.saveWidgetData<int>(_minutesKey, yearStats.totalMinutes);
      await HomeWidget.saveWidgetData<int>(_yearKey, year);
      if (accentColor != null) {
        await HomeWidget.saveWidgetData<int>(_accentColorKey, accentColor);
      }
      await HomeWidget.saveWidgetData<int>(
        _streakDaysKey,
        yearStats.currentStreakDays,
      );
      await HomeWidget.saveWidgetData<String>(
        _topSongTitleKey,
        topSong?.name ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        _topSongArtistKey,
        topSong?.subtitle ?? '',
      );

      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidMinutesSmallReceiver,
        iOSName: _iOSMinutesWidgetName,
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidMinutesLargeReceiver,
        iOSName: _iOSMinutesWidgetName,
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidStreakReceiver,
        iOSName: _iOSStreakWidgetName,
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidTopSongReceiver,
        iOSName: _iOSTopSongWidgetName,
      );
    } catch (error) {
      debugPrint('JamstatsWidgetService: refresh failed: $error');
    }
  }

  static Future<void> pushNowPlaying({
    required Track? track,
    required bool isPlaying,
  }) async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      await HomeWidget.saveWidgetData<String>(
        _nowPlayingTitleKey,
        track?.title ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        _nowPlayingArtistKey,
        track?.artist ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        _nowPlayingLabelKey,
        isPlaying ? 'Now Playing' : 'Last played',
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidNowPlayingReceiver,
        iOSName: _iOSNowPlayingWidgetName,
      );
    } catch (error) {
      debugPrint('JamstatsWidgetService: pushNowPlaying failed: $error');
    }
  }
}
