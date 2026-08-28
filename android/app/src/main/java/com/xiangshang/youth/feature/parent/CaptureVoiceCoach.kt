package com.xiangshang.youth.feature.parent

import android.content.Context
import android.speech.tts.TextToSpeech
import androidx.camera.core.ExperimentalGetImage
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import java.util.Locale

@ExperimentalGetImage
internal class VoiceCoach(context: Context) : TextToSpeech.OnInitListener {
    private var ready = false
    private val engine = TextToSpeech(context, this)
    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        if (ready) engine.language = Locale.CHINA
    }

    fun say(message: String) {
        if (ready) engine.speak(message, TextToSpeech.QUEUE_FLUSH, null, "body-coach")
    }

    fun stop() {
        engine.stop()
    }

    fun close() {
        engine.stop()
        engine.shutdown()
    }
}

@Composable
internal fun rememberVoiceCoach(context: Context) = remember { VoiceCoach(context.applicationContext) }
