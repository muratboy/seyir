package dev.takip.takip

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject

class SingleWidgetConfigureActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    data class ActivityOption(
        val id: Int,
        val name: String,
        val emoji: String,
        val count: Int,
        val isHabit: Boolean
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Kullanıcı iptal ederse varsayılan RESULT_CANCELED
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.activity_single_widget_configure)

        val root = findViewById<View>(R.id.widget_config_root)
        val closeBtn = findViewById<View>(R.id.widget_config_close)
        val listContainer = findViewById<LinearLayout>(R.id.widget_config_list)

        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val payloadStr = prefs.getString("payload", null)
        var isTr = true
        if (payloadStr != null) {
            try {
                val json = JSONObject(payloadStr)
                isTr = json.optBoolean("isTr", true)
            } catch (_: Exception) {}
        }
        findViewById<TextView>(R.id.widget_config_subtitle)?.text = if (isTr) "Dokunulduğunda hangi aktivite kaydedilsin?" else "Which activity should a tap log?"

        root.setOnClickListener { finish() }
        closeBtn.setOnClickListener { finish() }

        populateOptions(listContainer, isTr, payloadStr)
    }

    private fun populateOptions(container: LinearLayout, isTr: Boolean, payloadStr: String?) {
        val density = resources.displayMetrics.density
        val activities = mutableListOf<ActivityOption>()

        if (payloadStr != null) {
            try {
                val json = JSONObject(payloadStr)
                val acts = json.optJSONArray("activities")
                if (acts != null) {
                    for (i in 0 until acts.length()) {
                        val a = acts.getJSONObject(i)
                        activities.add(
                            ActivityOption(
                                id = a.getInt("id"),
                                name = a.getString("name"),
                                emoji = a.optString("emoji", "⚡"),
                                count = a.optInt("count", 0),
                                isHabit = a.optBoolean("isHabit", false)
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // Eğer payload'da henüz aktivite yoksa doğrudan veritabanından oku
        if (activities.isEmpty()) {
            try {
                val dbFile = getDatabasePath("takip.db")
                if (dbFile.exists()) {
                    val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY)
                    val cursor = db.rawQuery(
                        "SELECT id, name, emoji, is_habit FROM activities WHERE is_archived = 0 ORDER BY name COLLATE NOCASE ASC",
                        null
                    )
                    while (cursor.moveToNext()) {
                        activities.add(
                            ActivityOption(
                                id = cursor.getInt(0),
                                name = cursor.getString(1),
                                emoji = if (cursor.isNull(2)) "⚡" else cursor.getString(2),
                                count = 0,
                                isHabit = cursor.getInt(3) == 1
                            )
                        )
                    }
                    cursor.close()
                    db.close()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        container.removeAllViews()

        // 1. Seçenek: Akıllı / Otomatik Öneri
        val autoRow = createOptionRow(
            emoji = "⚡",
            title = if (isTr) "Akıllı / Otomatik Öneri" else "Smart / Auto Suggestion",
            subtitle = if (isTr) "Sıradaki alışkanlık veya saate göre öneri" else "Next habit or time suggestion",
            density = density
        ) {
            selectActivity(0)
        }
        container.addView(autoRow)

        // Ayırıcı çizgi
        val divider = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (1 * density).toInt()
            ).apply {
                setMargins(0, (8 * density).toInt(), 0, (8 * density).toInt())
            }
            setBackgroundColor(Color.parseColor("#334155"))
        }
        container.addView(divider)

        // 2. Aktif aktiviteler
        for (act in activities) {
            val sub = if (act.isHabit) {
                if (isTr) "Alışkanlık" else "Habit"
            } else if (act.count > 0) {
                if (isTr) "Bugün: ${act.count}" else "Today: ${act.count}"
            } else {
                null
            }

            val row = createOptionRow(
                emoji = act.emoji,
                title = act.name,
                subtitle = sub,
                density = density
            ) {
                selectActivity(act.id)
            }
            container.addView(row)
        }
    }

    private fun createOptionRow(
        emoji: String,
        title: String,
        subtitle: String?,
        density: Float,
        onClick: () -> Unit
    ): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val padH = (12 * density).toInt()
            val padV = (10 * density).toInt()
            setPadding(padH, padV, padH, padV)
            setBackgroundResource(R.drawable.quick_chip_bg)
            isClickable = true
            isFocusable = true

            val layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (6 * density).toInt()
            }
            setLayoutParams(layoutParams)
            setOnClickListener { onClick() }
        }

        // Emoji
        val emojiView = TextView(this).apply {
            text = emoji
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            val marginEndDp = (12 * density).toInt()
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = marginEndDp
            }
        }
        row.addView(emojiView)

        // Başlık ve alt başlık
        val textContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            )
        }

        val titleView = TextView(this).apply {
            text = title
            setTextColor(Color.parseColor("#FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        }
        textContainer.addView(titleView)

        if (subtitle != null) {
            val subView = TextView(this).apply {
                text = subtitle
                setTextColor(Color.parseColor("#94A3B8"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            }
            textContainer.addView(subView)
        }
        row.addView(textContainer)

        return row
    }

    private fun selectActivity(actId: Int) {
        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        prefs.edit().putInt("single_act_id_$appWidgetId", actId).apply()

        val appWidgetManager = AppWidgetManager.getInstance(this)
        TakipSingleWidgetProvider.updateSingleWidget(this, appWidgetManager, appWidgetId, prefs)

        val resultValue = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        setResult(RESULT_OK, resultValue)
        finish()
    }
}
