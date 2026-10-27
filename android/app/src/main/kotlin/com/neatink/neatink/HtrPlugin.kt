package com.neatink.neatink

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.nio.FloatBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import org.json.JSONObject

/**
 * Offline word recognition with ONNX Runtime, driven from Dart over the
 * `neatink/htr` MethodChannel (see `lib/recognition/htr_channel.dart`, which
 * is the other half of this protocol; change both together).
 *
 * The model is the IAM-trained SimpleHTR network (docs/htr-model-notes.md):
 * input `image` [N, 1, 32, 128] float, output `log_probs` [T, N, 79] float
 * (log-softmax, time first, blank = last class).
 *
 * | Dart -> Kotlin | arguments                     | reply                          |
 * |----------------|-------------------------------|--------------------------------|
 * | `recognize`    | images: List<Uint8List>       | List<Float32List>, one per image |
 * | `info`         | none                          | {classes, timesteps, blank, charset, width, height} |
 *
 * Each image is 4096 bytes: 32 rows x 128 columns, row-major, 0..255 with
 * white = 255 and ink dark. The reply for an image is a flat Float32List of
 * length `timesteps * classes`, row-major as [t][class] (log-probabilities).
 *
 * Every call runs on one background thread, in arrival order, and the reply
 * is posted to the main thread. The OrtSession is created lazily from the
 * Flutter asset on the first call and closed when the engine detaches.
 * Failures are `PlatformException`s whose code is one of `bad_image`,
 * `model_missing`, `model_unreadable`, `out_of_memory` or `htr_failed`.
 */
class HtrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "neatink-htr")
    }

    // Touched only from the executor thread.
    private var environment: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var inputName = "image"
    private var charset: List<String> = emptyList()
    private var classes = DEFAULT_CLASSES
    private var timesteps = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
        // Queued behind any inference that is still running.
        executor.execute { closeSession() }
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            executor.execute {
                try {
                    val value: Any? = when (call.method) {
                        "recognize" -> recognize(call.arguments)
                        "info" -> info()
                        else -> NOT_IMPLEMENTED
                    }
                    main.post {
                        if (value === NOT_IMPLEMENTED) result.notImplemented() else result.success(value)
                    }
                } catch (t: Throwable) {
                    val error = classify(t)
                    main.post { result.error(error.code, error.message, null) }
                }
            }
        } catch (e: RejectedExecutionException) {
            result.error("htr_failed", "The recognizer is shutting down.", null)
        }
    }

    // --- Protocol ----------------------------------------------------------

    private fun recognize(arguments: Any?): List<FloatArray> {
        val images = (arguments as? Map<*, *>)?.get("images") as? List<*>
            ?: throw HtrError("bad_image", "images is missing.")
        val pixels = images.mapIndexed { i, any ->
            val bytes = any as? ByteArray
            if (bytes == null || bytes.size != IMAGE_BYTES) {
                throw HtrError("bad_image", "Image $i must be $IMAGE_BYTES bytes (${WIDTH}x$HEIGHT grayscale).")
            }
            bytes
        }
        if (pixels.isEmpty()) return emptyList()
        val s = ensureSession()
        val env = environment!!

        val out = ArrayList<FloatArray>(pixels.size)
        var start = 0
        while (start < pixels.size) {
            val n = minOf(MAX_BATCH, pixels.size - start)
            val input = FloatBuffer.allocate(n * IMAGE_BYTES)
            for (k in 0 until n) {
                val bytes = pixels[start + k]
                for (b in bytes) input.put((b.toInt() and 0xFF) / 255f - 0.5f)
            }
            input.rewind()
            OnnxTensor.createTensor(env, input, longArrayOf(n.toLong(), 1, HEIGHT.toLong(), WIDTH.toLong())).use { tensor ->
                s.run(mapOf(inputName to tensor)).use { res ->
                    @Suppress("UNCHECKED_CAST")
                    val logProbs = res[0].value as Array<Array<FloatArray>> // [T][N][C]
                    timesteps = logProbs.size
                    for (k in 0 until n) {
                        val flat = FloatArray(logProbs.size * classes)
                        for (t in logProbs.indices) {
                            System.arraycopy(logProbs[t][k], 0, flat, t * classes, classes)
                        }
                        out.add(flat)
                    }
                }
            }
            start += n
        }
        return out
    }

    private fun info(): Map<String, Any> {
        ensureSession()
        if (timesteps == 0) {
            // One blank page reveals the (fixed) number of timesteps.
            val white = ByteArray(IMAGE_BYTES) { 0xFF.toByte() }
            recognize(mapOf("images" to listOf(white)))
        }
        return mapOf(
            "classes" to classes,
            "timesteps" to timesteps,
            "blank" to classes - 1,
            "charset" to charset,
            "width" to WIDTH,
            "height" to HEIGHT,
        )
    }

    // --- Session -----------------------------------------------------------

    private fun ensureSession(): OrtSession {
        session?.let { return it }
        val context = appContext ?: throw HtrError("htr_failed", "The recognizer is shut down.")
        val assets = context.assets
        val modelBytes = try {
            assets.open("$ASSET_DIR/model.onnx").use { it.readBytes() }
        } catch (e: java.io.FileNotFoundException) {
            throw HtrError("model_missing", "The handwriting model is not bundled with the app.")
        } catch (e: IOException) {
            throw HtrError("model_unreadable", e.message ?: "Cannot read the handwriting model.")
        }
        try {
            val config = JSONObject(assets.open("$ASSET_DIR/config.json").use { String(it.readBytes(), Charsets.UTF_8) })
            val chars = config.getJSONArray("charset")
            charset = List(chars.length()) { chars.getString(it) }
            classes = config.optInt("num_classes", charset.size + 1)
        } catch (e: Exception) {
            throw HtrError("model_unreadable", "Cannot read the handwriting model configuration.")
        }
        val env = OrtEnvironment.getEnvironment()
        val options = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(INTRA_OP_THREADS)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
        }
        try {
            val created = env.createSession(modelBytes, options)
            inputName = created.inputNames.firstOrNull() ?: inputName
            environment = env
            session = created
            return created
        } finally {
            options.close()
        }
    }

    private fun closeSession() {
        try {
            session?.close()
        } catch (_: Throwable) {
        }
        session = null
        // The OrtEnvironment is process-wide and shared; leave it open.
        environment = null
    }

    // --- Errors ------------------------------------------------------------

    private class HtrError(val code: String, message: String) : Exception(message)

    private class Classified(val code: String, val message: String)

    private fun classify(t: Throwable): Classified = when (t) {
        is HtrError -> Classified(t.code, t.message ?: "Handwriting recognition failed.")
        is OutOfMemoryError -> {
            closeSession()
            Classified("out_of_memory", "Not enough memory to recognise handwriting.")
        }
        else -> Classified("htr_failed", t.message ?: t.javaClass.simpleName)
    }

    private companion object {
        const val CHANNEL = "neatink/htr"
        const val ASSET_DIR = "flutter_assets/assets/htr"
        const val WIDTH = 128
        const val HEIGHT = 32
        const val IMAGE_BYTES = WIDTH * HEIGHT
        const val DEFAULT_CLASSES = 79
        const val MAX_BATCH = 16
        const val INTRA_OP_THREADS = 2
        val NOT_IMPLEMENTED = Any()
    }
}
