package dev.takip.takip

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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

    private fun formatDue(due: String, todayStr: String, locale: Locale, isTr: Boolean): Pair<String, Boolean> {
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

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val todayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val todayStr = todayFormat.format(Date())

        val rowIds = intArrayOf(
            R.id.todo_row_0, R.id.todo_row_1, R.id.todo_row_2,
            R.id.todo_row_3, R.id.todo_row_4, R.id.todo_row_5,
            R.id.todo_row_6, R.id.todo_row_7, R.id.todo_row_8,
            R.id.todo_row_9
        )
        val checkIds = intArrayOf(
            R.id.todo_check_0, R.id.todo_check_1, R.id.todo_check_2,
            R.id.todo_check_3, R.id.todo_check_4, R.id.todo_check_5,
            R.id.todo_check_6, R.id.todo_check_7, R.id.todo_check_8,
            R.id.todo_check_9
        )
        val titleIds = intArrayOf(
            R.id.todo_title_0, R.id.todo_title_1, R.id.todo_title_2,
            R.id.todo_title_3, R.id.todo_title_4, R.id.todo_title_5,
            R.id.todo_title_6, R.id.todo_title_7, R.id.todo_title_8,
            R.id.todo_title_9
        )
        val subIds = intArrayOf(
            R.id.todo_sub_0, R.id.todo_sub_1, R.id.todo_sub_2,
            R.id.todo_sub_3, R.id.todo_sub_4, R.id.todo_sub_5,
            R.id.todo_sub_6, R.id.todo_sub_7, R.id.todo_sub_8,
            R.id.todo_sub_9
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.todo_widget)

            // [+] Butonu doğrudan hızlı eklemeyi açar
            val addUri = Uri.parse("takip://todo_add")
            val addPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                addUri
            )
            views.setOnClickPendingIntent(R.id.todo_widget_add_btn, addPendingIntent)

            // Başlık veya boş durum dokunması
            val todosListUri = Uri.parse("takip://todos")
            val listPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                todosListUri
            )
            views.setOnClickPendingIntent(R.id.todo_widget_title, listPendingIntent)
            views.setOnClickPendingIntent(R.id.todo_widget_empty, addPendingIntent)

            val payloadStr = widgetData.getString("todo_payload", null)
            if (payloadStr != null) {
                try {
                    val json = JSONObject(payloadStr)
                    val count = json.optInt("count", 0)
                    val isTr = json.optBoolean("isTr", true)
                    val locale = if (isTr) Locale("tr", "TR") else Locale.ENGLISH
                    val prefix = if (isTr) "Yapılacaklar" else "To-dos"
                    val titleText = if (count > 0) "$prefix · $count" else prefix
                    views.setTextViewText(R.id.todo_widget_title, titleText)
                    views.setTextViewText(R.id.todo_widget_empty, if (isTr) "Yapılacak yok · + Ekle" else "No to-dos · + Add")

                    val itemsArray = json.optJSONArray("items")
                    val itemsCount = itemsArray?.length() ?: 0

                    if (itemsCount == 0) {
                        views.setViewVisibility(R.id.todo_widget_empty, View.VISIBLE)
                        views.setViewVisibility(R.id.todo_items_list, View.GONE)
                        views.setViewVisibility(R.id.todo_widget_more, View.GONE)
                    } else {
                        views.setViewVisibility(R.id.todo_widget_empty, View.GONE)
                        views.setViewVisibility(R.id.todo_items_list, View.VISIBLE)

                        // Widget yüksekliğine göre sığabilecek satır sayısını dinamik hesapla
                        val options = appWidgetManager.getAppWidgetOptions(widgetId)
                        val isPortrait = context.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT
                        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
                        val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minH)
                        val widgetHeightDp = if (isPortrait && maxH > 0) maxH else minH

                        val rowHeightDp = 24
                        val moreHeightDp = 18
                        val overheadDp = 48 // padding (20dp) + header (24dp) + divider (4dp)
                        val availableDp = (widgetHeightDp - overheadDp).coerceAtLeast(rowHeightDp)

                        val maxWithMore = ((availableDp - moreHeightDp) / rowHeightDp).coerceIn(1, rowIds.size)
                        val maxWithoutMore = (availableDp / rowHeightDp).coerceIn(1, rowIds.size)

                        val (visibleRows, showMore) = if (itemsCount <= maxWithoutMore) {
                            Pair(minOf(itemsCount, maxWithoutMore), false)
                        } else {
                            Pair(minOf(itemsCount, maxWithMore), true)
                        }

                        for (i in 0 until rowIds.size) {
                            val rowId = rowIds[i]
                            val checkId = checkIds[i]
                            val titleId = titleIds[i]
                            val subId = subIds[i]

                            if (i < visibleRows && i < itemsCount) {
                                val item = itemsArray!!.getJSONObject(i)
                                val id = item.getInt("id")
                                val title = item.getString("t")
                                val due = item.optString("due", "")
                                val linked = item.optBoolean("linked", false)
                                val sub = item.optString("sub", "")

                                views.setTextViewText(titleId, title)

                                // Yerelleştirilmiş tarih etiketi ("Cum", "10 Kas", "dün", "3 gün")
                                val (dueText, isOverdue) = formatDue(due, todayStr, locale, isTr)

                                val fullSub = when {
                                    sub.isNotEmpty() && dueText.isNotEmpty() -> "$sub · $dueText"
                                    sub.isNotEmpty() -> sub
                                    else -> dueText
                                }

                                views.setTextViewText(subId, fullSub)
                                val subColor = if (isOverdue) 0xFFE53935.toInt() else 0xFF64748B.toInt()
                                views.setTextColor(subId, subColor)

                                // İçi boş onay halkası (gecikmişte kırmızı kontur)
                                views.setInt(
                                    checkId,
                                    "setBackgroundResource",
                                    if (isOverdue) R.drawable.todo_check_ring_overdue else R.drawable.todo_check_ring
                                )
                                views.setTextViewText(checkId, "")

                                // Tıklama: onay halkası tamamlar, satır Todos'u açar
                                views.setOnClickPendingIntent(titleId, listPendingIntent)
                                views.setOnClickPendingIntent(subId, listPendingIntent)

                                if (linked) {
                                    // Bağlı yapılacak: uygulamayı tamamlama önizlemesine açar (önce göster, sonra yap)
                                    val previewUri = Uri.parse("takip://todo_preview?id=$id")
                                    val previewPendingIntent = HomeWidgetLaunchIntent.getActivity(
                                        context,
                                        MainActivity::class.java,
                                        previewUri
                                    )
                                    views.setOnClickPendingIntent(checkId, previewPendingIntent)
                                } else {
                                    // Bağlantısız yapılacak: uygulamayı açmadan arka planda tamamlar!
                                    val toggleUri = Uri.parse("takip://todo_toggle?id=$id")
                                    val togglePendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                                        context,
                                        toggleUri
                                    )
                                    views.setOnClickPendingIntent(checkId, togglePendingIntent)
                                }

                                views.setViewVisibility(rowId, View.VISIBLE)
                            } else {
                                views.setViewVisibility(rowId, View.GONE)
                            }
                        }

                        // Sığmayanlar varsa "+N daha"
                        if (showMore && itemsCount > visibleRows) {
                            val moreCount = itemsCount - visibleRows
                            views.setTextViewText(R.id.todo_widget_more, "+$moreCount ${if (isTr) "daha" else "more"}")
                            views.setOnClickPendingIntent(R.id.todo_widget_more, listPendingIntent)
                            views.setViewVisibility(R.id.todo_widget_more, View.VISIBLE)
                        } else {
                            views.setViewVisibility(R.id.todo_widget_more, View.GONE)
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            } else {
                val isTr = true
                val prefix = if (isTr) "Yapılacaklar" else "To-dos"
                views.setTextViewText(R.id.todo_widget_title, prefix)
                views.setTextViewText(R.id.todo_widget_empty, if (isTr) "Yapılacak yok · + Ekle" else "No to-dos · + Add")
                views.setViewVisibility(R.id.todo_widget_empty, View.VISIBLE)
                views.setViewVisibility(R.id.todo_items_list, View.GONE)
                views.setViewVisibility(R.id.todo_widget_more, View.GONE)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
