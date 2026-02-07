package com.fezze.justus.ui.auth.register

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.databinding.ActivityRegisterBinding
import com.fezze.justus.ui.auth.login.LoginActivity
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.launch
class RegisterActivity : AppCompatActivity() {
    private lateinit var binding: ActivityRegisterBinding
    private val viewModel: RegisterViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRegisterBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.registerBtn.setOnClickListener {
            val username = binding.usernameInput.text.toString()
            val password = binding.passwordInput.text.toString()
            val confermaPassword = binding.confermaPasswordInput.text.toString()
            val email = binding.emailInput.text.toString()
            if (password != confermaPassword) {
                Toast.makeText(this, "Le password non corrispondono", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val token = task.result ?: ""
                    viewModel.register(this, username, password, email, token)
                } else {
                    Toast.makeText(this, "Impossibile ottenere token FCM", Toast.LENGTH_SHORT).show()
                }
            }
        }
        lifecycleScope.launch {
            viewModel.uiEvents.collect { event ->
                when (event) {
                    is RegisterViewModel.RegisterEvent.SuccessRegister -> {
                        val user = event.user
                        SharedPrefsManager.saveUserCode(this@RegisterActivity, user.code)
                        Toast.makeText(
                            this@RegisterActivity,
                            "Il tuo codice è: ${user.code}\n",
                            Toast.LENGTH_LONG
                        ).show()
                        val intent = Intent(this@RegisterActivity, LoginActivity::class.java)
                        intent.putExtra("username", user.username)
                        startActivity(intent)
                        finish()
                    }
                    is RegisterViewModel.RegisterEvent.ShowMessage -> {
                        Toast.makeText(this@RegisterActivity, event.msg, Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }
}