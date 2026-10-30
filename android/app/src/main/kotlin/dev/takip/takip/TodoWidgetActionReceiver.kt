package dev.takip.takip

import android.app.ActivityOptions
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class TodoWidgetActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TOGGLE = "dev.takip.takip.TODO_ACTION_TOGGLE"
        const val ACTION_LAUNCH = "dev.takip.takip.TODO_ACTION_LAUNCH"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val uri = intent.data ?: return

        if (intent.action == ACTION_TOGGLE || uri.host == "todo_toggle") {
            // Bağlantısız yapılacak: uygulamayı açmadan arka planda tamamlar
            val bgIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                action = "es.antonborri.home_widget.action.BACKGROUND"
                data = uri
            }
            context.sendBroadcast(bgIntent)
        } else {
            // Bağlı yapılacak (önizleme) veya liste açılışı: TodosPage'i açar
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = uri
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val options = ActivityOptions.makeBasic()
                if (Build.VERSION.SDK_INT >= 35) {
                    options.setPendingIntentCreatorBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                } else {
                    options.pendingIntentBackgroundActivityStartMode =
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                }
                context.startActivity(launchIntent, options.toBundle())
            } else {
                context.startActivity(launchIntent)
            }
        }
    }
}
