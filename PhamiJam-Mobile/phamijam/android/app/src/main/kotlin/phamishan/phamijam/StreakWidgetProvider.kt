package phamishan.phamijam

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class StreakWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val days = widgetData.getInt("streak_days", 0)
        val accentColor = widgetData.getInt("accent_color", 0xFFDBA43A.toInt())

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_streak)
            views.setInt(R.id.widget_bg, "setColorFilter", accentColor)
            views.setTextViewText(R.id.widget_streak_value, days.toString())
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
