package com.fezze.justus.ui.favorites

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fezze.justus.ui.drive.DriveLocalCache
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.data.repository.ApiRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class FavoritesViewModel(private val repository: ApiRepository = ApiRepository()) : ViewModel() {
    private val _favoriteItems = MutableStateFlow<List<DriveItem>>(emptyList())
    val favoriteItems: StateFlow<List<DriveItem>> = _favoriteItems
    fun loadFavorites(context: Context) {
        viewModelScope.launch {
            val allItems = DriveLocalCache.getCachedDriveItems(context)
            val favorites = allItems.filter { it.is_favorite == 1 }
            _favoriteItems.value = favorites
        }
    }
    fun removeFavorite(itemId: Int, context: Context) {
        viewModelScope.launch {
            val currentList = _favoriteItems.value.toMutableList()
            val idx = currentList.indexOfFirst { it.id == itemId }
            if (idx == -1) return@launch
            val item = currentList[idx]
            val updatedItem = item.copy(is_favorite = 0)
            currentList.removeAt(idx)
            _favoriteItems.value = currentList
            val allItems = DriveLocalCache.getCachedDriveItems(context).toMutableList()
            val allIdx = allItems.indexOfFirst { it.id == itemId }
            if (allIdx != -1) {
                allItems[allIdx] = updatedItem
                DriveLocalCache.saveCachedDriveItems(context, allItems)
            }
            repository.removeFavorite(itemId)
        }
    }
    fun addReaction(itemId: Int, emoji: String, context: Context) {
        viewModelScope.launch {
            val currentList = _favoriteItems.value.toMutableList()
            val idx = currentList.indexOfFirst { it.id == itemId }
            if (idx == -1) return@launch
            val item = currentList[idx]
            val updatedReactions = item.reactions.toMutableList().apply { add(emoji) }
            val updatedItem = item.copy(reactions = updatedReactions)
            currentList[idx] = updatedItem
            _favoriteItems.value = currentList
            val allItems = DriveLocalCache.getCachedDriveItems(context).toMutableList()
            val allIdx = allItems.indexOfFirst { it.id == itemId }
            if (allIdx != -1) {
                allItems[allIdx] = updatedItem
                DriveLocalCache.saveCachedDriveItems(context, allItems)
            }
            repository.addReaction(itemId, emoji)
        }
    }
}
