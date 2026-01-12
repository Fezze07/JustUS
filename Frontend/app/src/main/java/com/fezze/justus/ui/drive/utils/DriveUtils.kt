package com.fezze.justus.ui.drive.utils

import android.content.Context
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import com.fezze.justus.BuildConfig
import com.fezze.justus.R
import com.fezze.justus.ui.drive.DriveLocalCache
import java.io.File

fun buildFullUrl(path: String): String {
    return if (path.startsWith("http")) path else BuildConfig.BASE_URL + path.removePrefix("/")
}
fun loadAndCacheThumbnail(context: Context, thumb: ImageView, url: String, itemId: Int,
                          placeholder: Int = R.drawable.ic_image_placeholder, isVideo: Boolean = false, frameTimeUs: Long = 1_000_000) {
    val cachedFile = DriveLocalCache.getThumbPath(context, itemId)?.let { File(it) }
    if (cachedFile != null && cachedFile.exists()) {
        Glide.with(context)
            .load(cachedFile)
            .placeholder(placeholder)
            .into(thumb)
        return
    }
    val request = Glide.with(context)
        .asBitmap()
        .load(url)
        .apply(
            RequestOptions()
                .placeholder(placeholder)
                .error(placeholder)
                .diskCacheStrategy(DiskCacheStrategy.ALL)
        )
    if (isVideo) request.frame(frameTimeUs)
    request.into(object : com.bumptech.glide.request.target.BitmapImageViewTarget(thumb) {
        override fun setResource(resource: android.graphics.Bitmap?) {
            if (resource == null) {
                thumb.setImageResource(placeholder)
                return
            }
            thumb.setImageBitmap(resource)
            Thread {
                try {
                    val cacheDir = File(context.cacheDir, "drive_thumbs")
                    if (!cacheDir.exists()) cacheDir.mkdirs()
                    val file = File(cacheDir, "thumb_$itemId.png")
                    file.outputStream().use { out ->
                        resource.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                    }
                    DriveLocalCache.saveThumbPath(context, itemId, file.absolutePath)
                } catch (_: Exception) {}
            }.start()
        }
    })
}
fun prefetchThumbnail(context: Context, url: String, itemId: Int, isVideo: Boolean = false) {
    val cachedFile = DriveLocalCache.getThumbPath(context, itemId)?.let { File(it) }
    if (cachedFile != null && cachedFile.exists()) return
    val request = Glide.with(context)
        .asBitmap()
        .load(url)
        .diskCacheStrategy(DiskCacheStrategy.ALL)
    if (isVideo) request.frame(1_000_000)
    request.preload()
}
