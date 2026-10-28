package com.neatink.neatink

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Saves a copy of a local file where the user chooses, with the system "Save to" dialog
 * (Storage Access Framework, `ACTION_CREATE_DOCUMENT`; no storage permission). Unlike
 * file_picker's `saveFile`, the file is streamed from its path, so a backup of hundreds of
 * megabytes never has to fit in memory. The Dart half is `lib/features/settings/backup_service.dart`.
 *
 * | Dart -> Kotlin | arguments                          | reply                              |
 * |----------------|------------------------------------|------------------------------------|
 * | `saveCopy`     | {path, fileName, mimeType}         | true when saved, false if cancelled |
 *
 * Failures are `PlatformException`s with code `bad_args`, `busy` or `save_failed`. A copy that
 * fails halfway deletes the half-written document.
 */
class FileSavePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "neatink-file-save")
    }

    /** The save waiting for the user's choice in the system dialog. */
    private var pending: Pending? = null

    private class Pending(val source: File, val result: MethodChannel.Result)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveCopy" -> saveCopy(call, result)
            else -> result.notImplemented()
        }
    }

    private fun saveCopy(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (path == null || fileName == null) {
            result.error("bad_args", "path and fileName are required", null)
            return
        }
        val source = File(path)
        if (!source.isFile) {
            result.error("save_failed", "The file to save does not exist", null)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("save_failed", "The app is not in the foreground", null)
            return
        }
        if (pending != null) {
            result.error("busy", "Another save is waiting for the user", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        pending = Pending(source, result)
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Exception) {
            pending = null
            result.error("save_failed", e.message ?: "No app can save files", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val p = pending ?: return true
        pending = null
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            p.result.success(false)
            return true
        }
        val resolver = activityBinding?.activity?.contentResolver
        if (resolver == null) {
            p.result.error("save_failed", "The app is not in the foreground", null)
            return true
        }
        executor.execute {
            try {
                // A new document is empty, so plain "w" needs no truncation.
                val out = resolver.openOutputStream(uri, "w")
                    ?: throw IOException("The chosen place cannot be written to")
                out.use { o -> p.source.inputStream().use { it.copyTo(o, 1 shl 20) } }
                main.post { p.result.success(true) }
            } catch (e: Exception) {
                try {
                    DocumentsContract.deleteDocument(resolver, uri)
                } catch (_: Exception) {
                    // Nothing more to do: the error below tells the user.
                }
                main.post { p.result.error("save_failed", e.message ?: e.toString(), null) }
            }
        }
        return true
    }

    companion object {
        const val CHANNEL = "neatink/file_save"
        private const val REQUEST_CODE = 0x4E49
    }
}
