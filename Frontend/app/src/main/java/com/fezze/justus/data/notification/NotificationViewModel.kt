package com.fezze.justus.data.notification

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.models.NotificationRequest
import com.fezze.justus.data.models.NotificationResponse
import com.fezze.justus.data.models.PartnerNotificationRequest
import kotlinx.coroutines.launch
class NotificationViewModel : ViewModel() {
    private val repo = NotificationRepository()
    private val _result = MutableLiveData<NotificationResponse?>()
    val result: LiveData<NotificationResponse?> = _result
    fun sendNotification(type: String, receiverId: Int, title: String, body: String) {
        viewModelScope.launch {
            val req = NotificationRequest(receiverId = receiverId, title = title, body = body)
            val res = repo.sendNotification(type, req)
            _result.postValue(res)
        }
    }
    fun sendNotificationPartner(type: String, username: String, code: String, title: String, body: String) {
        viewModelScope.launch {
            val req = PartnerNotificationRequest(type, username, code, title, body)
            val res = repo.sendNotificationPartner(req)
            _result.postValue(res)
        }
    }
}

