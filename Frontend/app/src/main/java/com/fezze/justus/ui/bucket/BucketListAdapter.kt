package com.fezze.justus.ui.bucket

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fezze.justus.data.models.BucketItem
import com.fezze.justus.databinding.ItemBucketBinding
class BucketListAdapter(
    private val onToggle: (BucketItem) -> Unit,
    private val onDelete: (BucketItem) -> Unit
) : ListAdapter<BucketItem, BucketListAdapter.VH>(Diff) {
    object Diff : DiffUtil.ItemCallback<BucketItem>() {
        override fun areItemsTheSame(oldItem: BucketItem, newItem: BucketItem) = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: BucketItem, newItem: BucketItem) = oldItem == newItem
    }
    inner class VH(private val binding: ItemBucketBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: BucketItem) {
            binding.textItem.text = item.text
            binding.checkboxDone.isChecked = item.done == 1
            binding.checkboxDone.setOnClickListener { onToggle(item) }
            binding.btnDelete.setOnClickListener { onDelete(item) }
        }
    }
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemBucketBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(binding)
    }
    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(getItem(position))
    }
}
