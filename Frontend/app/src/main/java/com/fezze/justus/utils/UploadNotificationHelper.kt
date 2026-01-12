package com.fezze.justus.utils

import android.R
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat

object UploadNotificationHelper {
    private const val CHANNEL_ID = "upload_channel"
    private const val CHANNEL_NAME = "Upload File"
    fun showUploadNotification(context: Context, fileName: String, progress: Int, ongoing: Boolean = true) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
        manager.createNotificationChannel(channel)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Caricamento: $fileName")
            .setSmallIcon(R.drawable.stat_sys_upload)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, progress == 0)
            .setOngoing(ongoing)
            .build()
        manager.notify(fileName.hashCode(), notification)
    }
    fun cancelUploadNotification(context: Context, fileName: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(fileName.hashCode())
    }
}