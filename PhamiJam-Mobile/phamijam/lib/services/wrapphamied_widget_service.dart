import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/wrapped_stats.dart';

const String _appGroupId = 'group.phamishan.phamijam.widget';
const String _androidSmallReceiver =
    'phamishan.phamijam.MinutesWidgetSmallProvider';
const String _androidLargeReceiver =
    'phamishan.phamijam.MinutesWidgetLargeProvider';
const String _iOSWidgetName = 'PhamiJamMinutesWidget';
const String _minutesKey = 'minutes_played';
const String _yearKey = 'wrapped_year';

class WrapphamiedWidgetService {
  WrapphamiedWidgetService._();

  static Future<void> refresh() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);

      final year = DateTime.now().year;
      final events = await ListeningHistoryService.eventsSince(
        DateTime(year),
        until: DateTime(year + 1),
      );
      final minutes = WrappedStats.fromEvents(events).totalMinutes;

      await HomeWidget.saveWidgetData<int>(_minutesKey, minutes);
      await HomeWidget.saveWidgetData<int>(_yearKey, year);

      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidSmallReceiver,
        iOSName: _iOSWidgetName,
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidLargeReceiver,
        iOSName: _iOSWidgetName,
      );
    } catch (error) {
      debugPrint('WrapphamiedWidgetService: refresh failed: $error');
    }
  }
}
