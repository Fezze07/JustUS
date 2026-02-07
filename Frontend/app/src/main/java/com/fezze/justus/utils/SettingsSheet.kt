package com.fezze.justus.utils

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.fezze.justus.R
import com.fezze.justus.ui.favorites.FavoritesActivity
import com.fezze.justus.ui.profile.ProfileActivity
import com.fezze.justus.ui.partner.PartnerActivity
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

class SettingsSheet : BottomSheetDialogFragment() {
    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.popup_settings, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        // Profilo
        view.findViewById<View>(R.id.optionProfile).setOnClickListener {
            startActivity(Intent(requireContext(), ProfileActivity::class.java))
            dismiss()
        }
        // Ricerca partner
        view.findViewById<View>(R.id.optionPartner).setOnClickListener {
            startActivity(Intent(requireContext(), PartnerActivity::class.java))
            dismiss()
        }
        // Preferiti
        view.findViewById<View>(R.id.optionFavorites).setOnClickListener {
            startActivity(Intent(requireContext(), FavoritesActivity::class.java))
            dismiss()
        }
    }

    override fun getTheme(): Int {
        return R.style.BottomSheetDialogTheme
    }
}