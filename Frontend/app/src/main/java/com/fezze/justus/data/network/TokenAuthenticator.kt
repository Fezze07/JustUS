package com.fezze.justus.data.network

import android.content.Context
import android.content.Intent
import android.util.Log
import com.fezze.justus.BuildConfig
import com.fezze.justus.data.local.SharedPrefsManager
import com.fezze.justus.data.models.RefreshRequest
import com.fezze.justus.ui.auth.login.LoginActivity
import okhttp3.Authenticator
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

class TokenAuthenticator(private val context: Context) : Authenticator {
    private val authApi = createAuthClient()

    override fun authenticate(route: Route?, response: Response): Request? {
        if (responseCount(response) >= 2) return null
        if (response.request.url.encodedPath.contains("/auth/refresh")) return null
        val refreshToken = SharedPrefsManager.getRefreshToken(context)
        if (refreshToken.isNullOrEmpty()) return null
        return try {
            val refreshResponse = authApi.refreshToken(RefreshRequest(refreshToken)).execute()
            val body = refreshResponse.body()
            if (refreshResponse.isSuccessful && !body?.accessToken.isNullOrEmpty()) {
                SharedPrefsManager.saveAccessToken(context, body.accessToken)
                body.refreshToken?.let { SharedPrefsManager.saveRefreshToken(context, it) }
                response.request.newBuilder()
                    .header("Authorization", "Bearer ${body.accessToken}")
                    .build()
            } else {
                logout()
            }
        } catch (e: Exception) {
            Log.e("TokenAuthenticator", "Errore critico durante refresh", e)
            null
        }
    }
    private fun logout(): Request? {
        SharedPrefsManager.clearAuth(context)
        val intent = Intent(context, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        context.startActivity(intent)
        return null
    }
    private fun responseCount(response: Response): Int {
        var count = 1
        var prior = response.priorResponse
        while (prior != null) {
            count++
            prior = prior.priorResponse
        }
        return count
    }
    private fun createAuthClient(): ApiService {
        return Retrofit.Builder()
            .baseUrl(BuildConfig.BASE_URL)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(ApiService::class.java)
    }
}