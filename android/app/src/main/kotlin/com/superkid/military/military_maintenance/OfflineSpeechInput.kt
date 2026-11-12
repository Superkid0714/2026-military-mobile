package com.superkid.military.military_maintenance

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel

internal class OfflineSpeechInput(private val activity: Activity) {
    private var recognizer: SpeechRecognizer? = null
    private var pending: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finish(error = "no_speech") }

    fun start(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", null, null)
            return
        }
        val available = Build.VERSION.SDK_INT >= 31 && runCatching {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        }.getOrDefault(false)
        if (!available) {
            result.error("unavailable", null, null)
            return
        }
        pending = result
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
        } else {
            listen()
        }
    }

    fun onPermission(granted: Boolean) {
        if (pending == null) return
        if (granted) listen() else finish(error = "permission")
    }

    private fun listen() {
        if (Build.VERSION.SDK_INT < 31) {
            finish(error = "unavailable")
            return
        }
        try {
            val instance = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            recognizer = instance
            instance.setRecognitionListener(object : RecognitionListener {
                override fun onResults(results: Bundle?) {
                    if (recognizer !== instance) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()?.trim()
                    if (text.isNullOrEmpty()) finish(error = "no_speech") else finish(text)
                }

                override fun onError(error: Int) {
                    if (recognizer !== instance) return
                    finish(error = when (error) {
                        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "unavailable"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
                        else -> "no_speech"
                    })
                }

                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            handler.postDelayed(timeout, 20000)
            instance.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            })
        } catch (_: Exception) {
            finish(error = "unavailable")
        }
    }

    fun cancel() = finish()

    private fun finish(text: String? = null, error: String? = null) {
        handler.removeCallbacks(timeout)
        val active = recognizer
        recognizer = null
        runCatching { active?.destroy() }
        val result = pending
        pending = null
        if (error == null) result?.success(text) else result?.error(error, null, null)
    }

    companion object {
        const val REQUEST = 893
    }
}
