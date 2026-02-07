package com.fezze.justus.ui.game

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.models.GameNewQuestionResponse
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
class GameViewModel(private val repo: ApiRepository, private val notificationVm: NotificationViewModel
) : ViewModel() {
    private val _currentQuestion = MutableStateFlow<GameNewQuestionResponse?>(null)
    val currentQuestion: StateFlow<GameNewQuestionResponse?> = _currentQuestion
    private val _gameStats = MutableStateFlow(0)
    val gameStats: StateFlow<Int> = _gameStats
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    fun initGame(context: Context) {
        SharedPrefsManager.getCachedGameQuestion(context)?.let {
            _currentQuestion.value = it
        }
        _gameStats.value = SharedPrefsManager.getGameMatches(context)
        fetchStats(context)
        viewModelScope.launch {
            val result = repo.fetchNewGameQuestion()
            if (result is ResultWrapper.Success && result.value.id != _currentQuestion.value?.id) {
                _currentQuestion.value = result.value
                SharedPrefsManager.saveGameQuestion(context, result.value)
            }
        }
    }
    fun fetchNewQuestion(context: Context) = viewModelScope.launch {
        when (val result = repo.fetchNewGameQuestion()) {
            is ResultWrapper.Success -> {
                _currentQuestion.value = result.value
                SharedPrefsManager.saveGameQuestion(context, result.value)
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage(result.message ?: "Errore generico", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Problema di rete", true))
        }
    }
    fun submitAnswer(votedFor: String, currentUser: String, partnerId: Int, context: Context) {
        val questionId = _currentQuestion.value?.id ?: return
        viewModelScope.launch {
            when (repo.submitGameAnswer(questionId, votedFor)) {
                is ResultWrapper.Success -> {
                    _uiEvents.emit(UiEvent.ShowMessage("Risposta inviata! ✨"))
                    notificationVm.sendNotification(
                        type = "game_answers",
                        receiverId = partnerId,
                        title = "Risposta inviata ✨",
                        body = "$currentUser ha risposto alla domanda!"
                    )
                    _currentQuestion.value = _currentQuestion.value?.copy(
                        status = "waiting",
                        message = "Aspetta che il partner risponda"
                    )
                    SharedPrefsManager.saveGameQuestion(context, _currentQuestion.value!!)
                    fetchStats(context)
                    fetchNewQuestion(context)
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore generico", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Problema di rete", true))
            }
        }
    }
    fun fetchStats(context: Context) = viewModelScope.launch {
        when (val result = repo.fetchGameStats()) {
            is ResultWrapper.Success -> {
                _gameStats.value = result.value.totalMatches
                SharedPrefsManager.saveGameMatches(context, result.value.totalMatches)
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage(result.message ?: "Errore generico", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Problema di rete", true))
        }
    }
    fun sendReminderNotification(currentUser: String, partnerId: Int) {
        viewModelScope.launch {
            notificationVm.sendNotification(
                type = "game_reminder",
                receiverId = partnerId,
                title = "Promemoria Gioco 🔔",
                body = "Ricordati di rispondere alla domanda!"
            )
            _uiEvents.emit(UiEvent.ShowMessage("Promemoria inviato! 🔔"))
        }
    }
}