package dev.takip.takip

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

class TakipWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        var theme = widgetData.getString("widget_theme", "system") ?: "system"
        var isTr = true
        val payloadStr = widgetData.getString("payload", null)
        if (payloadStr != null) {
            try {
                val json = JSONObject(payloadStr)
                val t = json.optString("theme", "")
                if (t.isNotEmpty()) theme = t
                isTr = json.optBoolean("isTr", true)
            } catch (_: Exception) {}
        }

        val layoutId = when (theme) {
            "dark" -> R.layout.takip_widget_dark
            "light" -> R.layout.takip_widget_light
            else -> R.layout.takip_widget
        }

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, layoutId)
            views.setTextViewText(R.id.widget_title, "Seyir")
            views.setTextViewText(R.id.widget_add_btn, if (isTr) "+ Ne yaptın?" else "+ What did you do?")
            views.setTextViewText(R.id.widget_empty, if (isTr) "Uygulamadan sık yapılanları ekleyebilirsiniz." else "Add shortcuts from the app.")

            // Quick Add button opens app directly into composer
            val addUri = Uri.parse("takip://add")
            val addPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                addUri
            )
            views.setOnClickPendingIntent(R.id.widget_add_btn, addPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_title, addPendingIntent)

            // Voice input button opens app directly into voice recording
            val voiceUri = Uri.parse("takip://voice")
            val voicePendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                voiceUri
            )
            views.setOnClickPendingIntent(R.id.widget_mic_btn, voicePendingIntent)

            if (payloadStr != null) {
                try {
                    val json = JSONObject(payloadStr)
                    val goalsStr = json.optString("goals", "")
                    views.setTextViewText(R.id.widget_goals, goalsStr)

                    val itemsArray = json.optJSONArray("items")
                    val itemIds = intArrayOf(R.id.item_0, R.id.item_1, R.id.item_2, R.id.item_3)

                    val count = itemsArray?.length() ?: 0
                    if (count == 0) {
                        views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                        views.setViewVisibility(R.id.row_1, View.GONE)
                        views.setViewVisibility(R.id.row_2, View.GONE)
                    } else {
                        views.setViewVisibility(R.id.widget_empty, View.GONE)
                        views.setViewVisibility(R.id.row_1, View.VISIBLE)
                        views.setViewVisibility(R.id.row_2, if (count > 2) View.VISIBLE else View.GONE)

                        for (i in 0 until 4) {
                            val viewId = itemIds[i]
                            if (i < count) {
                                val item = itemsArray!!.getJSONObject(i)
                                val id = item.getInt("id")
                                val title = item.getString("t")
                                val done = item.optBoolean("d", false)
                                val sub = item.optString("s", "")

                                val label = if (done) "✓ $title" else (if (sub.isNotEmpty()) "$title ($sub)" else title)
                                views.setTextViewText(viewId, label)
                                val itemBgRes = when (theme) {
                                    "dark" -> if (done) R.drawable.widget_item_done_bg_dark else R.drawable.widget_item_bg_dark
                                    "light" -> if (done) R.drawable.widget_item_done_bg_light else R.drawable.widget_item_bg_light
                                    else -> if (done) R.drawable.widget_item_done_bg else R.drawable.widget_item_bg
                                }
                                views.setInt(
                                    viewId,
                                    "setBackgroundResource",
                                    itemBgRes
                                )
                                views.setViewVisibility(viewId, View.VISIBLE)

                                // Background click intent to log or untick item without opening app!
                                val tapUri = Uri.parse("takip://tap?id=$id")
                                val itemPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                                    context,
                                    tapUri
                                )
                                views.setOnClickPendingIntent(viewId, itemPendingIntent)
                            } else {
                                views.setViewVisibility(viewId, View.GONE)
                            }
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            } else {
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setViewVisibility(R.id.row_1, View.GONE)
                views.setViewVisibility(R.id.row_2, View.GONE)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
