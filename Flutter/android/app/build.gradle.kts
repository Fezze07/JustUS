plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val requiredKeystoreKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
fun missingKeystoreKeys(): List<String> =
    requiredKeystoreKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.fezze.justus"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.fezze.justus"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists() && missingKeystoreKeys().isEmpty()) {
                keyAlias = keystoreProperties.getProperty("keyAlias").trim()
                keyPassword = keystoreProperties.getProperty("keyPassword").trim()
                storeFile = file(keystoreProperties.getProperty("storeFile").trim())
                storePassword = keystoreProperties.getProperty("storePassword").trim()
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val runsReleaseTask = allTasks.any { task ->
        task.project == project && task.name.contains("Release", ignoreCase = true)
    }
    if (runsReleaseTask) {
        if (!keystorePropertiesFile.exists()) {
            throw org.gradle.api.GradleException(
                "Missing Android release signing config: ${keystorePropertiesFile.absolutePath} not found. " +
                    "Release builds require a production keystore; debug signing fallback is disabled."
            )
        }
        val missing = missingKeystoreKeys()
        if (missing.isNotEmpty()) {
            throw org.gradle.api.GradleException(
                "Incomplete Android release signing config in ${keystorePropertiesFile.absolutePath}: " +
                    "missing ${missing.joinToString(", ")}."
            )
        }
        val storeFilePath = keystoreProperties.getProperty("storeFile").trim()
        val resolvedStoreFile = file(storeFilePath)
        if (!resolvedStoreFile.isFile) {
            throw org.gradle.api.GradleException(
                "Android release keystore file not found at ${resolvedStoreFile.absolutePath}."
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}


flutter {
    source = "../.."
}
