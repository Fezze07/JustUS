package com.fezze.justus.ui.mood

import android.app.AlertDialog
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.fezze.justus.BaseActivity
import com.fezze.justus.databinding.ActivityMoodBinding
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.launch
class MoodActivity : BaseActivity() {
    private lateinit var binding: ActivityMoodBinding
    private lateinit var viewModel: MoodViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMoodBinding.inflate(layoutInflater)
        setContentView(binding.root)
        viewModel = ViewModelProvider(this)[MoodViewModel::class.java]
        viewModel.loadCache(this)
        val emojiButtons = listOf(binding.btnCool, binding.btnLaugh, binding.btnLove, binding.btnSad)
        emojiButtons.forEachIndexed { index, button ->
            button.text = viewModel.recentEmojis.value.getOrNull(index) ?: "😐"
            button.setOnClickListener { onEmojiClick(it) }
        }
        binding.btnAddEmoji.setOnClickListener { onAddCustomEmojiClick() }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.userMood.collect { emoji ->
                    binding.tvUserMood.text = emoji ?: "😐"
                }
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.recentEmojis.collect { emojis ->
                    emojiButtons.forEachIndexed { index, button ->
                        button.text = emojis.getOrNull(index) ?: "😐"
                    }
                }
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    when (event) {
                        is MoodViewModel.UiEvent.ShowMessage -> {
                            if (event.vibrate) {
                                VibrationUtils.vibrateError(this@MoodActivity)
                            }
                            Toast.makeText(this@MoodActivity, event.message, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
        viewModel.fetchMyMood(this)
        viewModel.fetchRecentEmojis(this)
    }
    private fun onEmojiClick(view: View) {
        val emoji = (view as Button).text.toString()
        partnerId?.let {
            viewModel.updateMood(partnerId = it, emoji = emoji, context = this)
        }
    }
    private fun onAddCustomEmojiClick() {
        val editText = EditText(this).apply {
            hint = "Inserisci un'emoji"
            textSize = 24f
        }
        AlertDialog.Builder(this)
            .setTitle("Emoji Custom")
            .setView(editText)
            .setPositiveButton("Aggiungi") { _, _ ->
                val emoji = editText.text.toString().trim()
                if (emoji.isNotEmpty() && emoji.isOnlyEmoji()) {
                    partnerId?.let {
                        viewModel.updateMood(partnerId = it, emoji = emoji, context = this)
                    }
                } else {
                    VibrationUtils.vibrateError(this)
                    Toast.makeText(this, "Inserisci solo un’emoji valida", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }
    private fun String.isOnlyEmoji(): Boolean {
        if (isEmpty()) return false
        val emojiRegex = Regex("[\\p{So}\\p{Sk}\\u200D\\uFE0F]+")
        return matches(emojiRegex)
    }
}