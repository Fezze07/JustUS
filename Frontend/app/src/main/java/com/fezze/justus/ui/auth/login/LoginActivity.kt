package com.fezze.justus.ui.auth.login

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.databinding.ActivityLoginBinding
import com.fezze.justus.ui.auth.register.RegisterActivity
import com.fezze.justus.ui.homepage.HomepageActivity
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.launch
class LoginActivity : AppCompatActivity() {
    private lateinit var binding: ActivityLoginBinding
    private val viewModel: LoginViewModel by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 🔥 Auto-login se ho già tutto
        val savedUsername = SharedPrefsManager.getUsername(this)
        val savedCode = SharedPrefsManager.getUserCode(this)
        if (!savedUsername.isNullOrEmpty() && !savedCode.isNullOrEmpty()) {
            goToHomepage()
            return
        }
        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)
        requestNotificationPermission()
        prefillUsername()
        setupButtons()
        observeViewModel()
    }
    private fun requestNotificationPermission() {
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }
    private fun prefillUsername() {
        intent.getStringExtra("username")?.let {
            binding.usernameInput.setText(it)
        }
    }
    private fun setupButtons() {
        binding.registerBtn.setOnClickListener {
            startActivity(Intent(this, RegisterActivity::class.java))
        }
        binding.loginBtn.setOnClickListener {
            val username = binding.usernameInput.text.toString()
            val password = binding.passwordInput.text.toString()
            val savedCode = SharedPrefsManager.getUserCode(this)
            if (savedCode.isNullOrBlank()) {
                viewModel.requestCodes(username, password, this)
            } else {
                loginWithCode(username, savedCode, password)
            }
        }
    }
    private fun observeViewModel() {
        lifecycleScope.launch {
            viewModel.uiEvents.collect { event ->
                when (event) {
                    is LoginViewModel.LoginEvent.SuccessLogin -> goToHomepage()
                    is LoginViewModel.LoginEvent.SingleCodeFound -> {
                        val username = binding.usernameInput.text.toString()
                        val password = binding.passwordInput.text.toString()
                        SharedPrefsManager.saveUserCode(this@LoginActivity, event.code)
                        loginWithCode(username, event.code, password)
                    }
                    is LoginViewModel.LoginEvent.MultipleCodesFound -> {
                        showChooseAccountDialog(event.codes)
                    }
                    is LoginViewModel.LoginEvent.ShowMessage -> {
                        Toast.makeText(this@LoginActivity, event.msg, Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }
    private fun loginWithCode(username: String, code: String, password: String) {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                Toast.makeText(this, "Token FCM non disponibile", Toast.LENGTH_SHORT).show()
                return@addOnCompleteListener
            }
            val deviceToken = task.result ?: ""
            viewModel.login(this, "$username#$code", password, deviceToken)
        }
    }
    private fun showChooseAccountDialog(codes: List<String>) {
        val username = binding.usernameInput.text.toString()
        val password = binding.passwordInput.text.toString()
        val items = codes.map { "$username#$it" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Scegli account")
            .setItems(items) { _, index ->
                val selectedCode = codes[index]
                SharedPrefsManager.saveUserCode(this, selectedCode)
                loginWithCode(username, selectedCode, password)
            }
            .setCancelable(true)
            .show()
    }
    private fun goToHomepage() {
        startActivity(Intent(this, HomepageActivity::class.java))
        finish()
    }
}