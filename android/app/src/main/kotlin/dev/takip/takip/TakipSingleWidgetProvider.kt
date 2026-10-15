package dev.takip.takip

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

class TakipSingleWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.takip_single_widget)

            val payloadStr = widgetData.getString("payload", null)
            var title = "Takip"
            var sub = ""
            var emoji = "⚡"
            var actId = 0
            var done = false

            if (payloadStr != null) {
                try {
                    val json = JSONObject(payloadStr)
                    title = json.optString("single_title", "Takip")
                    sub = json.optString("single_sub", "")
                    emoji = json.optString("single_emoji", "⚡")
                    actId = json.optInt("single_act_id", 0)
                    done = json.optBoolean("single_done", false)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            views.setTextViewText(R.id.single_widget_emoji, emoji)
            views.setTextViewText(R.id.single_widget_title, if (done) "✓ $title" else title)
            views.setTextViewText(R.id.single_widget_sub, sub)
            views.setInt(
                R.id.single_widget_container,
                "setBackgroundResource",
                if (done) R.drawable.widget_item_done_bg else R.drawable.widget_bg
            )

            val pendingIntent = if (actId > 0) {
                val tapUri = Uri.parse("takip://single_tap?actId=$actId")
                HomeWidgetBackgroundIntent.getBroadcast(context, tapUri)
            } else {
                val addUri = Uri.parse("takip://add")
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, addUri)
            }
            views.setOnClickPendingIntent(R.id.single_widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
