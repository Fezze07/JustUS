package com.fezze.justus.ui.game

import android.os.Bundle
import android.widget.Toast
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.fezze.justus.BaseActivity
import com.fezze.justus.R
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.databinding.ActivityGameBinding
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class GameActivity : BaseActivity() {
    private lateinit var binding: ActivityGameBinding
    private lateinit var viewModel: GameViewModel
    private lateinit var currentUser: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityGameBinding.inflate(layoutInflater)
        setContentView(binding.root)
        currentUser = SharedPrefsManager.getUsername(this) ?: return
        val repo = ApiRepository()
        val notificationVm = NotificationViewModel()
        viewModel = GameViewModel(repo, notificationVm)
        setupClicks()
        observeViewModel()
        partnerId = SharedPrefsManager.getPartnerId(this)
        viewModel.initGame(this)
    }
    private fun setupClicks() {
        binding.btnOptionA.setOnClickListener {
            partnerId?.let { viewModel.submitAnswer("A", currentUser, it, this) }
        }
        binding.btnOptionB.setOnClickListener {
            partnerId?.let { viewModel.submitAnswer("B", currentUser, it, this) }
        }
    }
    private fun observeViewModel() {
        lifecycleScope.launch {
            viewModel.currentQuestion.collectLatest { q ->
                q?.let { question ->
                    binding.btnOptionA.text = question.optionA
                    binding.btnOptionB.text = question.optionB
                    if (question.status == "waiting") {
                        binding.tvQuestion.text =
                            question.message ?: "Aspetta che il partner risponda"
                        binding.btnOptionA.isEnabled = false
                        binding.btnOptionB.isEnabled = false
                        binding.btnRemindPartner.visibility = android.view.View.VISIBLE
                    } else {
                        binding.tvQuestion.text = question.question
                        binding.btnOptionA.isEnabled = true
                        binding.btnOptionB.isEnabled = true
                        binding.btnRemindPartner.visibility = android.view.View.GONE
                    }
                }
            }
        }
        binding.btnRemindPartner.setOnClickListener {
            partnerId?.let { viewModel.sendReminderNotification(currentUser, it) }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    when (event) {
                        is GameViewModel.UiEvent.ShowMessage -> {
                            if (event.vibrate) VibrationUtils.vibrateError(this@GameActivity)
                            Toast.makeText(this@GameActivity, event.message, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
        lifecycleScope.launch {
            viewModel.gameStats.collectLatest { stats ->
                binding.tvStats.text = getString(R.string.game_stats, stats)
            }
        }
    }
}