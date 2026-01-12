package com.fezze.justus.ui.partner
import android.os.Bundle
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.addTextChangedListener
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.fezze.justus.R
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.databinding.ActivityPartnerBinding
import com.fezze.justus.utils.VibrationUtils
import kotlinx.coroutines.launch
import kotlin.getValue
class PartnerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityPartnerBinding
    private val viewModel: PartnerViewModel by viewModels()
    private lateinit var adapterReceived: PartnerRequestAdapter
    private lateinit var adapterSuggestions: PartnerRequestAdapter
    private var isAutoFill = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPartnerBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setupUI()
        observeViewModel()
    }
    private fun setupUI() {
        val myCode = SharedPrefsManager.getUserCode(this) ?: "******"
        binding.tvMyCode.text = getString(R.string.my_code_text, myCode)
        adapterReceived = PartnerRequestAdapter(
            onAccept = { id -> viewModel.acceptPartner(id) },
            onReject = { id -> viewModel.rejectPartner(id) }
        )
        binding.recyclerReceived.adapter = adapterReceived
        binding.recyclerReceived.layoutManager = LinearLayoutManager(this)
        adapterSuggestions = PartnerRequestAdapter(
            onClick = { user ->
                isAutoFill = true
                binding.searchEditText.setText(user.username)
                binding.codeEditText.setText(user.code)
                isAutoFill = false
            }
        )
        binding.recyclerSuggestions.adapter = adapterSuggestions
        binding.recyclerSuggestions.layoutManager = LinearLayoutManager(this)
        binding.searchEditText.addTextChangedListener { editable ->
            if (isAutoFill) return@addTextChangedListener
            viewModel.usernameQuery.value = editable.toString()
        }
        binding.codeEditText.addTextChangedListener { editable ->
            if (isAutoFill) return@addTextChangedListener
            viewModel.codeQuery.value = editable.toString()
        }
        // Bottone invia richiesta
        binding.btnSendRequest.setOnClickListener {
            val username = binding.searchEditText.text.toString()
            val code = binding.codeEditText.text.toString()
            if (username.isNotBlank() && code.isNotBlank()) {
                viewModel.sendPartnerRequest(username, code)
            } else {
                Toast.makeText(this, "Inserisci username e codice", Toast.LENGTH_SHORT).show()
            }
        }
    }
    private fun observeViewModel() {
        // Eventi UI
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiEvents.collect { event ->
                    if (event is PartnerViewModel.UiEvent.ShowMessage) {
                        if (event.vibrate) VibrationUtils.vibrateError(this@PartnerActivity)
                        Toast.makeText(this@PartnerActivity, event.message, Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
        // Richieste ricevute
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.partnershipInfo.collect { info ->
                    adapterReceived.submitList(info?.pendingRequests?.received ?: emptyList())
                }
            }
        }
        // Suggerimenti ricerca
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.suggestedUsers.collect { suggestions ->
                    adapterSuggestions.submitList(suggestions)
                }
            }
        }
    }
}