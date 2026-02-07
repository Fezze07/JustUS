package com.fezze.justus.data.network

import android.content.Context
import com.fezze.justus.data.local.SharedPrefsManager
import okhttp3.Interceptor
import okhttp3.Response
class AuthInterceptor(private val context: Context) : Interceptor {
    private val skipUrls = listOf("/auth/login", "/auth/register", "/auth/refresh")

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        if (skipUrls.any { request.url.encodedPath.contains(it) }) {
            return chain.proceed(request)
        }
        val token = SharedPrefsManager.getAccessToken(context)
        val newRequest = request.newBuilder()
            .apply {
                if (!token.isNullOrEmpty()) {
                    addHeader("Authorization", "Bearer $token")
                }
            }
            .build()
        return chain.proceed(newRequest)
    }
}