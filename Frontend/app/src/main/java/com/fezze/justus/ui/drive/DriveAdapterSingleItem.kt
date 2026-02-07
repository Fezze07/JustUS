package com.fezze.justus.ui.drive

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.ui.drive.holders.*

open class DriveAdapterSingleItem(
    private val onDelete: ((Int) -> Unit)?,
    val onAddReaction: ((Int, String) -> Unit)?,
    val onToggleFavorite: ((Int) -> Unit)?,
    private val layoutRes: Int? = null
) : ListAdapter<DriveItem, RecyclerView.ViewHolder>(DiffCallback()) {
    companion object {
        const val TYPE_IMAGE = 1
        const val TYPE_VIDEO = 2
        const val TYPE_AUDIO = 3
        const val TYPE_DEFAULT = 99
    }

    override fun getItemViewType(position: Int): Int {
        if (layoutRes != null) return TYPE_DEFAULT
        return when (getItem(position).type) {
            "image" -> TYPE_IMAGE
            "video" -> TYPE_VIDEO
            "audio" -> TYPE_AUDIO
            else -> TYPE_DEFAULT
        }
    }
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        layoutRes?.let {
            val view = inflater.inflate(it, parent, false)
            return object : DriveBaseViewHolder(view, onDelete, onAddReaction, onToggleFavorite) {}
        }
        return when (viewType) {
            TYPE_IMAGE -> DriveImageViewHolder.create(inflater, parent, onDelete, onAddReaction, onToggleFavorite)
            TYPE_VIDEO -> DriveVideoViewHolder.create(inflater, parent, onDelete, onAddReaction, onToggleFavorite)
            TYPE_AUDIO -> DriveAudioViewHolder.create(inflater, parent, onDelete, onAddReaction, onToggleFavorite)
            else -> DriveUnknownViewHolder.create(inflater, parent, onDelete, onAddReaction, onToggleFavorite)
        }
    }
    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val item = getItem(position)
        (holder as? DriveBaseViewHolder)?.bind(item)
    }
    class DiffCallback : DiffUtil.ItemCallback<DriveItem>() {
        override fun areItemsTheSame(oldItem: DriveItem, newItem: DriveItem) = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: DriveItem, newItem: DriveItem) = oldItem == newItem
    }
}
