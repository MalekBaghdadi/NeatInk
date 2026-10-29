package com.neatink.neatink

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.PlaybackParams
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * Lecture recordings (v1.12.0): records the microphone to an AAC file while the user writes, and
 * plays recordings back. Everything stays on the device. The Dart half is `lib/audio/audio_channel.dart`.
 *
 * Recording runs in [RecordingService], a foreground service of type microphone, so it goes on
 * when the user leaves the app or the screen turns off (Android silences the microphone of
 * background apps otherwise). The file is an ADTS AAC stream (`.aac`): it stays playable up to
 * the last second written even if the app is killed mid-lecture, which an MP4 file would not.
 *
 * | Dart -> Kotlin     | arguments        | reply                                            |
 * |--------------------|------------------|--------------------------------------------------|
 * | `permission`       | {ask: bool}      | true when the microphone may be used             |
 * | `startRecording`   | {path}           | null                                             |
 * | `pauseRecording`   |                  | null                                             |
 * | `resumeRecording`  |                  | null                                             |
 * | `stopRecording`    |                  | null                                             |
 * | `recorderStatus`   |                  | {state: idle/recording/paused, level: 0..1}      |
 * | `load`             | {path}           | duration in ms                                   |
 * | `play` / `pause`   |                  | null                                             |
 * | `seek`             | {ms}             | null                                             |
 * | `speed`            | {speed}          | null                                             |
 * | `playerStatus`     |                  | {position, duration, playing, completed}         |
 * | `release`          |                  | null                                             |
 *
 * Failures are `PlatformException`s with code `bad_args`, `no_permission`, `record_failed` or
 * `play_failed` and a message the app can show.
 */
class AudioPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    private var player: MediaPlayer? = null
    private var completed = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        releasePlayer()
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "permission" -> permission(call.argument<Boolean>("ask") == true, result)
                "startRecording" -> startRecording(call, result)
                "pauseRecording" -> { Recorder.pause(); result.success(null) }
                "resumeRecording" -> { Recorder.resume(); result.success(null) }
                "stopRecording" -> { stopRecording(); result.success(null) }
                "recorderStatus" -> result.success(
                    mapOf("state" to Recorder.state, "level" to Recorder.level())
                )
                "load" -> load(call, result)
                "play" -> { player?.start(); completed = false; result.success(null) }
                "pause" -> { player?.let { if (it.isPlaying) it.pause() }; result.success(null) }
                "seek" -> seek(call, result)
                "speed" -> speed(call, result)
                "playerStatus" -> result.success(playerStatus())
                "release" -> { releasePlayer(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            val code = if (call.method.contains("ecord")) "record_failed" else "play_failed"
            result.error(code, e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Permission

    private fun hasMicrophone(): Boolean =
        context?.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun permission(ask: Boolean, result: MethodChannel.Result) {
        if (hasMicrophone() || !ask) {
            result.success(hasMicrophone())
            return
        }
        val activity: Activity? = activityBinding?.activity
        if (activity == null || pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        val wanted = mutableListOf(Manifest.permission.RECORD_AUDIO)
        // The "Recording" notification needs this on Android 13 and later (without it the
        // recording still works, the notification is just not shown).
        if (Build.VERSION.SDK_INT >= 33) wanted.add(Manifest.permission.POST_NOTIFICATIONS)
        activity.requestPermissions(wanted.toTypedArray(), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        result.success(hasMicrophone())
        return true
    }

    // ---------------------------------------------------------------------------------------------
    // Recording

    private fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val ctx = context
        if (path == null || ctx == null) {
            result.error("bad_args", "No file to record to.", null)
            return
        }
        if (!hasMicrophone()) {
            result.error("no_permission", "The app may not use the microphone.", null)
            return
        }
        File(path).parentFile?.mkdirs()
        // The service goes to the foreground first: Android lets a foreground service of type
        // microphone keep recording when the app is in the background.
        val intent = Intent(ctx, RecordingService::class.java)
        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(intent) else ctx.startService(intent)
        try {
            Recorder.start(ctx, path)
        } catch (e: Exception) {
            ctx.stopService(intent)
            throw e
        }
        result.success(null)
    }

    private fun stopRecording() {
        Recorder.stop()
        context?.let { it.stopService(Intent(it, RecordingService::class.java)) }
    }

    // ---------------------------------------------------------------------------------------------
    // Playback

    private fun load(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null || !File(path).exists()) {
            result.error("bad_args", "The recording file is missing.", null)
            return
        }
        releasePlayer()
        val p = MediaPlayer()
        p.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        p.setDataSource(path)
        p.setOnCompletionListener { completed = true }
        p.prepare()
        player = p
        completed = false
        result.success(p.duration)
    }

    private fun seek(call: MethodCall, result: MethodChannel.Result) {
        val ms = (call.argument<Number>("ms") ?: 0).toInt()
        val p = player
        if (p != null) {
            if (Build.VERSION.SDK_INT >= 26) {
                p.seekTo(ms.toLong(), MediaPlayer.SEEK_CLOSEST)
            } else {
                p.seekTo(ms)
            }
            completed = false
        }
        result.success(null)
    }

    private fun speed(call: MethodCall, result: MethodChannel.Result) {
        val speed = (call.argument<Number>("speed") ?: 1.0).toFloat()
        val p = player
        if (p != null) {
            val wasPlaying = p.isPlaying
            // Setting the speed starts a paused player; keep it paused.
            p.playbackParams = (p.playbackParams ?: PlaybackParams()).setSpeed(speed)
            if (!wasPlaying && p.isPlaying) p.pause()
        }
        result.success(null)
    }

    private fun playerStatus(): Map<String, Any> {
        val p = player ?: return mapOf("position" to 0, "duration" to 0, "playing" to false, "completed" to false)
        return mapOf(
            "position" to p.currentPosition,
            "duration" to p.duration,
            "playing" to p.isPlaying,
            "completed" to completed,
        )
    }

    private fun releasePlayer() {
        player?.release()
        player = null
        completed = false
    }

    companion object {
        const val CHANNEL = "neatink/audio"
        private const val REQUEST_CODE = 4711
    }
}

/**
 * The one microphone recorder of the app (a recording outlives the screen that started it).
 * 64 kbit/s mono AAC: about 29 MB per hour, clear enough for a lecture hall.
 */
object Recorder {
    private var recorder: MediaRecorder? = null
    private var paused = false

    val state: String
        @Synchronized get() = when {
            recorder == null -> "idle"
            paused -> "paused"
            else -> "recording"
        }

    @Synchronized
    fun start(context: Context, path: String) {
        stop()
        @Suppress("DEPRECATION")
        val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
        try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.AAC_ADTS)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioSamplingRate(44100)
            r.setAudioEncodingBitRate(64000)
            r.setOutputFile(path)
            r.prepare()
            r.start()
        } catch (e: Exception) {
            r.release()
            throw e
        }
        recorder = r
        paused = false
    }

    @Synchronized
    fun pause() {
        val r = recorder ?: return
        if (!paused) {
            r.pause()
            paused = true
        }
    }

    @Synchronized
    fun resume() {
        val r = recorder ?: return
        if (paused) {
            r.resume()
            paused = false
        }
    }

    @Synchronized
    fun stop() {
        val r = recorder ?: return
        recorder = null
        paused = false
        try {
            r.stop()
        } catch (_: RuntimeException) {
            // Stopped right after starting: nothing was written. The file is still valid ADTS.
        } finally {
            r.release()
        }
    }

    /** How loud the microphone is now, 0..1 (for the level meter). */
    @Synchronized
    fun level(): Double {
        val r = recorder ?: return 0.0
        if (paused) return 0.0
        return try {
            (r.maxAmplitude / 32767.0).coerceIn(0.0, 1.0)
        } catch (_: RuntimeException) {
            0.0
        }
    }
}
