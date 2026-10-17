package dev.takip.takip

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
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
            updateSingleWidget(context, appWidgetManager, widgetId, widgetData)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        appWidgetIds.forEach { id ->
            editor.remove("single_act_id_$id")
        }
        editor.apply()
    }

    companion object {
        fun updateSingleWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
            widgetData: SharedPreferences
        ) {
            val views = RemoteViews(context.packageName, R.layout.takip_single_widget)

            val payloadStr = widgetData.getString("payload", null)
            var title = "Seyir"
            var sub = ""
            var emoji = "⚡"
            var actId = 0
            var done = false

            // Belirli bir widget'a atanmış aktivite ID'si; yoksa genel ayar (-1 = ayarlanmamış)
            val specificActId = widgetData.getInt("single_act_id_$widgetId", -1)
            val targetActId = if (specificActId != -1) specificActId else widgetData.getInt("single_act_id_global", 0)

            if (payloadStr != null) {
                try {
                    val json = JSONObject(payloadStr)
                    val isTr = json.optBoolean("isTr", true)

                    if (targetActId > 0) {
                        val acts = json.optJSONArray("activities")
                        var found = false
                        if (acts != null) {
                            for (i in 0 until acts.length()) {
                                val a = acts.getJSONObject(i)
                                if (a.optInt("id") == targetActId) {
                                    title = a.optString("name", "Seyir")
                                    emoji = a.optString("emoji", "⚡")
                                    val count = a.optInt("count", 0)
                                    done = count > 0
                                    sub = if (done) (if (isTr) "Bugün $count" else "Today $count") else (if (isTr) "Dokun: Kaydet" else "Tap to log")
                                    actId = targetActId
                                    found = true
                                    break
                                }
                            }
                        }
                        if (!found) {
                            // Veritabanından doğrudan dene (payload henüz güncellenmemişse)
                            try {
                                val dbFile = context.getDatabasePath("takip.db")
                                if (dbFile.exists()) {
                                    val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY)
                                    val c = db.rawQuery("SELECT name, emoji FROM activities WHERE id = ?", arrayOf(targetActId.toString()))
                                    if (c.moveToFirst()) {
                                        title = c.getString(0)
                                        emoji = if (c.isNull(1)) "⚡" else c.getString(1)
                                        actId = targetActId
                                        sub = if (isTr) "Dokun: Kaydet" else "Tap to log"
                                        found = true
                                    }
                                    c.close()
                                    db.close()
                                }
                            } catch (_: Exception) {}
                        }
                        if (!found) {
                            // Belirtilen aktivite bulunamazsa varsayılan akıllı öneriye dön
                            title = json.optString("single_title", "Seyir")
                            sub = json.optString("single_sub", "")
                            emoji = json.optString("single_emoji", "⚡")
                            actId = json.optInt("single_act_id", 0)
                            done = json.optBoolean("single_done", false)
                        }
                    } else {
                        // Otomatik / Akıllı mod (Alışkanlık > Hedef > Saate göre öneri)
                        title = json.optString("single_title", "Seyir")
                        sub = json.optString("single_sub", "")
                        emoji = json.optString("single_emoji", "⚡")
                        actId = json.optInt("single_act_id", 0)
                        done = json.optBoolean("single_done", false)
                    }
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
