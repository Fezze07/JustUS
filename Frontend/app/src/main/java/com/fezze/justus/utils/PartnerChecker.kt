package com.fezze.justus.utils

import android.app.Activity
import android.content.Intent
import android.widget.Toast
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.repository.ApiRepository
import com.fezze.justus.ui.partner.PartnerActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object PartnerChecker {
    fun checkPartner(activity: Activity, onResult: ((Boolean) -> Unit)? = null) {
        val repo = ApiRepository()
        CoroutineScope(Dispatchers.IO).launch {
            val result = repo.getPartnership()
            withContext(Dispatchers.Main) {
                when (result) {
                    is ResultWrapper.Success -> {
                        val partnership = result.value
                        if (partnership.hasAcceptedPartner() && partnership.partner != null) {
                            val partner = partnership.partner
                            SharedPrefsManager.savePartner(activity, partner.id, partner.username)
                            onResult?.invoke(true)
                        } else {
                            Toast.makeText(activity, "Seleziona un partner per continuare", Toast.LENGTH_SHORT).show()
                            activity.startActivity(Intent(activity, PartnerActivity::class.java))
                            activity.finish()
                            onResult?.invoke(false)
                        }
                    }
                    is ResultWrapper.GenericError -> {
                        Toast.makeText(activity, "Impossibile controllare partner", Toast.LENGTH_SHORT).show()
                        onResult?.invoke(false)
                    }
                    is ResultWrapper.NetworkError -> {
                        Toast.makeText(activity, "Nessuna connessione", Toast.LENGTH_SHORT).show()
                        onResult?.invoke(false)
                    }
                }
            }
        }
    }
}
