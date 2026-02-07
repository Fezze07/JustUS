package com.fezze.justus.ui.drive.utils

import com.fezze.justus.data.models.DriveItem
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.TextStyle
import java.util.Locale

fun groupDriveItemsByZoom(items: List<DriveItem>, spanCount: Int): Map<String, List<DriveItem>> {
    val localeIt = Locale.forLanguageTag("it-IT")
    val grouped: Map<Any, List<DriveItem>> = when(spanCount) {
        // 🔹 GIORNO
        1, 2 -> items.mapNotNull { it.created_at.toLocalDateTime()?.toLocalDate()?.let { date -> date to it } }
            .groupBy({ it.first }, { it.second }) // chiave = LocalDate
        // 🔹 MESE
        3, 4 -> items.mapNotNull { it.created_at.toLocalDateTime()?.let { dt -> Pair(dt.year, dt.monthValue) to it } }
            .groupBy({ it.first }, { it.second }) // chiave = Pair(year, month)
        // 🔹 ANNO
        else -> items.mapNotNull { it.created_at.toLocalDateTime()?.year?.let { year -> year to it } }
            .groupBy({ it.first }, { it.second }) // chiave = Int
    }
    val sortedKeys = grouped.keys.sortedWith { a, b ->
        when (a) {
            is LocalDate if b is LocalDate -> b.compareTo(a)
            is Pair<*, *> if b is Pair<*, *> -> {
                val ay = a.first as Int
                val am = a.second as Int
                val by = b.first as Int
                val bm = b.second as Int
                if (by != ay) by - ay else bm - am
            }
            is Int if b is Int -> b - a
            else -> 0
        }
    }
    return sortedKeys.associateWith { key -> grouped[key]!! }
        .mapKeys { (key, _) ->
            when(key) {
                is LocalDate -> "${key.dayOfMonth} ${key.month.getDisplayName(TextStyle.FULL, localeIt).replaceFirstChar { it.uppercase() }}"
                is Pair<*, *> -> {
                    val year = key.first as Int
                    val month = key.second as Int
                    val monthName = java.time.Month.of(month).getDisplayName(TextStyle.FULL, localeIt)
                    "${monthName.replaceFirstChar { it.uppercase() }} $year"
                }
                is Int -> key.toString()
                else -> key.toString()
            }
        }
}
fun String.toLocalDateTime(): LocalDateTime? {
    return try {
        ZonedDateTime.parse(this)
            .withZoneSameInstant(ZoneId.systemDefault())
            .toLocalDateTime()
    } catch (_: Exception) {
        null
    }
}