package com.fezze.justus.ui.favorites

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.fezze.justus.ui.drive.DriveAdapterSingleItem
import com.fezze.justus.ui.drive.holders.*

class FavoritesAdapter(onAddReaction: (Int, String) -> Unit, onToggleFavorite: (Int) -> Unit) : DriveAdapterSingleItem(
    onDelete = null, onAddReaction = onAddReaction, onToggleFavorite = onToggleFavorite, layoutRes = null ) {
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_IMAGE -> DriveImageViewHolder.createForFavorites(inflater, parent, onAddReaction, onToggleFavorite)
            TYPE_VIDEO -> DriveVideoViewHolder.createForFavorites(inflater, parent, onAddReaction, onToggleFavorite)
            TYPE_AUDIO -> DriveAudioViewHolder.createForFavorites(inflater, parent, onAddReaction, onToggleFavorite)
            else -> DriveUnknownViewHolder.createForFavorites(inflater, parent, onAddReaction, onToggleFavorite)
        }
    }
}