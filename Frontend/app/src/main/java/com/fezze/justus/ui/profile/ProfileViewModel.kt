package com.fezze.justus.ui.profile
import android.content.Context
import android.net.Uri
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.models.User
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.UploadNotificationHelper
import com.fezze.justus.utils.ResultWrapper
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
class ProfileViewModel(private val repo: ApiRepository = ApiRepository()) : ViewModel() {
    private val _userProfileState = MutableLiveData<ResultWrapper<User>>()
    val userProfileState: LiveData<ResultWrapper<User>> = _userProfileState
    private val _partnerProfileState = MutableLiveData<ResultWrapper<User>>()
    val partnerProfileState: LiveData<ResultWrapper<User>> = _partnerProfileState
    private val _updateUserBioState = MutableLiveData<ResultWrapper<Unit>>()
    val updateUserBioState: LiveData<ResultWrapper<Unit>> = _updateUserBioState
    private val _localProfileImage = MutableLiveData<Uri?>()
    val localProfileImage: LiveData<Uri?> = _localProfileImage
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    fun loadProfile(context: Context) {
        viewModelScope.launch {
            val cachedUser = ProfileLocalCache.getUserProfile(context)
            val cachedPartner = ProfileLocalCache.getPartnerProfile(context)
            if (cachedUser != null) _userProfileState.value = ResultWrapper.Success(cachedUser)
            if (cachedPartner != null) _partnerProfileState.value = ResultWrapper.Success(cachedPartner)
            when (val serverUser = repo.fetchProfile()) {
                is ResultWrapper.Success -> {
                    val profile = serverUser.value
                    _userProfileState.value = ResultWrapper.Success(profile)
                    ProfileLocalCache.saveUserProfile(context, profile)
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", true))
            }
            when (val serverPartner = repo.fetchPartnerProfile()) {
                is ResultWrapper.Success -> {
                    val profile = serverPartner.value
                    _partnerProfileState.value = ResultWrapper.Success(profile)
                    ProfileLocalCache.savePartnerProfile(context, profile)
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server partner", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Nessuna connessione", true))
            }
        }
    }
    fun updateBio(context: Context, bio: String?) {
        viewModelScope.launch {
            _updateUserBioState.value = repo.updateProfileBio(bio)
            bio?.let {
                _userProfileState.value?.let { current ->
                    if (current is ResultWrapper.Success) {
                        val updatedProfile = current.value.copy(bio = it)
                        _userProfileState.value = ResultWrapper.Success(updatedProfile)
                        ProfileLocalCache.saveUserProfile(context, updatedProfile)
                    }
                }
            }
        }
    }
    fun setLocalProfileImage(uri: Uri) {
        _localProfileImage.value = null
        _localProfileImage.value = uri
    }
    fun uploadProfilePhoto(context: Context, fileUri: Uri, fileName: String, mimeType: String, fileSize: Long) {
        viewModelScope.launch {
            _userProfileState.value?.let { current ->
                if (current is ResultWrapper.Success) {
                    val updatedProfile = current.value.copy(profile_pic_url = fileUri.toString())
                    _userProfileState.value = ResultWrapper.Success(updatedProfile)
                }
            }
            _uiEvents.emit(UiEvent.ShowMessage("Caricamento foto profilo...", false))
            when (val result = repo.uploadProfile(context, fileUri, fileName, mimeType) { uploadedBytes ->
                val progress = ((uploadedBytes.toDouble() / fileSize) * 100).toInt()
                UploadNotificationHelper.showUploadNotification(context, fileName, progress)
            }) {
                is ResultWrapper.Success -> {
                    _userProfileState.value?.let { current ->
                        if (current is ResultWrapper.Success) {
                            val updatedProfile = current.value.copy(profile_pic_url = result.value)
                            _userProfileState.value = ResultWrapper.Success(updatedProfile)
                            ProfileLocalCache.saveUserProfile(context, updatedProfile)
                            ProfileLocalCache.saveProfilePicVersion(context, System.currentTimeMillis())
                        }
                    }
                    _uiEvents.emit(UiEvent.ShowMessage("Foto profilo aggiornata!"))
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore upload: ${result.message}", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Errore di rete", true))
            }
            UploadNotificationHelper.cancelUploadNotification(context, fileName)
            _localProfileImage.value = null
        }
    }
}