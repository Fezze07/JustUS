package com.fezze.justus

import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.PartnerChecker
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.VersionUtils
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch

open class BaseActivity : AppCompatActivity() {
    protected var partnerId: Int? = null
    protected open fun onPartnerReady() {}
    private val repo: ApiRepository = ApiRepository()
    private val _uiEvents = MutableSharedFlow<UiEvent>()
    val uiEvents: SharedFlow<UiEvent> = _uiEvents
    sealed class UiEvent {
        data class ShowMessage(val message: String, val vibrate: Boolean = false) : UiEvent()
    }
    override fun onStart() {
        super.onStart()
        checkAppVersion()
    }
    private fun checkAppVersion() {
        lifecycleScope.launch {
            when (val result = repo.checkAppVersion()) {
                is ResultWrapper.Success -> {
                    val versionInfo = result.value
                    val currentVersion = BuildConfig.VERSION_NAME
                    if (currentVersion == versionInfo.version || !VersionUtils.isUpdateAvailable(currentVersion, versionInfo.version)) {
                        startPartnerCheck()
                        return@launch
                    }
                    // Se c'è un aggiornamento disponibile e non lo stiamo già mostrando, mostra il dialog
                    if (!VersionUtils.isUpdateDialogShowing) {
                        if (!VersionUtils.canInstallUnknownApps(this@BaseActivity)) {
                            VersionUtils.requestInstallPermission(this@BaseActivity, 12345)
                        } else {
                            VersionUtils.showUpdateDialog(this@BaseActivity, versionInfo.apk_url, versionInfo.changelog)
                        }
                    }
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(UiEvent.ShowMessage("Errore server versione app", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(UiEvent.ShowMessage("Problema di rete", true))
            }
        }
    }
    private fun startPartnerCheck() {
        PartnerChecker.checkPartner(this) { hasPartner ->
            if (!hasPartner) return@checkPartner
            partnerId = SharedPrefsManager.getPartnerId(this)
            onPartnerReady()
        }
    }
}
