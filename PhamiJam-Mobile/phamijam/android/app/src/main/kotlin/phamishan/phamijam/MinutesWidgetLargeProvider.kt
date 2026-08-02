package phamishan.phamijam

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MinutesWidgetLargeProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val minutes = widgetData.getInt("minutes_played", 0)
        val year = widgetData.getInt("wrapped_year", 0)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_minutes_large)
            views.setTextViewText(R.id.widget_minutes_value, minutes.toString())
            views.setTextViewText(
                R.id.widget_minutes_label,
                "minutes listened in $year",
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
