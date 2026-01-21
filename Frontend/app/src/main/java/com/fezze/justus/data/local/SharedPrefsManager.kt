package com.fezze.justus.data.local

import android.content.Context
import com.fezze.justus.BuildConfig
import androidx.core.content.edit
import com.fezze.justus.data.models.*
import com.fezze.justus.ui.drive.DriveLocalCache.KEY_DRIVE_CACHE
import com.fezze.justus.ui.drive.DriveLocalCache.KEY_DRIVE_LAST_SYNC
import com.fezze.justus.ui.drive.DriveLocalCache.KEY_DRIVE_THUMB_CACHE
import com.fezze.justus.ui.mood.MoodLocalCache.KEY_RECENT_EMOJIS
import com.fezze.justus.ui.profile.ProfileLocalCache.KEY_PARTNER_PROFILE
import com.fezze.justus.ui.profile.ProfileLocalCache.KEY_PROFILE_PIC_VERSION
import com.fezze.justus.ui.profile.ProfileLocalCache.KEY_USER_PROFILE
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

object SharedPrefsManager {
    private const val PREFS_NAME = "justus_prefs"
    private const val KEY_USERNAME = "username"
    private const val KEY_USER_CODE = "user_code"
    private const val KEY_TOKEN = "token"
    private const val KEY_PARTNER_ID = "partner_id"
    private const val KEY_PARTNER_USERNAME = "partner_username"
    private const val KEY_MISS_YOU_TOTAL = "miss_you"
    private const val BUCKET_LIST_KEY = "bucket_list"
    private const val GAME_MATCHES_KEY = "game_matches"
    private const val GAME_QUESTION_KEY = "game_question"
    fun saveUsername(context: Context, username: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putString(KEY_USERNAME, username) }
    }
    fun getUsername(context: Context): String? =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_USERNAME, null)
    fun saveUserCode(context: Context, code: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putString(KEY_USER_CODE, code) }
    }
    fun getUserCode(context: Context): String? =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_USER_CODE, null)
    fun saveToken(context: Context, token: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putString(KEY_TOKEN, token) }
    }
    fun getToken(context: Context): String? =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_TOKEN, null)
    fun savePartner(context: Context, partnerId: Int, username: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putInt(KEY_PARTNER_ID, partnerId)
                .putString(KEY_PARTNER_USERNAME, username)
            }
    }
    fun getPartnerId(context: Context): Int? {
        val id = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_PARTNER_ID, -1)
        return if (id != -1) id else null
    }
    fun getPartnerUsername(context: Context): String? =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PARTNER_USERNAME, null)
    fun saveTotalMissYou(context: Context, total: Int) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit { putInt(KEY_MISS_YOU_TOTAL, total) }
    }
    fun getTotalMissYou(context: Context): Int? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return if (prefs.contains(KEY_MISS_YOU_TOTAL)) prefs.getInt(KEY_MISS_YOU_TOTAL, 0) else null
    }
    fun saveBucketList(context: Context, list: List<BucketItem>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = Gson().toJson(list)
        prefs.edit { putString(BUCKET_LIST_KEY, json) }
    }
    fun getBucketList(context: Context): List<BucketItem> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(BUCKET_LIST_KEY, null) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<BucketItem>>() {}.type
            Gson().fromJson(json, type)
        } catch (_: Exception) {
            emptyList()
        }
    }
    fun saveGameMatches(context: Context, total: Int) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit { putInt(GAME_MATCHES_KEY, total) }
    }
    fun getGameMatches(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getInt(GAME_MATCHES_KEY, 0)
    }
    fun saveGameQuestion(context: Context, question: GameNewQuestionResponse) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = Gson().toJson(question)
        prefs.edit { putString(GAME_QUESTION_KEY, json) }
    }
    fun getCachedGameQuestion(context: Context): GameNewQuestionResponse? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(GAME_QUESTION_KEY, null) ?: return null
        return try {
            Gson().fromJson(json, GameNewQuestionResponse::class.java)
        } catch (_: Exception) {
            null
        }
    }
    fun clearAppCache(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit {
            remove(BUCKET_LIST_KEY)
            remove(GAME_MATCHES_KEY)
            remove(GAME_QUESTION_KEY)
            remove(KEY_MISS_YOU_TOTAL)
            remove(KEY_RECENT_EMOJIS)
            remove(KEY_DRIVE_CACHE)
            remove(KEY_DRIVE_LAST_SYNC)
            remove(KEY_PROFILE_PIC_VERSION)
            remove(KEY_DRIVE_THUMB_CACHE)
        }
    }
}
