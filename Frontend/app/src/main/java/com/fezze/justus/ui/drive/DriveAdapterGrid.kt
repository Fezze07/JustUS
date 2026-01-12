package com.fezze.justus.ui.drive
import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.fezze.justus.R
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.ui.drive.utils.*

class DriveAdapterGrid(private val onClick: (DriveItem) -> Unit) :
    ListAdapter<Any, RecyclerView.ViewHolder>(DriveDiffCallback()) {
    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_ITEM = 1
    }
    fun submitGrouped(grouped: Map<String, List<DriveItem>>, context: Context) {
        val list = mutableListOf<Any>()
        grouped.forEach { (header, items) ->
            list.add(header)
            list.addAll(items)
            items.forEach { item ->
                val url = buildFullUrl(item.content)
                prefetchThumbnail(context, url, item.id, item.type == "video")
            }
        }
        submitList(list)
    }
    override fun getItemViewType(position: Int): Int {
        return if (getItem(position) is String) TYPE_HEADER else TYPE_ITEM
    }
    fun isHeader(position: Int) = getItem(position) is String
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return if (viewType == TYPE_HEADER) {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_drive_header, parent, false)
            HeaderVH(view)
        } else {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_drive_grid, parent, false)
            GridVH(view)
        }
    }
    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val currentItem = getItem(position)
        if (holder is HeaderVH && currentItem is String) {
            holder.bind(currentItem)
        } else if (holder is GridVH && currentItem is DriveItem) {
            holder.bind(currentItem)
        }
    }
    inner class GridVH(view: View) : RecyclerView.ViewHolder(view) {
        private val thumb: ImageView = view.findViewById(R.id.ivThumb)
        private val icon: ImageView = view.findViewById(R.id.ivType)
        fun bind(item: DriveItem) {
            val url = buildFullUrl(item.content)
            when (item.type) {
                "image" -> loadAndCacheThumbnail(itemView.context, thumb, url, item.id, R.drawable.placeholder)
                "video" -> loadAndCacheThumbnail(itemView.context, thumb, url, item.id, R.drawable.placeholder, true)
                "audio" -> Glide.with(itemView.context).load(R.drawable.ic_audio).into(thumb)
                else -> Glide.with(itemView.context).load(R.drawable.ic_file_placeholder).into(thumb)
            }
            icon.setImageResource(
                when (item.type) {
                    "video" -> R.drawable.ic_video
                    "audio" -> R.drawable.ic_audio
                    else -> 0
                }
            )
            icon.visibility = if (item.type == "image") View.GONE else View.VISIBLE
            itemView.setOnClickListener { onClick(item) }
        }
    }
    class HeaderVH(view: View) : RecyclerView.ViewHolder(view) {
        private val headerText: TextView = view.findViewById(R.id.tvHeader)
        fun bind(header: String) { headerText.text = header }
    }
    class DriveDiffCallback : androidx.recyclerview.widget.DiffUtil.ItemCallback<Any>() {
        override fun areItemsTheSame(oldItem: Any, newItem: Any): Boolean {
            return when (oldItem) {
                is DriveItem if newItem is DriveItem -> oldItem.id == newItem.id
                is String if newItem is String -> oldItem == newItem
                else -> false
            }
        }
        override fun areContentsTheSame(oldItem: Any, newItem: Any): Boolean {
            return oldItem == newItem
        }
    }
}