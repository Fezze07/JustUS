package com.fezze.justus.data.notification

import android.Manifest
import com.fezze.justus.R
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.fezze.justus.JustusApp
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.ui.auth.login.LoginActivity
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.launch

class MyFirebaseMessagingService : FirebaseMessagingService() {
    @RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val title = message.notification?.title ?: "JustUS"
        val body = message.notification?.body ?: ""
        showNotification(title, body)
    }
    @RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
    private fun showNotification(title: String, body: String) {
        val channelId = "justus_channel"
        val channel = NotificationChannel(
            channelId,
            "JustUS Notifications",
            NotificationManager.IMPORTANCE_HIGH
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
        val intent = Intent(this, LoginActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
        NotificationManagerCompat.from(this)
            .notify(System.currentTimeMillis().toInt(), builder.build())
    }
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val username = SharedPrefsManager.getUsername(JustusApp.appContext)
        if (username != null) {
            val repo = ApiRepository()
            kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                try {
                    repo.updateDeviceToken(username, token)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
}