package com.fezze.justus.ui.bucket

import android.os.Bundle
import android.widget.Toast
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.fezze.justus.BaseActivity
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.databinding.ActivityBucketListBinding
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
class BucketListActivity : BaseActivity() {
    private lateinit var binding: ActivityBucketListBinding
    private lateinit var viewModel: BucketListViewModel
    private lateinit var adapter: BucketListAdapter
    private lateinit var currentUser: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBucketListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        currentUser = SharedPrefsManager.getUsername(this) ?: return
        viewModel = ViewModelProvider(this)[BucketListViewModel::class.java]
        setupRecycler()
        setupClicks()
        observe()
        viewModel.initBucket(this)
    }
    private fun setupRecycler() {
        adapter = BucketListAdapter(
            onToggle = { viewModel.toggleDone(it.id, this) },
            onDelete = { viewModel.deleteItem(it.id, this) }
        )
        binding.recyclerBucket.layoutManager = LinearLayoutManager(this)
        binding.recyclerBucket.adapter = adapter
    }
    private fun setupClicks() {
        binding.btnAdd.setOnClickListener {
            val text = binding.inputText.text.toString().trim()
            if (text.isNotEmpty()) {
                binding.inputText.text.clear()
                partnerId?.let { viewModel.addItem(text, currentUser, it, this) }
            }
        }
    }
    private fun observe() {
        lifecycleScope.launch {
            viewModel.items.collectLatest { list ->
                adapter.submitList(list)
                binding.emptyGroup.alpha = if (list.isEmpty()) 1f else 0f
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    when (event) {
                        is BucketListViewModel.UiEvent.ShowMessage -> {
                            if (event.vibrate) VibrationUtils.vibrateError(this@BucketListActivity)
                            Toast.makeText(this@BucketListActivity, event.message, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }
}