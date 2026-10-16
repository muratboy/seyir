package dev.takip.takip

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.RecognizerIntent
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

class QuickRecordActivity : Activity() {

    private lateinit var inputEdit: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Kilit ekranı üstünde göster (şifre girmeden anında kayıt)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        setContentView(R.layout.activity_quick_record)

        val root = findViewById<View>(R.id.quick_record_root)
        val card = findViewById<View>(R.id.quick_record_card)
        val closeBtn = findViewById<View>(R.id.quick_close_btn)
        val openAppBtn = findViewById<View>(R.id.quick_open_app_btn)
        val micBtn = findViewById<View>(R.id.quick_mic_btn)
        val sendBtn = findViewById<View>(R.id.quick_send_btn)
        inputEdit = findViewById(R.id.quick_input_text)

        // Kartın dışına dokunulduğunda kapat
        root.setOnClickListener { finish() }
        card.setOnClickListener { /* tüket */ }

        closeBtn.setOnClickListener { finish() }

        openAppBtn.setOnClickListener {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                data = Uri.parse("takip://add")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(intent)
            finish()
        }

        sendBtn.setOnClickListener {
            submitText(inputEdit.text.toString())
        }

        inputEdit.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND || actionId == EditorInfo.IME_ACTION_DONE) {
                submitText(inputEdit.text.toString())
                true
            } else {
                false
            }
        }

        micBtn.setOnClickListener {
            startVoiceInput()
        }

        loadSuggestionChips()
    }

    private fun loadSuggestionChips() {
        val container = findViewById<LinearLayout>(R.id.quick_chips_container)
        val label = findViewById<View>(R.id.quick_suggestions_label)
        val scroll = findViewById<View>(R.id.quick_chips_scroll)

        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val payloadStr = prefs.getString("payload", null)

        if (payloadStr == null) {
            label.visibility = View.GONE
            scroll.visibility = View.GONE
            return
        }

        try {
            val json = JSONObject(payloadStr)
            val items = json.optJSONArray("items")
            if (items == null || items.length() == 0) {
                label.visibility = View.GONE
                scroll.visibility = View.GONE
                return
            }

            container.removeAllViews()
            val density = resources.displayMetrics.density

            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val id = item.getInt("id")
                val title = item.getString("t")
                val sub = item.optString("s", "")
                val actId = item.optInt("actId", if (id < 0) -id else 0)

                val chip = TextView(this).apply {
                    val labelText = if (sub.isNotEmpty()) "$title ($sub)" else title
                    text = labelText
                    setTextColor(Color.parseColor("#E2E8F0"))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setBackgroundResource(R.drawable.quick_chip_bg)
                    gravity = Gravity.CENTER
                    val padH = (12 * density).toInt()
                    val padV = (8 * density).toInt()
                    setPadding(padH, padV, padH, padV)

                    val layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply {
                        marginEnd = (8 * density).toInt()
                    }
                    setLayoutParams(layoutParams)

                    setOnClickListener {
                        val uri = if (id < 0) {
                            Uri.parse("takip://repeat?actId=${-id}")
                        } else {
                            Uri.parse("takip://tap?id=$id")
                        }
                        sendBackgroundBroadcast(uri)
                        Toast.makeText(this@QuickRecordActivity, "✓ $title kaydedildi", Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
                container.addView(chip)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            label.visibility = View.GONE
            scroll.visibility = View.GONE
        }
    }

    private fun submitText(rawText: String) {
        val text = rawText.trim()
        if (text.isEmpty()) return

        val uri = Uri.parse("takip://quick_text?text=" + Uri.encode(text))
        sendBackgroundBroadcast(uri)

        Toast.makeText(this, "✓ Kaydedildi: $text", Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun sendBackgroundBroadcast(uri: Uri) {
        val intent = Intent(this, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
            data = uri
        }
        sendBroadcast(intent)
    }

    private fun startVoiceInput() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Ne yaptın? Konuşun...")
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, 2001)
        } catch (e: Exception) {
            Toast.makeText(this, "Ses tanıma bu cihazda desteklenmiyor", Toast.LENGTH_SHORT).show()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 2001 && resultCode == RESULT_OK && data != null) {
            val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            val text = matches?.firstOrNull()?.trim()
            if (!text.isNullOrEmpty()) {
                inputEdit.setText(text)
                inputEdit.setSelection(text.length)
                inputEdit.requestFocus()
            }
        }
    }
}
