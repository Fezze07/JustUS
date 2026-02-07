package com.fezze.justus.ui.drive.holders
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.fezze.justus.R
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.ui.drive.utils.buildFullUrl
import com.fezze.justus.ui.drive.utils.loadAndCacheThumbnail
import io.getstream.photoview.PhotoView
class DriveImageViewHolder(
    itemView: View,
    onDelete: ((Int) -> Unit)? = null,
    onAddReaction: ((Int, String) -> Unit)? = null,
    onToggleFavorite: ((Int) -> Unit)? = null
) : DriveBaseViewHolder(itemView, onDelete, onAddReaction, onToggleFavorite) {
    private val imageView: PhotoView = itemView.findViewById(R.id.ivImage)

    override fun bind(item: DriveItem, onEdit: ((Int, String) -> Unit)?) {
        super.bind(item, onEdit)
        imageView.visibility = View.VISIBLE
        val url = buildFullUrl(item.content)
        loadAndCacheThumbnail(context = itemView.context, thumb = imageView, url = url, itemId = item.id, placeholder = R.drawable.placeholder)
    }
    companion object {
        fun create(inflater: LayoutInflater, parent: ViewGroup,
            onDelete: ((Int) -> Unit)? = null,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveImageViewHolder {
            val view = inflater.inflate(R.layout.item_drive, parent, false)
            return DriveImageViewHolder(view, onDelete, onAddReaction, onToggleFavorite)
        }
        fun createForFavorites(inflater: LayoutInflater, parent: ViewGroup,
            onAddReaction: ((Int, String) -> Unit)? = null, onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveImageViewHolder {
            val view = inflater.inflate(R.layout.item_favorites, parent, false)
            return DriveImageViewHolder(view, null, onAddReaction, onToggleFavorite)
        }
    }
}