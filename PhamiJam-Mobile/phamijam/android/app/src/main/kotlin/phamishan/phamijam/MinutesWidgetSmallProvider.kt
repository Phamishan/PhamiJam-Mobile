package phamishan.phamijam

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MinutesWidgetSmallProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val minutes = widgetData.getInt("minutes_played", 0)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_minutes_small)
            views.setTextViewText(R.id.widget_minutes_value, minutes.toString())
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
