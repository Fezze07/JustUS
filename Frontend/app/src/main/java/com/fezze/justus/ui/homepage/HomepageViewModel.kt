package com.fezze.justus.ui.homepage

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class HomepageViewModel(private val repo: ApiRepository = ApiRepository()) : ViewModel() {
    private val _totalMissYou = MutableStateFlow(0)
    val totalMissYou: StateFlow<Int> = _totalMissYou
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    fun initTotalMissYou(context: Context) {
        val cachedTotal = SharedPrefsManager.getTotalMissYou(context) ?: 0
        _totalMissYou.value = cachedTotal
        viewModelScope.launch { fetchTotalMissYou(context) }
    }
    fun fetchTotalMissYou(context: Context) = viewModelScope.launch {
        when (val result = repo.fetchMissYouTotal()) {
            is ResultWrapper.Success -> {
                _totalMissYou.value = result.value
                SharedPrefsManager.saveTotalMissYou(context, result.value)
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server nel calcolo totale", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", true))
        }
    }
    fun sendMissYou(context: Context) = viewModelScope.launch {
        when (val result = repo.sendMissYou()) {
            is ResultWrapper.Success -> {
                val newTotal = result.value
                _totalMissYou.value = newTotal
                SharedPrefsManager.saveTotalMissYou(context, newTotal)
                _uiEvents.emit(UiEvent.ShowMessage("Mi manchi inviato!"))
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server invio Mi manchi", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Problema di rete", true))
        }
    }
}