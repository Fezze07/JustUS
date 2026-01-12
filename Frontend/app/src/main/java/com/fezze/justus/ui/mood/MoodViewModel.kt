package com.fezze.justus.ui.mood
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
class MoodViewModel(
    private val repo: ApiRepository = ApiRepository(),
    private val notificationVm: NotificationViewModel = NotificationViewModel()
) : ViewModel() {
    private val _userMood = MutableStateFlow<String?>("😐")
    val userMood: StateFlow<String?> = _userMood
    private val _partnerMood = MutableStateFlow<String?>("😐")
    val partnerMood: StateFlow<String?> = _partnerMood
    private val _recentEmojis = MutableStateFlow<List<String>>(emptyList())
    val recentEmojis: StateFlow<List<String>> = _recentEmojis
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    // ------------------ FUNZIONI ------------------
    fun loadPartnerMoodFromCache(context: Context) {
        _partnerMood.value = MoodLocalCache.getMood(context, "partner") ?: "😐"
    }
    fun fetchMyMood(context: Context) {
        viewModelScope.launch {
            when (val result = repo.fetchMyMood()) {
                is ResultWrapper.Success -> {
                    val emoji = result.value.emoji ?: "😐"
                    _userMood.value = emoji
                    MoodLocalCache.saveMood(context, "me", emoji)
                }
                is ResultWrapper.GenericError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Errore server nel cercare il mood", vibrate = true))
                is ResultWrapper.NetworkError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", vibrate = true))
            }
        }
    }
    fun fetchPartnerMood(context: Context) {
        viewModelScope.launch {
            when (val result = repo.fetchPartnerMood()) {
                is ResultWrapper.Success -> {
                    val emoji = result.value.emoji ?: "😐"
                    _partnerMood.value = emoji
                    MoodLocalCache.saveMood(context, "partner", emoji)
                }
                is ResultWrapper.GenericError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Errore server nel cercare il mood", vibrate = true))
                is ResultWrapper.NetworkError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", vibrate = true))
            }
        }
    }
    fun fetchRecentEmojis(context: Context) {
        viewModelScope.launch {
            when (val result = repo.fetchRecentCoupleEmojis()) {
                is ResultWrapper.Success -> {
                    _recentEmojis.value = result.value
                    MoodLocalCache.saveRecentEmojis(context, result.value)
                }
                is ResultWrapper.GenericError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Errore server nel cercare le emoji recenti", vibrate = true))
                is ResultWrapper.NetworkError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", vibrate = true))
            }
        }
    }
    fun updateMood(partnerId: Int, emoji: String, context: Context) {
        viewModelScope.launch {
            when (val result = repo.setMood(emoji)) {
                is ResultWrapper.Success -> {
                    val newEmoji = result.value.emoji ?: "😐"
                    _userMood.value = newEmoji
                    MoodLocalCache.saveMood(context, "me" , newEmoji)
                    notificationVm.sendNotification(
                        type = "mood",
                        receiverId = partnerId,
                        title = "Mood aggiornato 😎",
                        body = "Il tuo partner ha cambiato mood!"
                    )
                    _uiEvents.emit(UiEvent.ShowMessage("Mood aggiornato!"))
                }
                is ResultWrapper.GenericError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Errore server nel cambio mood", vibrate = true))
                is ResultWrapper.NetworkError ->
                    _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", vibrate = true))
            }
        }
    }
    fun loadCache(context: Context) {
        val myMood = MoodLocalCache.getMood(context, "me")
        _userMood.value = myMood ?: "😐"
        fetchMyMood(context)
        val recent = MoodLocalCache.getRecentEmojis(context)
        if (recent.isNotEmpty()) _recentEmojis.value = recent
    }
}