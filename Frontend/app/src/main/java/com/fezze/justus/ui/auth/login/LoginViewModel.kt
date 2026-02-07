package com.fezze.justus.ui.auth.login

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.models.LoginResponse
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
class LoginViewModel(private val repo: ApiRepository = ApiRepository()) : ViewModel() {
    private val _uiEvents = MutableSharedFlow<LoginEvent>()
    val uiEvents: SharedFlow<LoginEvent> = _uiEvents
    fun login(context: Context, usernameWithCode: String, password: String, deviceToken: String) {
        if (usernameWithCode.isBlank() || password.isBlank()) {
            emitMessage("Compila tutti i campi", context)
            return
        }
        viewModelScope.launch {
            when (val result = repo.loginUser(usernameWithCode, password, deviceToken)) {
                is ResultWrapper.Success -> handleLoginSuccess(result.value, context)
                is ResultWrapper.GenericError -> emitMessage(
                    if (result.code == 404) "Utente non trovato" else "Errore server (${result.code})",
                    context
                )
                is ResultWrapper.NetworkError -> emitMessage("Connessione assente", context)
            }
        }
    }
    fun requestCodes(username: String, password: String, context: Context) {
        if (username.isBlank() || password.isBlank()) {
            emitMessage("Compila tutti i campi", context)
            return
        }
        viewModelScope.launch {
            when (val result = repo.requestUserCodes(username, password)) {
                is ResultWrapper.Success -> handleCodesSuccess(result.value.codes.orEmpty())
                is ResultWrapper.GenericError -> {
                    val msg = when (result.code) {
                        400 -> "Compila tutti i campi"
                        404 -> "Utente non trovato"
                        401 -> "Password errata"
                        else -> "Errore server (${result.code})"
                    }
                    emitMessage(msg, context)
                }
                is ResultWrapper.NetworkError -> emitMessage("Connessione assente", context)
            }
        }
    }
    private suspend fun handleLoginSuccess(body: LoginResponse, context: Context) {
        body.accessToken?.let { SharedPrefsManager.saveAccessToken(context, it) }
        body.refreshToken?.let { SharedPrefsManager.saveRefreshToken(context, it) }
        body.user?.let { user ->
            SharedPrefsManager.saveUsername(context, user.username)
        }
        if (body.accessToken != null && !body.user?.code.isNullOrBlank()) {
            _uiEvents.emit(LoginEvent.SuccessLogin(body.user.username))
        } else {
            emitMessage(body.error ?: body.message ?: "Errore login", context)
        }
    }
    private suspend fun handleCodesSuccess(codes: List<String>) {
        when {
            codes.isEmpty() -> _uiEvents.emit(LoginEvent.ShowMessage("Codice utente non trovato"))
            codes.size == 1 -> _uiEvents.emit(LoginEvent.SingleCodeFound(codes.first()))
            else -> _uiEvents.emit(LoginEvent.MultipleCodesFound(codes))
        }
    }
    private fun emitMessage(msg: String, context: Context) {
        viewModelScope.launch {
            VibrationUtils.vibrateError(context)
            _uiEvents.emit(LoginEvent.ShowMessage(msg))
        }
    }
    sealed class LoginEvent {
        data class SuccessLogin(val username: String) : LoginEvent()
        data class ShowMessage(val msg: String) : LoginEvent()
        data class SingleCodeFound(val code: String) : LoginEvent()
        data class MultipleCodesFound(val codes: List<String>) : LoginEvent()
    }
}