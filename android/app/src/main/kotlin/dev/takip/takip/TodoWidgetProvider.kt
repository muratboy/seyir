package dev.takip.takip

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal fun formatTodoDue(due: String, todayStr: String, locale: Locale, isTr: Boolean): Pair<String, Boolean> {
    if (due.isEmpty()) return Pair("", false)
    val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val dueDate = try { sdf.parse(due) } catch (e: Exception) { null } ?: return Pair(due, false)
    val todayDate = try { sdf.parse(todayStr) } catch (e: Exception) { null } ?: Date()

    val diffDays = Math.round((dueDate.time - todayDate.time).toDouble() / (1000 * 60 * 60 * 24)).toInt()

    return when {
        diffDays < -1 -> Pair(if (isTr) "${-diffDays} gün" else "${-diffDays}d", true)
        diffDays == -1 -> Pair(if (isTr) "dün" else "yesterday", true)
        diffDays == 0 -> Pair(if (isTr) "bugün" else "today", false)
        diffDays == 1 -> Pair(if (isTr) "yarın" else "tomorrow", false)
        diffDays in 2..6 -> {
            val dayFormat = SimpleDateFormat("EEE", locale)
            val dayName = dayFormat.format(dueDate).replace(".", "")
            Pair(dayName.replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }, false)
        }
        else -> {
            val monthFormat = if (isTr) SimpleDateFormat("d MMM", locale) else SimpleDateFormat("MMM d", locale)
            Pair(monthFormat.format(dueDate).replace(".", ""), false)
        }
    }
}

class TodoWidgetProvider : HomeWidgetProvider() {

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), widgetData)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val payloadStr = widgetData.getString("todo_payload", null)
        var theme = widgetData.getString("widget_theme", "system") ?: "system"
        var count = 0
        var isTr = true
        if (payloadStr != null) {
            try {
                val json = JSONObject(payloadStr)
                val t = json.optString("theme", "")
                if (t.isNotEmpty()) theme = t
                count = json.optInt("count", 0)
                isTr = json.optBoolean("isTr", true)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        val layoutId = when (theme) {
            "dark" -> R.layout.todo_widget_dark
            "light" -> R.layout.todo_widget_light
            else -> R.layout.todo_widget
        }

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, layoutId)

            // [+] Butonu doğrudan hızlı eklemeyi açar
            val addUri = Uri.parse("takip://todo_add")
            val addPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                addUri
            )
            views.setOnClickPendingIntent(R.id.todo_widget_add_btn, addPendingIntent)

            // Başlık veya boş durum dokunması: TodosPage'i veya hızlı eklemeyi açar
            val todosListUri = Uri.parse("takip://todos")
            val listPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                todosListUri
            )
            views.setOnClickPendingIntent(R.id.todo_widget_title, listPendingIntent)
            views.setOnClickPendingIntent(R.id.todo_widget_empty, addPendingIntent)

            val prefix = if (isTr) "Yapılacaklar" else "To-dos"
            val titleText = if (count > 0) "$prefix · $count" else prefix
            views.setTextViewText(R.id.todo_widget_title, titleText)
            views.setTextViewText(R.id.todo_widget_empty, if (isTr) "Yapılacak yok · + Ekle" else "No to-dos · + Add")

            // RemoteAdapter ile kaydırılabilir ListView bağla
            val serviceIntent = Intent(context, TodoWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                putExtra("theme", theme)
                data = Uri.parse("takip://todo_service/$widgetId?theme=$theme")
            }
            views.setRemoteAdapter(R.id.todo_list_view, serviceIntent)
            views.setEmptyView(R.id.todo_list_view, R.id.todo_widget_empty)

            // ListView öğeleri için PendingIntentTemplate
            val templateIntent = Intent(context, TodoWidgetActionReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= 31) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val templatePendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                templateIntent,
                flags
            )
            views.setPendingIntentTemplate(R.id.todo_list_view, templatePendingIntent)

            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.todo_list_view)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
