package com.fezze.justus

import android.app.Application
import android.content.Context
class JustusApp : Application() {
    companion object {
        lateinit var appContext: Context
            private set
    }
    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
    }
}
