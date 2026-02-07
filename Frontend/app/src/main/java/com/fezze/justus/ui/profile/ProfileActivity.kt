package com.fezze.justus.ui.profile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.bumptech.glide.Glide
import com.fezze.justus.BuildConfig
import com.fezze.justus.R
import com.fezze.justus.ui.profile.change_password.ChangePasswordActivity
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.launch
import androidx.core.net.toUri
import java.io.File

class ProfileActivity : AppCompatActivity() {
    private val viewModel: ProfileViewModel by viewModels()
    private lateinit var ivUser: ImageView
    private lateinit var ivPartner: ImageView
    private lateinit var tvUsername: TextView
    private lateinit var tvBio: TextView
    private lateinit var tvPartnerUsername: TextView
    private val pickImageLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { openCropActivity(it) }
    }
    private val cropLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) {
            val croppedUri: Uri? = result.data?.getParcelableExtra(CropImageActivity.RESULT_URI, Uri::class.java)
            croppedUri?.let { handleProfileImage(it) }
        }
    }
    private lateinit var tvPartnerBio: TextView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_profile)
        ivUser = findViewById(R.id.imgProfile)
        ivPartner = findViewById(R.id.imgPartner)
        tvUsername = findViewById(R.id.tvProfileUsername)
        tvBio = findViewById(R.id.tvBio)
        tvPartnerUsername = findViewById(R.id.tvPartnerUsername)
        tvPartnerBio = findViewById(R.id.tvPartnerBio)
        observeViewModel()
        observeUiEvents()
        setupClicks()
        viewModel.loadProfile(this)
    }
    private fun observeViewModel() {
        viewModel.userProfileState.observe(this) { res ->
            if (res is ResultWrapper.Success) {
                tvUsername.text = res.value.username
                tvBio.text = res.value.bio ?: ""
                if (viewModel.localProfileImage.value == null) {
                    loadProfileImage(res.value.profile_pic_url, ivUser)
                }
            }
        }
        viewModel.localProfileImage.observe(this) { uri ->
            uri?.let {
                Glide.with(this)
                    .load(it)
                    .circleCrop()
                    .into(ivUser)
            }
        }
        viewModel.partnerProfileState.observe(this) { res ->
            if (res is ResultWrapper.Success) {
                tvPartnerUsername.text = res.value.username
                tvPartnerBio.text = res.value.bio ?: ""
                loadProfileImage(res.value.profile_pic_url, ivPartner)
            }
        }
        viewModel.updateUserBioState.observe(this) { res ->
            when (res) {
                is ResultWrapper.Success -> viewModel.loadProfile(this)
                is ResultWrapper.GenericError -> showError(res.message ?: "Errore aggiornamento bio")
                is ResultWrapper.NetworkError -> showError("Errore di rete")
            }
        }
    }
    private fun observeUiEvents() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    when (event) {
                        is ProfileViewModel.UiEvent.ShowMessage -> {
                            Toast.makeText(this@ProfileActivity, event.message, Toast.LENGTH_SHORT).show()
                            if (event.vibrate) VibrationUtils.vibrateError(this@ProfileActivity)
                        }
                    }
                }
            }
        }
    }
    private fun setupClicks() {
        findViewById<View>(R.id.btnEditBio).setOnClickListener { showEditBioDialog() }
        findViewById<View>(R.id.btnChangePassword).setOnClickListener {
            startActivity(Intent(this, ChangePasswordActivity::class.java))
        }
        findViewById<View>(R.id.btnChangeProfilePic).setOnClickListener { pickProfileImage() }
    }
    private fun loadProfileImage(url: String?, imageView: ImageView) {
        if (!url.isNullOrEmpty()) {
            if (url.startsWith("content://") || url.startsWith("file://")) {
                Glide.with(this)
                    .load(url.toUri())
                    .placeholder(R.drawable.ic_profile_default)
                    .error(R.drawable.ic_profile_default)
                    .circleCrop()
                    .into(imageView)
            } else {
                val profilePicVersion = ProfileLocalCache.getProfilePicVersion(this)
                val fullUrl = buildFullUrl(url)
                val cacheBustedUrl = "$fullUrl?v=$profilePicVersion"
                Glide.with(this)
                    .load(cacheBustedUrl)
                    .placeholder(R.drawable.ic_profile_default)
                    .error(R.drawable.ic_profile_default)
                    .circleCrop()
                    .into(imageView)
            }
        } else {
            imageView.setImageResource(R.drawable.ic_profile_default)
        }
    }
    private fun showEditBioDialog() {
        val input = EditText(this)
        AlertDialog.Builder(this)
            .setTitle("Modifica bio")
            .setView(input)
            .setPositiveButton("Salva") { _, _ ->
                viewModel.updateBio(this, input.text.toString())
            }
            .setNegativeButton("Annulla", null)
            .show()
    }
    private fun pickProfileImage() {
        pickImageLauncher.launch("image/*")
    }
    private fun openCropActivity(uri: Uri) {
        val cropIntent = Intent(this, CropImageActivity::class.java)
        cropIntent.putExtra(CropImageActivity.EXTRA_IMAGE_URI, uri)
        cropLauncher.launch(cropIntent)
    }
    private fun copyUriToCache(uri: Uri): Uri {
        val file = File(cacheDir, "profile_${System.currentTimeMillis()}.jpg")
        contentResolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return file.toUri()
    }
    private fun handleProfileImage(fileUri: Uri) {
        val contentResolver = contentResolver
        var fileName = "profile_pic.jpg"
        val mimeType = contentResolver.getType(fileUri) ?: "image/jpeg"
        var fileSize = 0L
        contentResolver.query(fileUri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIndex != -1) fileName = cursor.getString(nameIndex) ?: fileName
                if (sizeIndex != -1) fileSize = cursor.getLong(sizeIndex)
            }
        }
        if (fileSize == 0L) {
            contentResolver.openInputStream(fileUri)?.use { fileSize = it.available().toLong() }
        }
        val safeUri = copyUriToCache(fileUri)
        viewModel.setLocalProfileImage(safeUri)
        viewModel.uploadProfilePhoto(this, safeUri, fileName, mimeType, fileSize)
    }
    private fun buildFullUrl(path: String): String {
        return if (path.startsWith("http")) path else BuildConfig.BASE_URL + path.removePrefix("/")
    }
    private fun showError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        VibrationUtils.vibrateError(this)
    }
}