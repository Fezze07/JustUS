package com.fezze.justus.data.repository

import android.content.Context
import android.net.Uri
import com.fezze.justus.JustusApp
import com.fezze.justus.data.models.*
import com.fezze.justus.data.network.RetrofitClient
import com.fezze.justus.utils.ResultWrapper
import com.fezze.justus.utils.safeCallResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okio.BufferedSink

class ApiRepository {
    private val api = RetrofitClient.getApi(JustusApp.appContext)
    // -------------------- Auth / User --------------------
    suspend fun loginUser(usernameWithCode: String, password: String, deviceToken: String
    ): ResultWrapper<LoginResponse> = safeCallResult {
        api.login(LoginRequestBody(usernameWithCode, password, deviceToken))
    }
    suspend fun registerUser(username: String, password: String, email: String?, deviceToken: String
    ): ResultWrapper<RegisterResponse> = safeCallResult {
        api.register(RegisterRequestBody(username, password, email, deviceToken))
    }
    suspend fun requestUserCodes(username: String, password: String): ResultWrapper<RequestCodesResponse> =
        safeCallResult {
            api.requestUserCodes(RequestCodesBody(username, password))
        }
    suspend fun updateDeviceToken(usernameWithCode: String, deviceToken: String): ResultWrapper<Unit> =
        safeCallResult { api.updateDeviceToken(UpdateTokenRequest(usernameWithCode, deviceToken)) }
            .let { result ->
                when (result) {
                    is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                    is ResultWrapper.GenericError -> result
                    is ResultWrapper.NetworkError -> result
                }
            }
    // -------------------- Profile --------------------
    suspend fun fetchProfile(): ResultWrapper<User> =
        safeCallResult { api.getProfile() }.let { result ->
            when (result) {
                is ResultWrapper.Success ->
                    result.value.profile?.let { ResultWrapper.Success(it) }
                        ?: ResultWrapper.GenericError(null, "Profilo non trovato")
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun fetchPartnerProfile(): ResultWrapper<User> =
        safeCallResult { api.getPartnerProfile() }.let { result ->
            when (result) {
                is ResultWrapper.Success ->
                    result.value.profile?.let { ResultWrapper.Success(it) }
                        ?: ResultWrapper.GenericError(null, "Profilo partner non trovato")
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun updateProfileBio(bio: String?): ResultWrapper<Unit> =
        safeCallResult { api.updateProfile(UpdateProfileRequest(bio)) }
            .let { result ->
                when (result) {
                    is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                    is ResultWrapper.GenericError -> result
                    is ResultWrapper.NetworkError -> result
                }
            }
    suspend fun changePassword(oldPassword: String, newPassword: String): ResultWrapper<Unit> =
        safeCallResult {
            api.changePassword(ChangePasswordRequest(oldPassword, newPassword))
        }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    // -------------------- Partnership --------------------
    suspend fun sendPartnerRequest(partnerUsername: String, partnerCode: String): ResultWrapper<Unit> =
        safeCallResult { api.sendPartnerRequest(PartnerRequestBody(partnerUsername, partnerCode)) }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun acceptPartnerRequest(requesterId: Int): ResultWrapper<Unit> =
        safeCallResult { api.acceptPartnerRequest(AcceptRequestBody(requesterId)) }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun rejectPartnerRequest(requesterId: Int): ResultWrapper<Unit> =
        safeCallResult { api.rejectPartnerRequest(AcceptRequestBody(requesterId)) }.let { result ->
            when(result) {
                is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun searchPartner(username: String?, code: String?): ResultWrapper<List<User>> =
        safeCallResult { api.searchPartner(username, code) }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(result.value.users)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun getPartnership(): ResultWrapper<PartnershipResponse> =
        safeCallResult { api.getPartnership() }
    // -------------------- MissYou / Mood --------------------
    suspend fun sendMissYou(): ResultWrapper<Int> =
        safeCallResult { api.sendMissYou() }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(result.value.total)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun fetchMissYouTotal(): ResultWrapper<Int> =
        safeCallResult { api.getMissYouTotal() }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(result.value.total)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun setMood(emoji: String): ResultWrapper<MoodResponse> =
        safeCallResult { api.setMood(MoodRequest(emoji)) }
    suspend fun fetchMyMood(): ResultWrapper<MoodResponse> =
        safeCallResult { api.getMood("me") }
    suspend fun fetchPartnerMood(): ResultWrapper<MoodResponse> =
        safeCallResult { api.getMood("partner") }
    suspend fun fetchRecentCoupleEmojis(): ResultWrapper<List<String>> =
        safeCallResult { api.getRecentGlobalEmojis() }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(result.value.emojis)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    // -------------------- BucketList --------------------
    suspend fun fetchBucketList(): ResultWrapper<BucketListResponse> =
        safeCallResult { api.getBucket() }
    suspend fun addBucketItem(text: String): ResultWrapper<GenericResponse> =
        safeCallResult { api.addBucketItem(AddBucketRequest(text)) }
    suspend fun toggleBucketDone(id: Int): ResultWrapper<GenericResponse> =
        safeCallResult { api.toggleDone(id) }
    suspend fun deleteBucketItem(id: Int): ResultWrapper<GenericResponse> =
        safeCallResult { api.deleteBucketItem(id) }
    // -------------------- Game --------------------
    suspend fun fetchNewGameQuestion(): ResultWrapper<GameNewQuestionResponse> =
        safeCallResult {
            api.getNewQuestion()
        }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(result.value)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun submitGameAnswer(questionId: Int, votedFor: String): ResultWrapper<Unit> =
        safeCallResult {
            api.submitAnswer(GameAnswerRequest(questionId, votedFor))
        }.let { result ->
            when (result) {
                is ResultWrapper.Success -> ResultWrapper.Success(Unit)
                is ResultWrapper.GenericError -> result
                is ResultWrapper.NetworkError -> result
            }
        }
    suspend fun fetchGameStats(): ResultWrapper<GameStatsResponse> =
        safeCallResult { api.getGameStats() }
    // -------------------- Drive / Upload --------------------
    suspend fun fetchDriveItems(): ResultWrapper<DriveListResponse> =
        safeCallResult { api.getDriveItems() }
    suspend fun createDriveItem(type: String, content: String?, metadata: Map<String, Any>?): ResultWrapper<DriveSingleResponse> =
        safeCallResult { api.addDriveItem(DriveItemRequest(type, content, metadata)) }
    suspend fun deleteDriveItem(id: Int): ResultWrapper<GenericResponse> =
        safeCallResult { api.deleteDriveItem(id) }
    suspend fun fetchDriveChanges(lastSync: String?): ResultWrapper<DriveSyncResponse> =
        safeCallResult { api.getDriveChanges(lastSync) }
    // -------------------- Reactions --------------------
    suspend fun addReaction(itemId: Int, emoji: String): ResultWrapper<DriveItemReactionResponse> =
        safeCallResult {
            api.addDriveReaction(itemId, DriveItemReaction(emoji))
        }
    suspend fun fetchReactions(itemId: Int): ResultWrapper<DriveItemReactionsListResponse> =
        safeCallResult {
            api.getDriveReactions(itemId)
        }
    // -------------------- Favorite --------------------
    suspend fun addFavorite(itemId: Int): ResultWrapper<GenericResponse> =
        safeCallResult {
            api.addFavorite(itemId)
        }
    suspend fun removeFavorite(itemId: Int): ResultWrapper<GenericResponse> =
        safeCallResult {
            api.removeFavorite(itemId)
        }
    // -------------------- App Version --------------------
    suspend fun checkAppVersion(): ResultWrapper<AppVersionResponse> =
        safeCallResult { api.getAppVersion() }
    // -------------------- Upload --------------------
    suspend fun uploadProfile(context: Context, fileUri: Uri, fileName: String, mimeType: String,
                              onProgress: (uploadedBytes: Long) -> Unit): ResultWrapper<String> {
        return uploadFile(context, fileUri, fileName, mimeType, "/upload/profile", onProgress)
    }
    suspend fun uploadDiary(context: Context, fileUri: Uri, fileName: String, mimeType: String,
                            onProgress: (uploadedBytes: Long) -> Unit): ResultWrapper<String> {
        return uploadFile(context, fileUri, fileName, mimeType, "/upload/diary", onProgress)
    }
    private suspend fun uploadFile(context: Context, fileUri: Uri, fileName: String, mimeType: String, route: String,
                                   onProgress: (uploadedBytes: Long) -> Unit): ResultWrapper<String> {
        return withContext(Dispatchers.IO) {
            try {
                val filePart = prepareFilePartWithProgress(context, fileUri, fileName, mimeType, onProgress)
                val response = api.uploadFile(route, filePart)
                if (response.isSuccessful && response.body()?.success == true) {
                    ResultWrapper.Success(response.body()!!.url)
                } else {
                    ResultWrapper.GenericError(response.code(), "Upload fallito")
                }
            } catch (_: Exception) {
                ResultWrapper.NetworkError
            }
        }
    }
    fun prepareFilePartWithProgress(context: Context, fileUri: Uri, fileName: String, mimeType: String,
                                    onProgress: (uploadedBytes: Long) -> Unit): MultipartBody.Part {
        val inputStream = context.contentResolver.openInputStream(fileUri)!!
        val fileBytes = inputStream.readBytes()
        inputStream.close()
        val requestBody = object : RequestBody() {
            override fun contentType() = mimeType.toMediaTypeOrNull()
            override fun contentLength() = fileBytes.size.toLong()
            override fun writeTo(sink: BufferedSink) {
                var bytesWritten = 0L
                val buffer = ByteArray(32 * 1024)
                val input = fileBytes.inputStream()
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    sink.write(buffer, 0, read)
                    bytesWritten += read
                    onProgress(bytesWritten)
                }
                input.close()
            }
        }
        return MultipartBody.Part.createFormData("file", fileName, requestBody)
    }
}