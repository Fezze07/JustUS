# GENERALE
####################################
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn org.jspecify.nullness.Nullable

# MODEL APP
####################################
-keep class com.fezze.justus.** { *; }

# RETROFIT / OKHTTP
####################################
-keep class retrofit2.Retrofit { *; }
-keep class retrofit2.http.** { *; }
-keep class okhttp3.OkHttpClient { *; }

# FIREBASE
####################################
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.**

# COROUTINES
####################################
-dontwarn kotlinx.coroutines.**

# VIEW BINDING
####################################
-keep class **Binding { *; }