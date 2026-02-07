package com.fezze.justus.ui.drive.holders

import android.app.DownloadManager
import android.content.Context
import android.os.Environment
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.net.toUri
import androidx.recyclerview.widget.RecyclerView

import com.fezze.justus.R
import com.fezze.justus.data.models.DriveItem
import com.fezze.justus.ui.drive.utils.buildFullUrl

abstract class DriveBaseViewHolder(
    itemView: View,
    private val onDelete: ((Int) -> Unit)?,
    private val onAddReaction: ((Int, String) -> Unit)?,
    private val onToggleFavorite: ((Int) -> Unit)? = null
) : RecyclerView.ViewHolder(itemView) {
    protected val reactionsLayout: LinearLayout = itemView.findViewById(R.id.reactionsLayout)
    protected val btnDelete: View? = itemView.findViewById(R.id.btnDelete)
    protected val btnDownload: View? = itemView.findViewById(R.id.btnDownload)
    protected val btnFavorite: View? = itemView.findViewById(R.id.btnFavorite)
    open fun bind(item: DriveItem, onEdit: ((Int, String) -> Unit)? = null) {
        setupButtons(item)
        setupReactions(item)
        setupFavorite(item)
    }
    /** Gestione pulsanti Delete / Edit / Download **/
    private fun setupButtons(item: DriveItem) {
        // DELETE sempre visibile
        btnDelete?.visibility = View.VISIBLE
        btnDelete?.setOnClickListener {
            AlertDialog.Builder(itemView.context)
                .setTitle("Elimina contenuto")
                .setMessage("Sei sicuro? 😬")
                .setPositiveButton("Elimina") { _, _ -> onDelete?.invoke(item.id) }
                .setNegativeButton("Annulla", null)
                .show()
        }
        // DOWNLOAD solo per media + unknown
        if (item.type == "image" || item.type == "video" || item.type == "audio" || item.type == "unknown") {
            btnDownload?.visibility = View.VISIBLE
            btnDownload?.setOnClickListener {
                try {
                    val ctx = itemView.context
                    val uri = buildFullUrl(item.content).toUri()
                    val fileName = "${item.id}_${uri.lastPathSegment ?: item.id}"
                    val request = DownloadManager.Request(uri)
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
                    val manager = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    manager.enqueue(request)
                    Toast.makeText(ctx, "Download avviato 📥", Toast.LENGTH_SHORT).show()
                } catch (_: Exception) {
                    Toast.makeText(itemView.context, "Errore download 💀", Toast.LENGTH_SHORT).show()
                }
            }
        } else {
            btnDownload?.visibility = View.GONE
        }
    }
    /** Reactions **/
    private fun setupReactions(item: DriveItem) {
        reactionsLayout.removeAllViews()
        item.reactions.forEach { emoji ->
            val tv = TextView(itemView.context).apply {
                text = emoji
                textSize = 20f
                setPadding(6, 0, 6, 0)
            }
            reactionsLayout.addView(tv)
        }
        val addReaction = TextView(itemView.context).apply {
            text = "+"
            textSize = 22f
            setPadding(10, 0, 10, 0)
            setOnClickListener { showAddReactionDialog(item) }
        }
        reactionsLayout.addView(addReaction)
    }
    private fun showAddReactionDialog(item: DriveItem) {
        val ctx = itemView.context
        val input = EditText(ctx).apply {
            hint = "Emoji 👀"
            textSize = 18f
        }
        AlertDialog.Builder(ctx)
            .setTitle("Aggiungi reaction")
            .setView(input)
            .setPositiveButton("Aggiungi") { _, _ ->
                val emoji = input.text.toString().trim()
                if (emoji.isNotEmpty()) {
                    onAddReaction?.invoke(item.id, emoji)
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }
    private fun setupFavorite(item: DriveItem) {
        btnFavorite?.visibility = View.VISIBLE
        updateFavoriteUI(item.is_favorite)
        btnFavorite?.setOnClickListener {
            onToggleFavorite?.invoke(item.id)
        }
    }
    private fun updateFavoriteUI(isFavorite: Int) {
        val starIcon = if (isFavorite == 1) R.drawable.ic_star_filled else R.drawable.ic_star_outline
        (btnFavorite as? android.widget.ImageView)?.setImageResource(starIcon)
    }
}