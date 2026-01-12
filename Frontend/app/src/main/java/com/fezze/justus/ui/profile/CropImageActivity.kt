package com.fezze.justus.ui.profile
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity
import com.canhub.cropper.CropImageView
import com.fezze.justus.R
import java.io.File

class CropImageActivity : AppCompatActivity() {
    companion object {
        const val EXTRA_IMAGE_URI = "extra_image_uri"
        const val RESULT_URI = "result_uri"
    }
    private lateinit var cropImageView: CropImageView
    private lateinit var btnConfirm: Button
    private lateinit var btnCancel: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_crop_image)
        cropImageView = findViewById(R.id.cropImageView)
        btnConfirm = findViewById(R.id.btnConfirm)
        btnCancel = findViewById(R.id.btnCancel)
        val imageUri = intent.getParcelableExtra(EXTRA_IMAGE_URI, Uri::class.java)
        imageUri?.let {
            cropImageView.setImageUriAsync(it)
            cropImageView.guidelines = CropImageView.Guidelines.OFF
            cropImageView.cropShape = CropImageView.CropShape.RECTANGLE
        }
        btnConfirm.setOnClickListener {
            val croppedBitmap = cropImageView.getCroppedImage()
            if (croppedBitmap != null) {
                val file = File(cacheDir, "cropped_profile.jpg")
                file.outputStream().use { out ->
                    croppedBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 100, out)
                }
                val resultIntent = Intent().apply {
                    putExtra(RESULT_URI, Uri.fromFile(file))
                }
                setResult(RESULT_OK, resultIntent)
            } else {
                setResult(RESULT_CANCELED)
            }
            finish()
        }
        btnCancel.setOnClickListener {
            setResult(RESULT_CANCELED)
            finish()
        }
    }
}
