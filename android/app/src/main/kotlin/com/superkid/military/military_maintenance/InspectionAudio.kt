package com.superkid.military.military_maintenance

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

internal class InspectionAudio(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val limit = Runnable { finish(save = true) }
    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null
    private var request: MethodChannel.Result? = null
    private var destination: File? = null
    private var attachmentPath: String? = null
    private var temporary: File? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "record" -> {
                    val path = requireNotNull(call.argument<String>("path"))
                    record(privateFile(path, ".jpg"), "$path.m4a", result)
                }
                "finish" -> { finish(save = true); result.success(null) }
                "cancel" -> { finish(save = false); stopPlayback(); result.success(null) }
                "stopPlayback" -> { stopPlayback(); result.success(null) }
                "play" -> { play(privateFile(call.argument<String>("path"), ".m4a")); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("audio_failed", null, null)
        }
    }

    private fun privateFile(path: String?, suffix: String): File {
        val file = File(requireNotNull(path)).canonicalFile
        val root = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
        require(file.path.startsWith(root) && file.name.endsWith(suffix) && file.isFile)
        return file
    }

    private fun record(image: File, path: String, result: MethodChannel.Result) {
        if (request != null) {
            result.error("busy", null, null)
            return
        }
        stopPlayback()
        destination = File(image.path + ".m4a")
        attachmentPath = path
        request = result
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            start()
        } else {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
        }
    }

    fun onPermission(granted: Boolean) {
        if (request == null) return
        if (granted) start() else finish(save = false, error = "permission")
    }

    @Suppress("DEPRECATION")
    private fun start() {
        try {
            val file = File.createTempFile("inspection-audio-", ".partial", destination!!.parentFile)
            temporary = file
            val active = MediaRecorder()
            recorder = active
            active.setAudioSource(MediaRecorder.AudioSource.MIC)
            active.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            active.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            active.setAudioChannels(1)
            active.setAudioSamplingRate(16000)
            active.setAudioEncodingBitRate(48000)
            active.setOutputFile(file.path)
            active.setOnErrorListener { _, _, _ -> finish(save = false, error = "audio_failed") }
            active.prepare()
            active.start()
            handler.postDelayed(limit, 15000)
        } catch (_: Exception) {
            finish(save = false, error = "audio_failed")
        }
    }

    private fun finish(save: Boolean, error: String? = null) {
        handler.removeCallbacks(limit)
        val active = recorder
        recorder = null
        val stopped = active != null && save && runCatching { active.stop() }.isSuccess
        runCatching { active?.release() }
        val file = temporary
        val target = destination
        val path = attachmentPath
        attachmentPath = null
        temporary = null
        destination = null
        val result = request
        request = null
        val saved = stopped && target != null && file != null && file.length() > 0 &&
            file.length() <= 256 * 1024 && file.renameTo(target)
        file?.delete()
        when {
            error != null -> result?.error(error, null, null)
            saved -> result?.success(path)
            save -> result?.error("audio_failed", null, null)
            else -> result?.success(null)
        }
    }

    private fun play(file: File) {
        require(request == null)
        stopPlayback()
        val active = MediaPlayer()
        player = active
        try {
            active.setDataSource(file.path)
            active.setOnPreparedListener { if (player === it) it.start() }
            active.setOnCompletionListener { if (player === it) stopPlayback() }
            active.setOnErrorListener { media, _, _ ->
                if (player === media) stopPlayback()
                true
            }
            active.prepareAsync()
        } catch (error: Exception) {
            stopPlayback()
            throw error
        }
    }

    private fun stopPlayback() {
        val active = player
        player = null
        runCatching { active?.release() }
    }

    fun close() {
        finish(save = false)
        stopPlayback()
    }

    companion object {
        const val REQUEST = 894
    }
}
