package dev.takip.takip

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodoRemoteViewsFactory(applicationContext, intent)
    }
}

internal data class TodoWidgetItem(
    val id: Int,
    val title: String,
    val due: String,
    val overdue: Boolean,
    val linked: Boolean,
    val sub: String
)

class TodoRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private val items = ArrayList<TodoWidgetItem>()
    private var isTr = true
    private var locale = Locale("tr", "TR")
    private var theme = "system"

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    private fun loadData() {
        items.clear()
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        theme = intent.getStringExtra("theme") ?: prefs.getString("widget_theme", "system") ?: "system"
        val payloadStr = prefs.getString("todo_payload", null) ?: return

        try {
            val json = JSONObject(payloadStr)
            val t = json.optString("theme", "")
            if (t.isNotEmpty()) theme = t
            isTr = json.optBoolean("isTr", true)
            locale = if (isTr) Locale("tr", "TR") else Locale.ENGLISH

            val jsonArray = json.optJSONArray("items") ?: return
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                items.add(
                    TodoWidgetItem(
                        id = obj.getInt("id"),
                        title = obj.getString("t"),
                        due = obj.optString("due", ""),
                        overdue = obj.optBoolean("overdue", false),
                        linked = obj.optBoolean("linked", false),
                        sub = obj.optString("sub", "")
                    )
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position < 0 || position >= items.size) return null
        val item = items[position]

        val itemLayoutId = when (theme) {
            "dark" -> R.layout.todo_widget_item_dark
            "light" -> R.layout.todo_widget_item_light
            else -> R.layout.todo_widget_item
        }
        val views = RemoteViews(context.packageName, itemLayoutId)
        views.setTextViewText(R.id.todo_item_title, item.title)

        val todayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val todayStr = todayFormat.format(Date())

        val (dueText, isOverdue) = formatTodoDue(item.due, todayStr, locale, isTr)

        val fullSub = when {
            item.sub.isNotEmpty() && dueText.isNotEmpty() -> "${item.sub} · $dueText"
            item.sub.isNotEmpty() -> item.sub
            else -> dueText
        }

        if (isOverdue) {
            views.setTextViewText(R.id.todo_item_sub_overdue, fullSub)
            views.setViewVisibility(R.id.todo_item_sub_overdue, View.VISIBLE)
            views.setViewVisibility(R.id.todo_item_sub, View.GONE)
        } else {
            views.setTextViewText(R.id.todo_item_sub, fullSub)
            views.setViewVisibility(R.id.todo_item_sub, View.VISIBLE)
            views.setViewVisibility(R.id.todo_item_sub_overdue, View.GONE)
        }

        // İçi boş onay halkası (gecikmişte kırmızı kontur, temaya uygun halka)
        val ringDrawable = when (theme) {
            "dark" -> if (isOverdue) R.drawable.todo_check_ring_overdue_dark else R.drawable.todo_check_ring_dark
            "light" -> if (isOverdue) R.drawable.todo_check_ring_overdue_light else R.drawable.todo_check_ring_light
            else -> if (isOverdue) R.drawable.todo_check_ring_overdue else R.drawable.todo_check_ring
        }
        views.setInt(
            R.id.todo_item_check,
            "setBackgroundResource",
            ringDrawable
        )
        views.setTextViewText(R.id.todo_item_check, "")

        // Fill-in Intent for Check Ring:
        // Bağlı: tamamlama önizlemesini açar; Bağlantısız: uygulamayı açmadan arka planda tamamlar
        val checkFillIn = Intent().apply {
            if (item.linked) {
                action = TodoWidgetActionReceiver.ACTION_LAUNCH
                data = Uri.parse("takip://todo_preview?id=${item.id}")
            } else {
                action = TodoWidgetActionReceiver.ACTION_TOGGLE
                data = Uri.parse("takip://todo_toggle?id=${item.id}")
            }
        }
        views.setOnClickFillInIntent(R.id.todo_item_check, checkFillIn)

        // Fill-in Intent for Row:
        // Satıra dokunmak TodosPage'i açar
        val rowFillIn = Intent().apply {
            action = TodoWidgetActionReceiver.ACTION_LAUNCH
            data = Uri.parse("takip://todos")
        }
        views.setOnClickFillInIntent(R.id.todo_item_row, rowFillIn)
        views.setOnClickFillInIntent(R.id.todo_item_title, rowFillIn)
        views.setOnClickFillInIntent(R.id.todo_item_sub, rowFillIn)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 3

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
