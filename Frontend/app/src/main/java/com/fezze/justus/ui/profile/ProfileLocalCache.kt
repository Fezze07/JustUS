package com.fezze.justus.ui.profile

import android.content.Context
import androidx.core.content.edit
import com.fezze.justus.data.models.User
import com.google.gson.Gson

object ProfileLocalCache {
    private const val PREFS_NAME = "justus_prefs"
    const val KEY_USER_PROFILE = "cached_user_profile"
    const val KEY_PARTNER_PROFILE = "cached_partner_profile"
    const val KEY_PROFILE_PIC_VERSION = "cached_profile_pic_version"
    private val gson = Gson()
    fun saveUserProfile(context: Context, profile: User) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = gson.toJson(profile)
        prefs.edit { putString(KEY_USER_PROFILE, json) }
    }
    fun getUserProfile(context: Context): User? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_USER_PROFILE, null) ?: return null
        return gson.fromJson(json, User::class.java)
    }
    fun savePartnerProfile(context: Context, profile: User) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = gson.toJson(profile)
        prefs.edit { putString(KEY_PARTNER_PROFILE, json) }
    }
    fun getPartnerProfile(context: Context): User? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_PARTNER_PROFILE, null) ?: return null
        return gson.fromJson(json, User::class.java)
    }
    fun saveProfilePicVersion(context: Context, version: Long) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit { putLong(KEY_PROFILE_PIC_VERSION, version) }
    }
    fun getProfilePicVersion(context: Context): Long {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_PROFILE_PIC_VERSION, 0)
    }
}
