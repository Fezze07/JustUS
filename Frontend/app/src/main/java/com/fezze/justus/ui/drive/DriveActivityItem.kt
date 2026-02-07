package com.fezze.justus.ui.drive

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.fezze.justus.databinding.ActivityDriveItemBinding
import kotlinx.coroutines.launch

class DriveActivityItem : AppCompatActivity() {
    private lateinit var binding: ActivityDriveItemBinding
    private val viewModel: DriveViewModel by viewModels()
    private lateinit var adapter: DriveAdapterSingleItem
    private val itemId: Int by lazy { intent.getIntExtra("ITEM_ID", -1) }
    companion object {
        fun start(context: Context, itemId: Int) {
            val intent = Intent(context, DriveActivityItem::class.java)
            intent.putExtra("ITEM_ID", itemId)
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (itemId == -1) {
            Toast.makeText(this, "Item non valido 💀", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        binding = ActivityDriveItemBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setupRecycler()
        observeItem()
        viewModel.loadSingleItem(itemId)
    }
    private fun setupRecycler() {
        adapter = DriveAdapterSingleItem(
            onDelete = { id -> viewModel.deleteItem(id, this); finish() },
            onAddReaction = { id, emoji -> viewModel.addReaction(id, emoji, this) },
            onToggleFavorite = { id -> viewModel.onToggleFavorite(id, this) }
        )
        binding.recyclerView.apply {
            adapter = this@DriveActivityItem.adapter
            layoutManager = LinearLayoutManager(this@DriveActivityItem)
        }
    }
    private fun observeItem() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.singleItem.collect { item ->
                    item?.let {
                        adapter.submitList(listOf(it))
                    }
                }
            }
        }
    }
}
