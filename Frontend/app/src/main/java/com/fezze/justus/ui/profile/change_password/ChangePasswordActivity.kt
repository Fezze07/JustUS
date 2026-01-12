package com.fezze.justus.ui.profile.change_password

import android.annotation.SuppressLint
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import com.fezze.justus.R
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.VibrationUtils

class ChangePasswordActivity : AppCompatActivity() {
    private val viewModel: ChangePasswordViewModel by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_change_password)
        val etOld = findViewById<EditText>(R.id.etOldPassword)
        val etNew = findViewById<EditText>(R.id.etNewPassword)
        val btn = findViewById<Button>(R.id.btnConfirm)
        setupPasswordToggle(etOld)
        setupPasswordToggle(etNew)
        btn.setOnClickListener {
            viewModel.changePassword(
                etOld.text.toString(),
                etNew.text.toString()
            )
        }
        viewModel.state.observe(this) { res ->
            when (res) {
                is ResultWrapper.Success -> {
                    Toast.makeText(this, "Password aggiornata", Toast.LENGTH_SHORT).show()
                    finish()
                }
                is ResultWrapper.GenericError -> {
                    VibrationUtils.vibrateError(this)
                    Toast.makeText(this, res.message ?: "Errore", Toast.LENGTH_SHORT).show()
                }
                is ResultWrapper.NetworkError -> {
                    VibrationUtils.vibrateError(this)
                    Toast.makeText(this, "Offline", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
    @SuppressLint("ClickableViewAccessibility")
    private fun setupPasswordToggle(editText: EditText) {
        editText.setOnTouchListener { v, event ->
            if (event.action == android.view.MotionEvent.ACTION_UP) {
                val drawableEnd = editText.compoundDrawables[2]
                if (drawableEnd != null &&
                    event.rawX >= (editText.right - drawableEnd.bounds.width())
                ) {
                    v.performClick()
                    togglePasswordVisibility(editText)
                    return@setOnTouchListener true
                }
            }
            false
        }
    }
    private fun togglePasswordVisibility(editText: EditText) {
        val isHidden = editText.inputType ==
                (android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD)
        editText.inputType =
            if (isHidden)
                android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            else
                android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        editText.setSelection(editText.text.length)
        val icon = if (isHidden) R.drawable.ic_eye_on else R.drawable.ic_eye_off
        editText.setCompoundDrawablesWithIntrinsicBounds(0, 0, icon, 0)
    }
}
