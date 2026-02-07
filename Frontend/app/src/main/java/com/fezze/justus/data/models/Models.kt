package com.fezze.justus.data.models
data class GenericResponse(val success: Boolean, val error: String?)
data class LoginResponse(
    val success: Boolean,
    val message: String? = null,
    val accessToken: String? = null,
    val refreshToken: String? = null,
    val user: User? = null,
    val error: String? = null
)
data class User(
    val id: Int,
    val username: String,
    val code: String,
    val email: String?,
    val bio: String?,
    val profile_pic_url: String?
)
data class ProfileResponse(
    val success: Boolean,
    val profile: User?,
    val message: String? = null,
    val error: String? = null
)
data class UpdateProfileRequest(val bio: String?)
data class ChangePasswordRequest(val oldPassword: String, val newPassword: String)
data class LoginRequestBody(
    val usernameWithCode: String,
    val password: String,
    val deviceToken: String
)
data class RegisterRequestBody(
    val username: String,
    val password: String,
    val email: String? = null,
    val deviceToken: String
)
data class RegisterResponse(
    val success: Boolean,
    val message: String? = null,
    val user: User? = null,
    val error: String? = null
)
data class RequestCodesBody( val username: String, val password: String)
data class RequestCodesResponse(val ok: Boolean, val codes: List<String>? = null, val msg: String? = null)
data class UpdateTokenRequest(val usernameWithCode: String, val deviceToken: String)
data class UpdateTokenResponse(val success: Boolean, val error: String? = null)
data class RefreshRequest(val refreshToken: String)
data class RefreshResponse(val success: Boolean, val accessToken: String? = null, val refreshToken: String? = null)
data class PartnershipResponse(
    val success: Boolean,
    val partner: User? = null,
    val pendingRequests: PendingRequests? = null,
    val message: String? = null,
    val error: String? = null
) { fun hasAcceptedPartner(): Boolean = partner != null }
data class PendingRequests(val received: List<User> = emptyList(), val sent: List<User> = emptyList())
data class PartnerRequestBody( val partner_username: String, val partner_code: String)
data class SearchPartnerResponse(val success: Boolean, val users: List<User>)
data class AcceptRequestBody(val requester_id: Int)
data class MissYouResponse(val success: Boolean, val total: Int)
data class MoodResponse(val success: Boolean,val emoji: String?)
data class MoodRequest(val emoji: String)
data class EmojiResponse(val emojis: List<String>)
data class BucketItem(
    val id: Int,
    val text: String,
    val done: Int,
    val created_at: String
)
data class BucketListResponse(val success: Boolean,val items: List<BucketItem>)
data class AddBucketRequest(val text: String)
data class GameAnswerRequest(val questionId: Int, val votedFor: String /*"A" o "B"*/)
data class GameStatsResponse(val success: Boolean, val totalMatches: Int)
data class GameNewQuestionResponse(
    val success: Boolean,
    val id: Int,
    val question: String,
    val optionA: String, // username A
    val optionB: String, // username B
    val status: String? = null,   // "pending" o "waiting"
    val message: String? = null   // messaggio tipo "Aspetta che l'altro risponda"
)
data class DriveItem(
    val id: Int,
    val type: String,
    val content: String,
    val metadata: Map<String, String>?,
    val reactions: List<String> = emptyList(),
    val created_at: String,
    val updated_at: String,
    val is_favorite: Int // 0 o 1
)
data class DriveItemRequest(
    val type: String,
    val content: String?,
    val metadata: Map<String, Any>?
)
data class DriveListResponse(val success: Boolean, val items: List<DriveItem>)
data class DriveSingleResponse(val success: Boolean, val item: DriveItem)
data class FileUploadResponse(
    val success: Boolean,
    val url: String,
    val originalName: String?,
    val size: Long?,
    val mime: String?
)
data class DriveChange(
    val id: Int,
    val action: String, // "create", "update", "delete"
    val item: DriveItem? = null
)
data class DriveSyncResponse(
    val success: Boolean,
    val changes: List<DriveChange>,
    val lastSync: String
)
data class DriveItemReaction(val emoji: String)
data class DriveItemReactionCount(val emoji: String, val total: Int)
data class DriveItemReactionResponse(val success: Boolean, val counts: List<DriveItemReactionCount>)
data class DriveItemReactionsListResponse(val success: Boolean, val reactions: List<DriveItemReaction>)
data class NotificationRequest(
    val receiverId: Int,
    val title: String,
    val body: String
)
data class PartnerNotificationRequest(
    val type: String,
    val username: String,
    val code: String,
    val title: String,
    val body: String
)
data class NotificationResponse(
    val success: Boolean,
    val message: String? = null,
    val error: String? = null
)
data class AppVersionResponse(
    val version: String,
    val apk_url: String,
    val changelog: String
)