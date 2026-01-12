package com.fezze.justus.ui.partner

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.JustusApp
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.models.PartnershipResponse
import com.fezze.justus.data.models.User
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

@OptIn(FlowPreview::class)
class PartnerViewModel() : ViewModel() {
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    private val repository: ApiRepository = ApiRepository()
    private val notificationVm: NotificationViewModel = NotificationViewModel()
    val usernameQuery = MutableStateFlow("")
    val codeQuery = MutableStateFlow("")
    private val _suggestedUsers = MutableStateFlow<List<User>>(emptyList())
    val suggestedUsers: StateFlow<List<User>> = _suggestedUsers.asStateFlow()
    private val _partnershipInfo = MutableStateFlow<PartnershipResponse?>(null)
    val partnershipInfo: StateFlow<PartnershipResponse?> = _partnershipInfo.asStateFlow()
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    init {
        viewModelScope.launch {
            combine(usernameQuery, codeQuery) { username, code -> username to code }
                .debounce(300)
                .distinctUntilChanged()
                .collect { (username, code) ->
                    fetchSuggestions(username, code)
                }
        }
        fetchPartnership()
    }
    private fun fetchSuggestions(username: String?, code: String?) {
        viewModelScope.launch {
            if (username.isNullOrBlank() && code.isNullOrBlank()) {
                _suggestedUsers.value = emptyList()
                return@launch
            }
            when (val result = repository.searchPartner(username, code)) {
                is ResultWrapper.Success -> _suggestedUsers.value = result.value
                is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Errore rete", true))
            }
        }
    }
    fun fetchPartnership() = viewModelScope.launch {
        val result = repository.getPartnership()
        if (result is ResultWrapper.Success) {
            result.value.partner?.let { partner ->
                SharedPrefsManager.savePartner(
                    context = JustusApp.appContext,
                    partnerId = partner.id,
                    username = partner.username
                )
            }
            _partnershipInfo.value = result.value
        } else {
            _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
        }
    }
    fun sendPartnerRequest(username: String, code: String) = viewModelScope.launch {
        val currentUser = SharedPrefsManager.getUsername(JustusApp.appContext) ?: return@launch
        when(val result = repository.sendPartnerRequest(username, code)) {
            is ResultWrapper.Success -> {
                _uiEvents.emit(UiEvent.ShowMessage("Richiesta inviata a $username"))
                notificationVm.sendNotificationPartner(
                    type = "partner_request",
                    username = username,
                    code = code,
                    title = "Nuova richiesta di partnership!",
                    body = "$currentUser ti ha inviato una richiesta"
                )
                fetchPartnership()
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Errore rete", true))
        }
    }

    fun acceptPartner(requesterId: Int) = viewModelScope.launch {
        val currentUser = SharedPrefsManager.getUsername(JustusApp.appContext) ?: return@launch
        when(val result = repository.acceptPartnerRequest(requesterId)) {
            is ResultWrapper.Success -> {
                _uiEvents.emit(UiEvent.ShowMessage("Richiesta accettata"))
                SharedPrefsManager.savePartner(
                    context = JustusApp.appContext,
                    partnerId = requesterId,
                    username = _partnershipInfo.value?.pendingRequests?.received?.find { it.id == requesterId }?.username ?: ""
                )
                notificationVm.sendNotification(
                    type = "partner_accept",
                    receiverId = requesterId,
                    title = "Richiesta accettata!",
                    body = "$currentUser ha accettato la tua richiesta 💗"
                )
                fetchPartnership()
            }
            else -> _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
        }
    }
    fun rejectPartner(requesterId: Int) = viewModelScope.launch {
        when(val result = repository.rejectPartnerRequest(requesterId)) {
            is ResultWrapper.Success -> {
                _partnershipInfo.update { info ->
                    info?.copy(
                        pendingRequests = info.pendingRequests?.copy(
                            received = info.pendingRequests.received.filter { it.id != requesterId })
                    )
                }
                _uiEvents.emit(UiEvent.ShowMessage("Richiesta rifiutata"))
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Errore rete", true))
        }
    }
}
