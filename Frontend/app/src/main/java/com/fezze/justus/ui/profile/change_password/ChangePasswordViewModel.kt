package com.fezze.justus.ui.profile.change_password

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.launch

class ChangePasswordViewModel(private val repo: ApiRepository = ApiRepository()) : ViewModel() {
    private val _state = MutableLiveData<ResultWrapper<Unit>>()
    val state: LiveData<ResultWrapper<Unit>> = _state
    fun changePassword(oldPassword: String, newPassword: String) {
        if (oldPassword.isBlank() || newPassword.isBlank()) {
            _state.value = ResultWrapper.GenericError(null, "Compila tutti i campi")
            return
        }
        if (newPassword.length < 4) {
            _state.value = ResultWrapper.GenericError(null, "Password troppo corta")
            return
        }
        viewModelScope.launch {
            _state.value = repo.changePassword(oldPassword, newPassword)
        }
    }
}
