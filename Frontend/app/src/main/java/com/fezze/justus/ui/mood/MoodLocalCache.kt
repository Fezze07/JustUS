package com.fezze.justus.ui.mood

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import androidx.core.content.edit

object MoodLocalCache {
    private const val PREFS_NAME = "justus_prefs"
    const val KEY_RECENT_EMOJIS = "cached_recent_emojis"
    private val gson = Gson()
    fun saveMood(context: Context, target: String, emoji: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putString("mood_$target", emoji) }
    }
    fun getMood(context: Context, target: String): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString("mood_$target", null)
    }
    fun saveRecentEmojis(context: Context, emojis: List<String>) {
        val toSave = emojis.take(4)
        val json = gson.toJson(toSave)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putString(KEY_RECENT_EMOJIS, json) }
    }
    fun getRecentEmojis(context: Context): List<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_RECENT_EMOJIS, null) ?: return emptyList()
        val type = object : TypeToken<List<String>>() {}.type
        return gson.fromJson(json, type) ?: emptyList()
    }
}
