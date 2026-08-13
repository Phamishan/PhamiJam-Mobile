package phamishan.phamijam

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class NowPlayingWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("now_playing_title", "") ?: ""
        val artist = widgetData.getString("now_playing_artist", "") ?: ""
        val label = widgetData.getString("now_playing_label", "Now Playing") ?: "Now Playing"
        val accentColor = widgetData.getInt("accent_color", 0xFFDBA43A.toInt())

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_now_playing)
            views.setInt(R.id.widget_bg, "setColorFilter", accentColor)
            views.setTextViewText(R.id.widget_now_playing_label, label)
            views.setTextViewText(
                R.id.widget_now_playing_title,
                if (title.isEmpty()) "Nothing playing yet" else title,
            )
            views.setTextViewText(R.id.widget_now_playing_artist, artist)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
