package com.fezze.justus.ui.drive

import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.widget.SeekBar
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.data.notification.NotificationViewModel
import com.fezze.justus.databinding.ActivityDriveBinding
import com.fezze.justus.ui.drive.utils.groupDriveItemsByZoom
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.launch

class DriveActivity : AppCompatActivity() {
    private lateinit var binding: ActivityDriveBinding
    private val viewModel: DriveViewModel by viewModels()
    private val notificationViewModel: NotificationViewModel by viewModels()
    private lateinit var adapter: DriveAdapterGrid
    private lateinit var gridLayoutManager: GridLayoutManager
    private var spanCount = 3
    private val minSpan = 1
    private val maxSpan = 6
    private var currentScaleFactor = 1f
    private var cachedItems: List<DriveItem> = emptyList()
    private lateinit var currentUser: String
    private var partnerId: Int? = null
    private val pickFileLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri?.let { handlePickedFile(it) }
    }
    private val scaleGestureDetector by lazy {
        ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val factor = detector.scaleFactor
                if (factor > 1.05f && spanCount > minSpan) {
                    setGridZoom((spanCount - 1).coerceIn(minSpan, maxSpan))
                } else if (factor < 0.95f && spanCount < maxSpan) {
                    setGridZoom((spanCount + 1).coerceIn(minSpan, maxSpan))
                }
                return true
            }
        })
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityDriveBinding.inflate(layoutInflater)
        setContentView(binding.root)
        currentUser = SharedPrefsManager.getUsername(this) ?: run { finish(); return }
        partnerId = SharedPrefsManager.getPartnerId(this) ?: run {
            Toast.makeText(this, "Nessun partner collegato", Toast.LENGTH_SHORT).show()
            finish(); return
        }
        setupRecyclerView()
        setupButtons()
        observeViewModel()
        viewModel.initialLoad(this)
        // Zoom
        binding.zoomSeekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                val newSpan = (progress + 1).coerceIn(minSpan, maxSpan)
                if (newSpan != spanCount) {
                    setGridZoom(newSpan)
                    currentScaleFactor = 1f
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
    }
    private fun setupRecyclerView() {
        adapter = DriveAdapterGrid { item ->
            DriveActivityItem.start(this, item.id)
        }
        gridLayoutManager = GridLayoutManager(this, spanCount)
        gridLayoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int): Int {
                return if (adapter.isHeader(position)) spanCount else 1
            }
        }
        binding.recyclerViewDrive.apply {
            adapter = this@DriveActivity.adapter
            layoutManager = gridLayoutManager
            setHasFixedSize(true)
            setOnTouchListener { v, event ->
                scaleGestureDetector.onTouchEvent(event)
                if (event.action == MotionEvent.ACTION_UP) {
                    v.performClick()
                }
                false
            }
        }
    }
    private fun setGridZoom(newSpanCount: Int) {
        spanCount = newSpanCount
        gridLayoutManager.spanCount = spanCount
        binding.zoomSeekBar.progress = spanCount - 1
        viewModel.driveItems.value.let { items ->
            val grouped = groupDriveItemsByZoom(items, spanCount)
            adapter.submitGrouped(grouped, this)
        }
    }
    private fun setupButtons() {
        binding.btnAddFile.setOnClickListener {
            pickFileLauncher.launch(arrayOf("*/*"))
        }
    }
    private fun observeViewModel() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.driveItems.collect { items ->
                    cachedItems = items
                    val grouped = groupDriveItemsByZoom(items, spanCount)
                    adapter.submitGrouped(grouped, this@DriveActivity)
                }
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    when (event) {
                        is DriveViewModel.DriveEvent.ShowMessage -> {
                            if (event.vibrate) VibrationUtils.vibrateError(this@DriveActivity)
                            Toast.makeText(this@DriveActivity, event.msg, Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }
    private fun handlePickedFile(fileUri: Uri) {
        var fileName = "unknown"
        var fileSize = 0L
        val mimeType = contentResolver.getType(fileUri) ?: "application/octet-stream"
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
        Log.d("DriveActivity", "File selezionato: $fileName, size: $fileSize, mime: $mimeType")
        viewModel.addFileItem(this, fileUri, fileName, fileSize, mimeType)
        partnerId?.let {
            notificationViewModel.sendNotification(
                type = "drive_media",
                receiverId = it,
                title = "Diario aggiornato\uD83E\uDDFE",
                body = "$currentUser ha aggiunto un nuovo ricordo, guardalo!"
            )
        }
    }
}