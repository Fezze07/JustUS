package com.fezze.justus.ui.drive.holders
import android.media.MediaPlayer
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.core.net.toUri
import com.fezze.justus.R
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.ui.drive.utils.buildFullUrl

class DriveAudioViewHolder( itemView: View,
    onDelete: ((Int) -> Unit)? = null,
    onAddReaction: ((Int, String) -> Unit)? = null,
    onToggleFavorite: ((Int) -> Unit)? = null
) : DriveBaseViewHolder(itemView, onDelete, onAddReaction, onToggleFavorite) {
    private val tvText: TextView = itemView.findViewById(R.id.tvText)
    private var mediaPlayer: MediaPlayer? = null
    override fun bind(item: DriveItem, onEdit: ((Int, String) -> Unit)?) {
        super.bind(item, onEdit)
        tvText.visibility = View.VISIBLE
        tvText.text = itemView.context.getString(R.string.drive_listen_audio)
        itemView.setOnClickListener {
            if (mediaPlayer == null) startAudio(item) else stopAudio()
        }
    }
    private fun startAudio(item: DriveItem) {
        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(itemView.context, buildFullUrl(item.content).toUri())
                setOnPreparedListener { it.start() }
                setOnCompletionListener { stopAudio() }
                prepareAsync()
            }
            Toast.makeText(itemView.context, "Caricamento audio…", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            stopAudio()
            Toast.makeText(itemView.context, "Errore audio", Toast.LENGTH_SHORT).show()
        }
    }
    private fun stopAudio() {
        try { mediaPlayer?.stop() } catch (_: Exception) {}
        try { mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
    }
    companion object {
        fun create(inflater: LayoutInflater, parent: ViewGroup,
            onDelete: ((Int) -> Unit)? = null,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveAudioViewHolder {
            val view = inflater.inflate(R.layout.item_drive, parent, false)
            return DriveAudioViewHolder(view, onDelete, onAddReaction, onToggleFavorite)
        }
        fun createForFavorites(inflater: LayoutInflater, parent: ViewGroup,
            onAddReaction: ((Int, String) -> Unit)? = null,
            onToggleFavorite: ((Int) -> Unit)? = null
        ): DriveAudioViewHolder {
            val view = inflater.inflate(R.layout.item_favorites, parent, false)
            return DriveAudioViewHolder(view, null, onAddReaction, onToggleFavorite)
        }
    }
}
