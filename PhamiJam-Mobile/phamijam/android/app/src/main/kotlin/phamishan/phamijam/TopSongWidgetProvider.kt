package phamishan.phamijam

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class TopSongWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("top_song_title", "") ?: ""
        val artist = widgetData.getString("top_song_artist", "") ?: ""
        val accentColor = widgetData.getInt("accent_color", 0xFFDBA43A.toInt())

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_top_song)
            views.setInt(R.id.widget_bg, "setColorFilter", accentColor)
            views.setTextViewText(
                R.id.widget_top_song_title,
                if (title.isEmpty()) "No plays yet this week" else title,
            )
            views.setTextViewText(R.id.widget_top_song_artist, artist)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
