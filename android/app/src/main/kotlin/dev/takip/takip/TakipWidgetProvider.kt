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
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.takip_widget)

            // Quick Add button opens app directly into composer
            val addUri = Uri.parse("takip://add")
            val addPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                addUri
            )
            views.setOnClickPendingIntent(R.id.widget_add_btn, addPendingIntent)

            val payloadStr = widgetData.getString("payload", null)
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
                                views.setInt(
                                    viewId,
                                    "setBackgroundResource",
                                    if (done) R.drawable.widget_item_done_bg else R.drawable.widget_item_bg
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
