package com.fezze.justus.utils

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.Response
import java.io.IOException

suspend fun <T> safeCallResult(call: suspend () -> Response<T>): ResultWrapper<T> {
    return withContext(Dispatchers.IO) {
        try {
            val response = call()
            if (response.isSuccessful && response.body() != null) {
                ResultWrapper.Success(response.body()!!)
            } else {
                ResultWrapper.GenericError(
                    code = response.code(),
                    message = response.errorBody()?.string()
                )
            }
        } catch (_: IOException) {
            ResultWrapper.NetworkError
        } catch (e: Exception) {
            ResultWrapper.GenericError(message = e.localizedMessage)
        }
    }
}