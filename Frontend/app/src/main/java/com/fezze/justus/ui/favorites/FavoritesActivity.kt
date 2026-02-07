package com.fezze.justus.ui.favorites

import android.os.Bundle
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.fezze.justus.databinding.ActivityFavoritesBinding
import com.fezze.justus.ui.drive.DriveAdapterSingleItem
import kotlinx.coroutines.launch
class FavoritesActivity : AppCompatActivity() {
    private lateinit var binding: ActivityFavoritesBinding
    private val viewModel: FavoritesViewModel by viewModels()
    private lateinit var adapter: DriveAdapterSingleItem
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityFavoritesBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setupRecyclerView()
        observeViewModel()
        viewModel.loadFavorites(this)
    }

    private fun setupRecyclerView() {
        adapter = FavoritesAdapter(
            onAddReaction = { id, emoji -> viewModel.addReaction(id, emoji, this) },
            onToggleFavorite = { id -> viewModel.removeFavorite(id, this) }
        )
        binding.recyclerViewFavorites.adapter = adapter
        binding.recyclerViewFavorites.layoutManager = LinearLayoutManager(this)
    }
    private fun observeViewModel() {
        lifecycleScope.launch {
            viewModel.favoriteItems.collect { items ->
                adapter.submitList(items)
            }
        }
    }
}