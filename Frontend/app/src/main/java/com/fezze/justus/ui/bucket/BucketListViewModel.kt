package com.fezze.justus.ui.bucket

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.models.BucketItem
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
class BucketListViewModel(private val repo: ApiRepository = ApiRepository(),
                          private val notificationVm: NotificationViewModel = NotificationViewModel()) : ViewModel() {
    val items = MutableStateFlow<List<BucketItem>>(emptyList())
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    fun initBucket(context: Context) {
        items.value = SharedPrefsManager.getBucketList(context)
        fetchBucket(context)
    }
    fun fetchBucket(context: Context) = viewModelScope.launch {
        when (val res = repo.fetchBucketList()) {
            is ResultWrapper.Success -> {
                if (res.value.success) {
                    items.value = res.value.items
                    SharedPrefsManager.saveBucketList(context, res.value.items)
                } else _uiEvents.emit(UiEvent.ShowMessage("Errore nel caricamento", true))
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Offline 😴", true))
        }
    }
    fun addItem(text: String, currentUser: String, partnerId: Int, context: Context) = viewModelScope.launch {
        when (repo.addBucketItem(text)) {
            is ResultWrapper.Success -> {
                sendNotification(currentUser, partnerId)
                fetchBucket(context)
            }
            else -> _uiEvents.emit(UiEvent.ShowMessage("Errore salvataggio", true))
        }
    }
    fun toggleDone(id: Int, context: Context) = viewModelScope.launch {
        when (repo.toggleBucketDone(id)) {
            is ResultWrapper.Success -> {
                val newList = items.value.map {
                    if (it.id == id) it.copy(done = if (it.done == 1) 0 else 1) else it
                }
                items.value = newList
                SharedPrefsManager.saveBucketList(context, newList)
            }
            else -> _uiEvents.emit(UiEvent.ShowMessage("Errore aggiornamento", true))
        }
    }
    fun deleteItem(id: Int, context: Context) = viewModelScope.launch {
        when (repo.deleteBucketItem(id)) {
            is ResultWrapper.Success -> {
                val newList = items.value.filterNot { it.id == id }
                items.value = newList
                SharedPrefsManager.saveBucketList(context, newList)
            }
            else -> _uiEvents.emit(UiEvent.ShowMessage("Errore cancellazione", true))
        }
    }
    private fun sendNotification(sender: String, partnerId: Int) {
        notificationVm.sendNotification(
            type = "bucket",
            receiverId = partnerId,
            title = "Nuovo promemoria 🎯",
            body = "$sender ha aggiunto qualcosa di nuovo da fare"
        )
    }
}