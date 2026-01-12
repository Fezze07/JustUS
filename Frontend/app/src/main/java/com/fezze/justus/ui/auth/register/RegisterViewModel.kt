package com.fezze.justus.ui.auth.register

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.models.User
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
class RegisterViewModel(private val repo: ApiRepository = ApiRepository()) : ViewModel() {
    private val _uiEvents = MutableSharedFlow<RegisterEvent>()
    val uiEvents: SharedFlow<RegisterEvent> = _uiEvents
    fun register(context: Context, username: String, password: String, email: String, deviceToken: String) {
        if (username.isBlank() || password.isBlank()) {
            viewModelScope.launch {
                VibrationUtils.vibrateError(context)
                _uiEvents.emit(RegisterEvent.ShowMessage("Inserisci username e password", true))
            }
            return
        }
        viewModelScope.launch {
            try {
                when (val result = repo.registerUser(username, password, email, deviceToken)) {
                    is ResultWrapper.Success -> {
                        val user = result.value.user
                        if (user != null) {
                            _uiEvents.emit(RegisterEvent.SuccessRegister(user))
                        } else {
                            VibrationUtils.vibrateError(context)
                            _uiEvents.emit(
                                RegisterEvent.ShowMessage(
                                    result.value.message ?: "Errore registrazione",
                                    true
                                )
                            )
                        }
                    }
                    is ResultWrapper.GenericError -> {
                        VibrationUtils.vibrateError(context)
                        _uiEvents.emit(RegisterEvent.ShowMessage("Errore server (${result.code})", true))
                    }
                    is ResultWrapper.NetworkError -> {
                        VibrationUtils.vibrateError(context)
                        _uiEvents.emit(RegisterEvent.ShowMessage("Connessione assente", true))
                    }
                }
            } catch (e: Exception) {
                VibrationUtils.vibrateError(context)
                _uiEvents.emit(RegisterEvent.ShowMessage("Errore imprevisto: ${e.localizedMessage}", true))
            }
        }
    }
    sealed class RegisterEvent {
        data class SuccessRegister(val user: User) : RegisterEvent()
        data class ShowMessage(val msg: String, val vibrate: Boolean = false) : RegisterEvent()
    }
}