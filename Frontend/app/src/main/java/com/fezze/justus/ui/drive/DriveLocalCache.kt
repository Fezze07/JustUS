package com.fezze.justus.ui.drive

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.fezze.justus.data.models.*
import androidx.core.content.edit

object DriveLocalCache {
    private const val PREFS_NAME = "justus_prefs"
    const val KEY_DRIVE_CACHE = "cached_drive_items"
    const val KEY_DRIVE_LAST_SYNC = "last_sync"
    const val KEY_DRIVE_THUMB_CACHE = "cached_thumbs"
    private val gson = Gson()

    // 1️⃣ Salva lista completa degli item
    fun saveCachedDriveItems(context: Context, items: List<DriveItem>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = gson.toJson(items)
        prefs.edit { putString(KEY_DRIVE_CACHE, json) }
    }
    // 2️⃣ Legge gli item cache-ati
    fun getCachedDriveItems(context: Context): List<DriveItem> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_DRIVE_CACHE, null) ?: return emptyList()
        val type = object : TypeToken<List<DriveItem>>() {}.type
        return gson.fromJson(json, type) ?: emptyList()
    }
    // 3️⃣ Applica le changes e aggiorna la cache
    fun applyDriveChangesToCache(context: Context, changes: List<DriveChange>, newLastSync: String) {
        // Prendi la lista corrente
        val current = getCachedDriveItems(context).toMutableList()
        changes.forEach { change ->
            when (change.action.lowercase()) {
                "create" -> {
                    change.item?.let { item ->
                        // Evito duplicati in caso di sync strani
                        current.removeAll { it.id == item.id }
                        current.add(item)
                    }
                }
                "update" -> {
                    change.item?.let { item ->
                        val idx = current.indexOfFirst { it.id == item.id }
                        if (idx != -1) current[idx] = item
                    }
                }
                "delete" -> {
                    current.removeAll { it.id == change.id }
                }
            }
        }
        saveCachedDriveItems(context, current)
        saveLastSync(context, newLastSync)
    }
    fun saveLastSync(context: Context, timestamp: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit {
                putString(KEY_DRIVE_LAST_SYNC, timestamp)
            }
    }
    fun getLastSync(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_DRIVE_LAST_SYNC, null)
    }
    fun saveThumbPath(context: Context, itemId: Int, path: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val map = getThumbMap(context).toMutableMap()
        map[itemId.toString()] = path
        prefs.edit { putString(KEY_DRIVE_THUMB_CACHE, Gson().toJson(map)) }
    }
    fun getThumbMap(context: Context): Map<String, String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_DRIVE_THUMB_CACHE, "{}")
        val type = object : TypeToken<Map<String, String>>() {}.type
        return Gson().fromJson(json, type) ?: emptyMap()
    }
    fun getThumbPath(context: Context, itemId: Int): String? {
        return getThumbMap(context)[itemId.toString()]
    }
}
