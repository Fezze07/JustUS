package com.fezze.justus.ui.homepage
import android.content.Intent
import android.os.Bundle
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.widget.PopupWindow
import android.widget.Toast
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.fezze.justus.BaseActivity
import com.fezze.justus.R
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.ui.bucket.BucketListActivity
import com.fezze.justus.ui.drive.DriveActivity
import com.fezze.justus.ui.game.GameActivity
import com.fezze.justus.ui.mood.MoodActivity
import kotlinx.coroutines.launch
import com.fezze.justus.utils.VersionUtils
import com.fezze.justus.databinding.ActivityHomepageBinding
import com.fezze.justus.ui.favorites.FavoritesActivity
import com.fezze.justus.ui.mood.MoodViewModel
import com.fezze.justus.ui.profile.ProfileActivity
import com.fezze.justus.utils.VibrationUtils
import java.io.File
class HomepageActivity : BaseActivity() {
    private lateinit var binding: ActivityHomepageBinding
    private val viewModel: HomepageViewModel by viewModels()
    private val moodViewModel: MoodViewModel by viewModels()
    private val notificationVm by lazy { NotificationViewModel() }
    private val currentUser by lazy { SharedPrefsManager.getUsername(this) ?: "" }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // ----- Layout -----
        binding = ActivityHomepageBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setLoading(true)
        observeUiEvents()
    }
    override fun onPartnerReady() {
        setLoading(false)
        setupButtons()
        partnerId = SharedPrefsManager.getPartnerId(this)
        val partnerName = SharedPrefsManager.getPartnerUsername(this) ?: "tuo partner"
        binding.tvPartnerLabel.text = getString(R.string.partner_mood_label, partnerName)
        // ----- Mood -----
        moodViewModel.loadPartnerMoodFromCache(this)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                moodViewModel.partnerMood.collect { emoji ->
                    binding.tvPartnerMood.text = emoji ?: "😐"
                }
            }
        }
        // ----- Miss you -----
        viewModel.initTotalMissYou(this)
        lifecycleScope.launch {
            viewModel.totalMissYou.collect { total ->
                binding.tvTotal.text = getString(R.string.total_miss_you_count, total)
            }
        }
        // ----- Fetch -----
        moodViewModel.fetchPartnerMood(this)
        viewModel.fetchTotalMissYou(this)
    }
    private fun setupButtons() {
        binding.missYouBtn.setOnClickListener {
            it.isEnabled = false
            viewModel.sendMissYou(this)
            partnerId?.let { receiverId ->
                notificationVm.sendNotification(
                    type = "missyou",
                    receiverId = receiverId,
                    title = "Mi manchi 💗",
                    body = "$currentUser vuole stare con te!"
                )
            }
            it.isEnabled = true
        }
        binding.moodBtn.setOnClickListener { startActivity(Intent(this, MoodActivity::class.java)) }
        binding.bucketBtn.setOnClickListener { startActivity(Intent(this, BucketListActivity::class.java)) }
        binding.gameBtn.setOnClickListener { startActivity(Intent(this, GameActivity::class.java)) }
        binding.driveBtn.setOnClickListener { startActivity(Intent(this, DriveActivity::class.java)) }
        binding.btnSettings.setOnClickListener { showSettingsPopup(it) }
    }
    private fun observeUiEvents() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    when (event) {
                        is HomepageViewModel.UiEvent.ShowMessage -> {
                            if (event.vibrate) {
                                VibrationUtils.vibrateError(this@HomepageActivity)
                            }
                            Toast.makeText(this@HomepageActivity, event.message, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }
    private fun showSettingsPopup(anchor: View) {
        val popupView = layoutInflater.inflate(R.layout.popup_settings, anchor.parent as ViewGroup, false)
        val popupWindow = PopupWindow(popupView, ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, true)
        popupWindow.elevation = 20f
        popupWindow.isOutsideTouchable = true
        popupView.findViewById<View>(R.id.optionProfile).setOnClickListener {
            startActivity(Intent(this, ProfileActivity::class.java))
            popupWindow.dismiss()
        }
        popupView.findViewById<View>(R.id.optionPartner).setOnClickListener {
            popupWindow.dismiss()
            val partnerId = SharedPrefsManager.getPartnerId(this)
            if (partnerId != null) {
                Toast.makeText(this, "Non puoi avere più partner malandrino!", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Partner non trovato", Toast.LENGTH_SHORT).show()
            }
        }
        popupView.findViewById<View>(R.id.optionFavorites).setOnClickListener {
            startActivity(Intent(this, FavoritesActivity::class.java))
            popupWindow.dismiss()
        }
        popupWindow.showAsDropDown(anchor, -250, 20)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 12345) {
            val apkFile = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "app-update.apk")
            if (apkFile.exists()) {
                VersionUtils.installApkWithPermission(this, apkFile, 12345)
            }
        }
    }
    private fun setUiEnabled(enabled: Boolean) {
        binding.missYouBtn.isEnabled = enabled
        binding.moodBtn.isEnabled = enabled
        binding.bucketBtn.isEnabled = enabled
        binding.gameBtn.isEnabled = enabled
        binding.driveBtn.isEnabled = enabled
        binding.btnSettings.isEnabled = enabled
        binding.root.alpha = if (enabled) 1f else 0.6f
    }
    private fun setLoading(isLoading: Boolean) {
        binding.loadingOverlay.visibility = if (isLoading) View.VISIBLE else View.GONE
        binding.root.isClickable = isLoading
        setUiEnabled(!isLoading)
    }
}