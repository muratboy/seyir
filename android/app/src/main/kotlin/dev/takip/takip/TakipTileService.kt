package dev.takip.takip

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import org.json.JSONObject

class TakipTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        tile.state = Tile.STATE_ACTIVE
        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val payloadStr = prefs.getString("payload", null)
        var isTr = true
        if (payloadStr != null) {
            try {
                val json = JSONObject(payloadStr)
                isTr = json.optBoolean("isTr", true)
            } catch (_: Exception) {}
        }
        tile.label = if (isTr) "Hızlı Kayıt" else "Quick Log"
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, QuickRecordActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
