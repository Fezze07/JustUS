package com.fezze.justus.utils

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.content.getSystemService

object VibrationUtils {
    fun vibrateError(context: Context, durationMs: Long = 80) {
        val vibrator: Vibrator? = context.getSystemService()
        vibrator?.let {
            if (it.hasVibrator()) {
                it.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            }
        }
    }
}