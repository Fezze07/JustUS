package com.fezze.justus.ui.drive.holders
import android.annotation.SuppressLint
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.fezze.justus.R
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.ui.drive.utils.buildFullUrl
import com.fezze.justus.ui.drive.utils.loadAndCacheThumbnail
import com.google.android.material.button.MaterialButton
import io.getstream.photoview.PhotoView
class DriveVideoViewHolder( itemView: View,
    onDelete: ((Int) -> Unit)? = null,
    onAddReaction: ((Int, String) -> Unit)? = null,
    onToggleFavorite: ((Int) -> Unit)? = null
) : DriveBaseViewHolder(itemView, onDelete, onAddReaction, onToggleFavorite) {
    private val playerView: PlayerView = itemView.findViewById(R.id.playerView)
    private val btnPlayPause: MaterialButton = itemView.findViewById(R.id.btnPauseVideo)
    private val thumbnail: PhotoView = itemView.findViewById(R.id.ivVideoThumbnail)
    private var player: ExoPlayer? = null
    init {
        itemView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {}
            override fun onViewDetachedFromWindow(v: View) {
                releasePlayer()
            }
        })
    }
    override fun bind(item: DriveItem, onEdit: ((Int, String) -> Unit)?) {
        super.bind(item, onEdit)
        val url = buildFullUrl(item.content)
        releasePlayer()
        playerView.visibility = View.GONE
        thumbnail.visibility = View.VISIBLE
        btnPlayPause.apply {
            visibility = View.VISIBLE
            text = itemView.context.getString(R.string.btn_play)
            isEnabled = true
        }
        loadAndCacheThumbnail(itemView.context, thumbnail, url, item.id, R.drawable.ic_video_placeholder, isVideo = true)
        btnPlayPause.setOnClickListener {
            if (player == null) startVideo(url) else togglePlayPause()
        }
    }
    private fun startVideo(url: String) {
        Toast.makeText(itemView.context, "Caricamento video…", Toast.LENGTH_SHORT).show()
        thumbnail.alpha = 0f
        playerView.visibility = View.VISIBLE
        playerView.requestLayout()
        player = ExoPlayer.Builder(itemView.context).build().also {
            playerView.player = it
            it.setMediaItem(MediaItem.fromUri(url))
            it.prepare()
            it.addListener(playerListener)
        }
    }
    private fun togglePlayPause() {
        player?.let {
            if (it.isPlaying) {
                it.pause()
                thumbnail.alpha = 1f
                playerView.visibility = View.GONE
                btnPlayPause.text = itemView.context.getString(R.string.btn_play)
            } else {
                thumbnail.alpha = 0f
                playerView.visibility = View.VISIBLE
                playerView.requestLayout()
                it.play()
                btnPlayPause.text = itemView.context.getString(R.string.btn_pause)
            }
        }
    }
    private fun resetUi() {
        releasePlayer()
        playerView.visibility = View.GONE
        thumbnail.alpha = 1f
        btnPlayPause.text = itemView.context.getString(R.string.btn_play)
    }
    private val playerListener = object : Player.Listener {
        @SuppressLint("SwitchIntDef")
        override fun onPlaybackStateChanged(state: Int) {
            when (state) {
                Player.STATE_READY -> {
                    playerView.visibility = View.VISIBLE
                    playerView.requestLayout()
                    player?.play()
                    btnPlayPause.text = itemView.context.getString(R.string.btn_pause)
                }
                Player.STATE_ENDED -> resetUi()
            }
        }
        override fun onPlayerError(error: PlaybackException) {
            Toast.makeText(itemView.context, "Errore video ", Toast.LENGTH_SHORT).show()
            resetUi()
        }
    }
    private fun releasePlayer() {
        player?.release()
        player = null
        playerView.player = null
    }
    companion object {
        fun create(inflater: LayoutInflater, parent: ViewGroup,
            onDelete: ((Int) -> Unit)? = null,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveVideoViewHolder {
            val view = inflater.inflate(R.layout.item_drive, parent, false)
            return DriveVideoViewHolder(view, onDelete, onAddReaction, onToggleFavorite)
        }
        fun createForFavorites(inflater: LayoutInflater, parent: ViewGroup,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveVideoViewHolder {
            val view = inflater.inflate(R.layout.item_favorites, parent, false)
            return DriveVideoViewHolder(view, null, onAddReaction, onToggleFavorite)
        }
    }
}
