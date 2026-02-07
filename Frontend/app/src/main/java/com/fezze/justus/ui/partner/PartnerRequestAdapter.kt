package com.fezze.justus.ui.partner

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.fezze.justus.R
import com.fezze.justus.data.models.User
import com.fezze.justus.databinding.PartnerRequestBinding
class PartnerRequestAdapter(
    private val onAccept: ((Int) -> Unit)? = null,
    private val onReject: ((Int) -> Unit)? = null,
    private val onClick: ((User) -> Unit)? = null
) : ListAdapter<User, PartnerRequestAdapter.VH>(DIFF) {
    companion object {
        val DIFF = object : DiffUtil.ItemCallback<User>() {
            override fun areItemsTheSame(oldItem: User, newItem: User) = oldItem.id == newItem.id
            override fun areContentsTheSame(oldItem: User, newItem: User) = oldItem == newItem
        }
    }
    inner class VH(val binding: PartnerRequestBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(user: User) {
            binding.tvUsername.text = binding.root.context.getString(R.string.user_code_text, user.username, user.code)
            val profileUrl = user.profile_pic_url
            if (!profileUrl.isNullOrBlank()) {
                Glide.with(binding.ivProfile.context)
                    .load(profileUrl)
                    .placeholder(R.drawable.ic_profile) // placeholder
                    .error(R.drawable.ic_profile)
                    .circleCrop()
                    .into(binding.ivProfile)
            } else {
                binding.ivProfile.setImageResource(R.drawable.ic_profile)
            }
            if (onAccept != null && onReject != null) {
                binding.btnAccept.visibility = View.VISIBLE
                binding.btnReject.visibility = View.VISIBLE
                binding.btnAccept.setOnClickListener { onAccept.invoke(user.id) }
                binding.btnReject.setOnClickListener { onReject.invoke(user.id) }
            } else {
                binding.btnAccept.visibility = View.GONE
                binding.btnReject.visibility = View.GONE
            }
            onClick?.let { click ->
                binding.root.setOnClickListener { click.invoke(user) }
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = PartnerRequestBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(binding)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(getItem(position))
    }
}