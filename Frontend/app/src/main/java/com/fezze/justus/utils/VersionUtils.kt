package com.fezze.justus.utils

import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import com.fezze.justus.BuildConfig
import com.fezze.justus.R
import com.fezze.justus.data.local.SharedPrefsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

object VersionUtils {
    fun handleVersioning(context: Context) {
        val currentVersion = BuildConfig.VERSION_NAME
        val savedVersion = SharedPrefsManager.getLastInstalledVersion(context)
        Log.d("VersionUtils", "handleVersioning: current=$currentVersion, saved=$savedVersion")
        if (savedVersion != currentVersion) {
            Log.d("VersionUtils", "Versione cambiata: $savedVersion -> $currentVersion, pulendo cache")
            SharedPrefsManager.clearAppCache(context)
            SharedPrefsManager.saveLastInstalledVersion(context, currentVersion)
        }
    }
    fun isUpdateAvailable(localVersion: String, serverVersion: String): Boolean {
        val localParts = localVersion.split(".").map { it.toIntOrNull() ?: 0 }
        val serverParts = serverVersion.split(".").map { it.toIntOrNull() ?: 0 }
        Log.d("VersionUtils", "Local: $localVersion, Server: $serverVersion")
        for (i in 0 until maxOf(localParts.size, serverParts.size)) {
            val local = localParts.getOrElse(i) { 0 }
            val server = serverParts.getOrElse(i) { 0 }
            if (server > local) return true
            if (server < local) return false
        }
        return false
    }
    fun showUpdateDialog(activity: Activity, apkUrl: String, changelog: String) {
        val dialogView = activity.layoutInflater.inflate(R.layout.version_update, null)
        val progressBar = dialogView.findViewById<ProgressBar>(R.id.progressBar)
        val progressText = dialogView.findViewById<TextView>(R.id.progressText)
        val dialog = AlertDialog.Builder(activity)
            .setTitle("Nuovo aggiornamento disponibile!")
            .setMessage(changelog)
            .setView(dialogView)
            .setPositiveButton("Aggiorna", null)
            .setNegativeButton("Chiudi", null)
            .create()
        dialog.setOnShowListener {
            val button = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
            button.setOnClickListener {
                startDownload(activity, apkUrl, progressBar, progressText)
            }
        }
        dialog.show()
    }
    fun startDownload(activity: Activity, url: String, progressBar: ProgressBar, progressText: TextView) {
        val fileName = "app-update.apk"
        val request = DownloadManager.Request(url.toUri())
            .setTitle("Scaricando aggiornamento")
            .setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS, fileName)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
        val manager = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)
        CoroutineScope(Dispatchers.IO).launch {
            var downloading = true
            while (downloading) {
                val cursor = manager.query(DownloadManager.Query().setFilterById(downloadId))
                if (cursor.moveToFirst()) {
                    val bytesDownloaded =
                        cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val bytesTotal =
                        cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    val status =
                        cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    if (bytesTotal > 0) {
                        val progress = ((bytesDownloaded * 100) / bytesTotal).toInt()
                        withContext(Dispatchers.Main) {
                            progressBar.isIndeterminate = false
                            progressBar.progress = progress
                            progressText.text = "Scaricando: $progress%"
                        }
                    }
                    if (status == DownloadManager.STATUS_SUCCESSFUL) {
                        downloading = false
                    }
                }
                cursor.close()
                delay(300)
            }
            // Percorsi del file scaricato
            val file = File(activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "app-update.apk")
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
            // Intent di installazione
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            withContext(Dispatchers.Main) {
                activity.startActivity(installIntent)
            }
        }
    }
    fun canInstallUnknownApps(context: Context): Boolean {
        return context.packageManager.canRequestPackageInstalls()
    }
    fun requestInstallPermission(activity: Activity, requestCode: Int) {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = "package:${activity.packageName}".toUri()
        }
        activity.startActivityForResult(intent, requestCode)
    }
    fun installApkWithPermission(activity: Activity, apkFile: File, requestCode: Int) {
        if (canInstallUnknownApps(activity)) {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(installIntent)
        } else {
            requestInstallPermission(activity, requestCode)
        }
    }
}
