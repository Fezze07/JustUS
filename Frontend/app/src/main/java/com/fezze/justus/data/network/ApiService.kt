package com.fezze.justus.data.network

import com.fezze.justus.data.models.*
import okhttp3.MultipartBody
import retrofit2.Call
import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Url

interface ApiService {
    @POST("auth/login")
    suspend fun login(@Body body: LoginRequestBody): Response<LoginResponse>
    @POST("auth/register")
    suspend fun register(@Body body: RegisterRequestBody): Response<RegisterResponse>
    @POST("auth/request-code")
    suspend fun requestUserCodes(@Body body: RequestCodesBody): Response<RequestCodesResponse>
    @POST("auth/device-token")
    suspend fun updateDeviceToken(@Body body: UpdateTokenRequest): Response<UpdateTokenResponse>
    @POST("auth/refresh")
    fun refreshToken(@Body body: RefreshRequest): Call<RefreshResponse>
    @GET("profile")
    suspend fun getProfile(): Response<ProfileResponse>
    @GET("profile/partner")
    suspend fun getPartnerProfile(): Response<ProfileResponse>
    @PATCH("profile")
    suspend fun updateProfile(@Body body: UpdateProfileRequest): Response<GenericResponse>
    @POST("profile/change-password")
    suspend fun changePassword(@Body body: ChangePasswordRequest): Response<GenericResponse>
    @POST("partnerships/request")
    suspend fun sendPartnerRequest(@Body body: PartnerRequestBody): Response<GenericResponse>
    @POST("partnerships/accept")
    suspend fun acceptPartnerRequest(@Body body: AcceptRequestBody): Response<GenericResponse>
    @POST("partnerships/reject")
    suspend fun rejectPartnerRequest(@Body body: AcceptRequestBody): Response<GenericResponse>
    @GET("partnerships/search")
    suspend fun searchPartner(@Query("username") username: String?, @Query("code") code: String?): Response<SearchPartnerResponse>
    @GET("partnerships")
    suspend fun getPartnership(): Response<PartnershipResponse>
    @POST("missyou")
    suspend fun sendMissYou(): Response<MissYouResponse>
    @GET("missyou/total")
    suspend fun getMissYouTotal(): Response<MissYouResponse>
    @POST("mood")
    suspend fun setMood(@Body request: MoodRequest): Response<MoodResponse>
    @GET("mood")
    suspend fun getMood(@Query("target") target: String): Response<MoodResponse>
    @GET("mood/recent/couple")
    suspend fun getRecentGlobalEmojis(): Response<EmojiResponse>
    @GET("bucket")
    suspend fun getBucket(): Response<BucketListResponse>
    @POST("bucket")
    suspend fun addBucketItem(@Body req: AddBucketRequest): Response<GenericResponse>
    @PATCH("bucket/{id}")
    suspend fun toggleDone(@Path("id") id: Int): Response<GenericResponse>
    @DELETE("bucket/{id}")
    suspend fun deleteBucketItem(@Path("id") id: Int): Response<GenericResponse>
    @GET("game/new")
    suspend fun getNewQuestion(): Response<GameNewQuestionResponse>
    @POST("game/answer")
    suspend fun submitAnswer(@Body request: GameAnswerRequest): Response<GenericResponse>
    @GET("game/stats")
    suspend fun getGameStats(): Response<GameStatsResponse>
    @GET("drive")
    suspend fun getDriveItems(): Response<DriveListResponse>
    @POST("drive")
    suspend fun addDriveItem(@Body req: DriveItemRequest): Response<DriveSingleResponse>
    @DELETE("drive/{id}")
    suspend fun deleteDriveItem(@Path("id") id: Int): Response<GenericResponse>
    @POST("drive/{id}/reaction")
    suspend fun addDriveReaction(@Path("id") itemId: Int, @Body body: DriveItemReaction): Response<DriveItemReactionResponse>
    @GET("drive/{id}/reactions")
    suspend fun getDriveReactions(@Path("id") itemId: Int): Response<DriveItemReactionsListResponse>
    @POST("drive/{id}/favorite")
    suspend fun addFavorite(@Path("id") id: Int): Response<GenericResponse>
    @DELETE("drive/{id}/favorite")
    suspend fun removeFavorite(@Path("id") id: Int): Response<GenericResponse>
    @GET("drive/changes")
    suspend fun getDriveChanges(@Query("since") lastSync: String? = null): Response<DriveSyncResponse>
    @POST("notify/{type}")
    suspend fun sendNotification(@Path("type") type: String, @Body body: NotificationRequest): Response<NotificationResponse>
    @POST("notify/partner")
    suspend fun sendNotificationPartner(@Body request: PartnerNotificationRequest): Response<NotificationResponse>
    @Multipart @POST
    suspend fun uploadFile(@Url url: String, @Part file: MultipartBody.Part): Response<FileUploadResponse>
    @GET("app-version")
    suspend fun getAppVersion(): Response<AppVersionResponse>
}