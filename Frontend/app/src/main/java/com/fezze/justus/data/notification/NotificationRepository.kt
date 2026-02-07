package com.fezze.justus.data.notification

import com.fezze.justus.JustusApp
import com.fezze.justus.data.models.NotificationRequest
import com.fezze.justus.data.models.NotificationResponse
import com.fezze.justus.data.models.PartnerNotificationRequest
import com.fezze.justus.data.network.ApiService
import com.fezze.justus.data.network.RetrofitClient

class NotificationRepository(private val api: ApiService = RetrofitClient.getApi(JustusApp.appContext)) {
    suspend fun sendNotification(type: String, request: NotificationRequest): NotificationResponse? {
        return try {
            val res = api.sendNotification(type, request)
            if (res.isSuccessful) res.body() else null
        } catch (_: Exception) {
            null
        }
    }
    suspend fun sendNotificationPartner(request: PartnerNotificationRequest): NotificationResponse? {
        return try {
            val res = api.sendNotificationPartner(request)
            if (res.isSuccessful) res.body() else null
        } catch (_: Exception) {
            null
        }
    }
}