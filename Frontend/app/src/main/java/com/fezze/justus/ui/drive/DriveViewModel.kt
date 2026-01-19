package com.fezze.justus.ui.drive
import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.data.models.*
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.UploadNotificationHelper
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

@Suppress("USELESS_ELVIS")
class DriveViewModel : ViewModel() {
    private val repository = ApiRepository()
    private val _driveItems = MutableStateFlow<List<DriveItem>>(emptyList())
    val driveItems: StateFlow<List<DriveItem>> get() = _driveItems
    private val _singleItem = MutableStateFlow<DriveItem?>(null)
    val singleItem: StateFlow<DriveItem?> get() = _singleItem
    private val _uiEvents = MutableSharedFlow<DriveEvent>()
    val uiEvents: SharedFlow<DriveEvent> get() = _uiEvents

    /** Carica cache locale + fetch completo dal server */
    fun initialLoad(context: Context) {
        viewModelScope.launch {
            val cached = DriveLocalCache.getCachedDriveItems(context)
            val validItems = cached
                .map { it.copy(reactions = it.reactions ?: emptyList()) }
                .sortedByDescending { it.created_at }
            if (validItems.isNotEmpty()) {
                _driveItems.value = validItems
                if (validItems.size != cached.size) {
                    DriveLocalCache.saveCachedDriveItems(context, validItems)
                }
            }
            when (val result = repository.fetchDriveItems()) {
                is ResultWrapper.Success -> {
                    val items = result.value.items
                        .map { it.copy(reactions = it.reactions ?: emptyList()) }
                    val updatedList = items.map { item ->
                        val reactionsDeferred = viewModelScope.async {
                            val res = repository.fetchReactions(item.id)
                            if (res is ResultWrapper.Success)
                                res.value.reactions.map { it.emoji } ?: emptyList()
                            else emptyList()
                        }
                        item.copy(reactions = reactionsDeferred.await())
                    }
                    val sortedList = updatedList.sortedByDescending { it.created_at }
                    DriveLocalCache.saveCachedDriveItems(context, sortedList)
                    DriveLocalCache.saveLastSync(context, getCurrentTimeIso())
                    _driveItems.value = sortedList
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore: ${result.code}", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore rete", true))
            }
        }
    }
    /** Load single item */
    fun loadSingleItem(itemId: Int) {
        viewModelScope.launch {
            val cachedItem = _driveItems.value.firstOrNull { it.id == itemId }
            if (cachedItem != null) {
                _singleItem.value = cachedItem
                return@launch
            }
            when (val result = repository.fetchDriveItems()) {
                is ResultWrapper.Success -> {
                    val items = result.value.items
                        .map { it.copy(reactions = it.reactions ?: emptyList()) }
                    val item = items.firstOrNull { it.id == itemId }
                    if (item != null) {
                        _singleItem.value = item
                    } else {
                        _uiEvents.emit(DriveEvent.ShowMessage("Item non trovato", true))
                    }
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore caricamento item", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore rete", true))
            }
        }
    }
    /** Sync incrementale dal server */
    fun syncDriveItems(context: Context) {
        viewModelScope.launch {
            val lastSync = DriveLocalCache.getLastSync(context) ?: return@launch
            when (val result = repository.fetchDriveChanges(lastSync)) {
                is ResultWrapper.Success -> {
                    DriveLocalCache.applyDriveChangesToCache(context, result.value.changes, result.value.lastSync)
                    val updated = DriveLocalCache.getCachedDriveItems(context)
                        .map { it.copy(reactions = it.reactions ?: emptyList()) }
                        .sortedByDescending { it.created_at }
                    _driveItems.value = updated
                }
                is ResultWrapper.GenericError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore: ${result.code}", true))
                is ResultWrapper.NetworkError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore rete", true))
            }
        }
    }
    /** Upload file + creazione item */
    fun addFileItem(context: Context, fileUri: Uri, fileName: String, fileSize: Long, mimeType: String) {
        viewModelScope.launch {
            if (fileSize > 3_000_000L) {
                _uiEvents.emit(DriveEvent.ShowMessage("⚠️ Attenzione: il file è grande (${fileSize / 1_000_000} MB), il caricamento potrebbe richiedere tempo"))
            }
            _uiEvents.emit(DriveEvent.ShowMessage("Caricamento file: $fileName ..."))
            val uploadResult = repository.uploadDiary(context, fileUri, fileName, mimeType) { uploadedBytes ->
                val progress = ((uploadedBytes.toDouble() / fileSize) * 100).toInt()
                UploadNotificationHelper.showUploadNotification(context, fileName, progress)
            }
            if (uploadResult is ResultWrapper.Success) {
                val url = uploadResult.value
                val type = when {
                    mimeType.startsWith("image") -> "image"
                    mimeType.startsWith("video") -> "video"
                    mimeType.startsWith("audio") -> "audio"
                    else -> "file"
                }
                val metadata = mapOf("filename" to fileName, "size" to fileSize, "mime" to mimeType)
                when (repository.createDriveItem(type, url, metadata)) {
                    is ResultWrapper.Success -> {
                        syncDriveItems(context)
                        _uiEvents.emit(DriveEvent.ShowMessage("Upload completato"))
                    }
                    else -> _uiEvents.emit(DriveEvent.ShowMessage("Errore creazione item", true))
                }
            } else {
                _uiEvents.emit(DriveEvent.ShowMessage("Errore upload file", true))
            }
            UploadNotificationHelper.cancelUploadNotification(context, fileName)
        }
    }
    /** Delete item */
    fun deleteItem(id: Int, context: Context) = viewModelScope.launch {
        val currentList = _driveItems.value
        val updatedList = currentList.filterNot { it.id == id }
        _driveItems.value = updatedList
        DriveLocalCache.saveCachedDriveItems(context, updatedList)
        when (repository.deleteDriveItem(id)) {
            is ResultWrapper.Success -> {
                _uiEvents.emit(DriveEvent.ShowMessage("Item eliminato!"))
            }
            else -> {
                _driveItems.value = currentList
                DriveLocalCache.saveCachedDriveItems(context, currentList)
                _uiEvents.emit(DriveEvent.ShowMessage("Errore nell'eliminazione", true))
            }
        }
    }
    /** Add reaction */
    fun addReaction(itemId: Int, emoji: String, context: Context) = viewModelScope.launch {
        when (repository.addReaction(itemId, emoji)) {
            is ResultWrapper.Success -> {
                val updated = _driveItems.value.map { item ->
                    if (item.id == itemId) item.copy(reactions = item.reactions + emoji) else item
                }
                _driveItems.value = updated
                DriveLocalCache.saveCachedDriveItems(context, updated)
            }
            is ResultWrapper.GenericError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore aggiunta reaction", true))
            is ResultWrapper.NetworkError -> _uiEvents.emit(DriveEvent.ShowMessage("Errore rete", true))
        }
    }
    /** Toggle preferito */
    fun onToggleFavorite(itemId: Int, context: Context) = viewModelScope.launch {
        val currentList = _driveItems.value.toMutableList()
        val idx = currentList.indexOfFirst { it.id == itemId }
        val item = if (idx != -1) currentList[idx] else _singleItem.value?.takeIf { it.id == itemId }
        if (item == null) return@launch

        val isCurrentlyFavorite = item.is_favorite == 1
        val updatedItem = item.copy(is_favorite = if (isCurrentlyFavorite) 0 else 1)

        if (idx != -1) {
            currentList[idx] = updatedItem
            _driveItems.value = currentList
            DriveLocalCache.saveCachedDriveItems(context, currentList)
        }
        if (_singleItem.value?.id == itemId) {
            _singleItem.value = updatedItem
        }
        val result = if (!isCurrentlyFavorite) {
            repository.addFavorite(itemId)
        } else {
            repository.removeFavorite(itemId)
        }
        if (result !is ResultWrapper.Success) {
            currentList[idx] = item
            _driveItems.value = currentList
            DriveLocalCache.saveCachedDriveItems(context, currentList)
            _uiEvents.emit(DriveEvent.ShowMessage("Errore aggiornamento preferito", true))
        }
    }
    private fun getCurrentTimeIso(): String = java.time.Instant.now().toString()
    sealed class DriveEvent {
        data class ShowMessage(val msg: String, val vibrate: Boolean = false) : DriveEvent()
    }
}