package com.fezze.justus.ui.drive.holders
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.fezze.justus.R
import com.fezze.justus.data.models.DriveItem
class DriveUnknownViewHolder( itemView: View,
    onDelete: ((Int) -> Unit)? = null,
    onAddReaction: ((Int, String) -> Unit)? = null,
    onToggleFavorite: ((Int) -> Unit)? = null
) : DriveBaseViewHolder(itemView, onDelete, onAddReaction, onToggleFavorite) {
    private val tvText: TextView = itemView.findViewById(R.id.tvText)
    override fun bind(item: DriveItem, onEdit: ((Int, String) -> Unit)?) {
        super.bind(item, onEdit)
        tvText.visibility = View.VISIBLE
        tvText.text = itemView.context.getString(R.string.drive_unknown_file)
    }
    companion object {
        fun create(inflater: LayoutInflater, parent: ViewGroup,
            onDelete: ((Int) -> Unit)? = null,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveUnknownViewHolder {
            val view = inflater.inflate(R.layout.item_drive, parent, false)
            return DriveUnknownViewHolder(view, onDelete, onAddReaction, onToggleFavorite)
        }
        fun createForFavorites(inflater: LayoutInflater, parent: ViewGroup,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveUnknownViewHolder {
            val view = inflater.inflate(R.layout.item_favorites, parent, false)
            return DriveUnknownViewHolder(view, null, onAddReaction, onToggleFavorite)
        }
    }
}
