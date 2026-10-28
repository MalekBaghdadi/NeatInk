package com.neatink.neatink

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import org.json.JSONObject

/**
 * Offline handwriting recognition (whole lines) with ONNX Runtime, driven from Dart over the
 * `neatink/htr` MethodChannel (see `lib/recognition/htr_channel.dart`, which
 * is the other half of this protocol; change both together).
 *
 * The model is PaddleOCR's PP-OCRv5 English mobile text recogniser
 * (docs/htr-model-notes.md): input `x` float32 [N, 3, 48, W] with N and W
 * dynamic, output float32 [N, T, 438] softmax probabilities (not log), where
 * class 0 is the CTC blank, classes 1..436 the characters of the model's
 * dictionary and class 437 the space. T is about W / 8.
 *
 * | Dart -> Kotlin | arguments                             | reply                         |
 * |----------------|---------------------------------------|-------------------------------|
 * | `recognize`    | {images: List<Map>}                   | List<Map>, one per image      |
 * | `info`         | none                                  | Map (model facts)             |
 *
 * `recognize` image map: `width` Int (16..2400), `height` Int (must be 48) and
 * `pixels` Uint8List/ByteArray of `width * height` bytes, row-major, 0..255,
 * white paper = 255, dark ink = low. The images are sent as they are (the
 * width follows the aspect ratio of the line or word, up to 2400 px for a
 * whole line): each image is **one** ORT call, no batching and no padding,
 * because padding changes what the model reads.
 * Kotlin turns a pixel v into (v / 255 - 0.5) / 0.5 and copies it to the
 * three channels.
 *
 * `recognize` reply item: `{timesteps: Int T, classes: Int C, probs:
 * Float32List}` where `probs` has `T * C` values, row-major `[t][class]`.
 *
 * `info` reply: `{classes, blank, charsetSize, inputHeight, minWidth,
 * maxWidth, inputName}`.
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
    private var inputName = "x"
    private var classes = DEFAULT_CLASSES
    private var blank = 0
    private var charsetSize = 0

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

    private class WordInput(val width: Int, val pixels: ByteArray)

    private fun recognize(arguments: Any?): List<Map<String, Any>> {
        val images = (arguments as? Map<*, *>)?.get("images") as? List<*>
            ?: throw HtrError("bad_image", "images is missing.")
        // Validate everything first, so a bad image fails the call before any work.
        val inputs = images.mapIndexed { i, any -> parseImage(i, any) }
        if (inputs.isEmpty()) return emptyList()
        val s = ensureSession()
        val env = environment!!
        return inputs.map { runOne(env, s, it) }
    }

    private fun parseImage(index: Int, any: Any?): WordInput {
        val map = any as? Map<*, *>
            ?: throw HtrError("bad_image", "Image $index must be a map {width, height, pixels}.")
        val width = (map["width"] as? Number)?.toInt()
        val height = (map["height"] as? Number)?.toInt()
        val pixels = map["pixels"] as? ByteArray
        if (width == null || height == null || pixels == null) {
            throw HtrError("bad_image", "Image $index needs width, height and pixels.")
        }
        if (height != HEIGHT) {
            throw HtrError("bad_image", "Image $index must be $HEIGHT pixels high, not $height.")
        }
        if (width < MIN_WIDTH || width > MAX_WIDTH) {
            throw HtrError("bad_image", "Image $index must be $MIN_WIDTH..$MAX_WIDTH pixels wide, not $width.")
        }
        if (pixels.size != width * height) {
            throw HtrError("bad_image", "Image $index has ${pixels.size} bytes, expected ${width * height}.")
        }
        return WordInput(width, pixels)
    }

    /** One image through the network: [1, 3, 48, W] in, [1, T, C] out. */
    private fun runOne(env: OrtEnvironment, s: OrtSession, image: WordInput): Map<String, Any> {
        val plane = HEIGHT * image.width
        // A direct buffer is handed to ONNX Runtime without another copy.
        val input = ByteBuffer.allocateDirect(3 * plane * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        val gray = FloatArray(plane)
        for (k in 0 until plane) {
            gray[k] = ((image.pixels[k].toInt() and 0xFF) / 255f - 0.5f) / 0.5f
        }
        repeat(3) { input.put(gray) } // the grey image goes into all three channels
        input.rewind()
        val shape = longArrayOf(1, 3, HEIGHT.toLong(), image.width.toLong())
        return OnnxTensor.createTensor(env, input, shape).use { tensor ->
            s.run(mapOf(inputName to tensor)).use { res ->
                val out = res[0] as OnnxTensor
                val outShape = out.info.shape // [1, T, C]
                if (outShape.size != 3 || outShape[2].toInt() != classes) {
                    throw HtrError("htr_failed", "Unexpected model output shape ${outShape.contentToString()}.")
                }
                val steps = outShape[1].toInt()
                val buffer = out.floatBuffer
                val probs = FloatArray(buffer.remaining())
                buffer.get(probs)
                if (probs.size != steps * classes) {
                    throw HtrError("htr_failed", "Model output has ${probs.size} values, expected ${steps * classes}.")
                }
                mapOf<String, Any>("timesteps" to steps, "classes" to classes, "probs" to probs)
            }
        }
    }

    private fun info(): Map<String, Any> {
        ensureSession()
        return mapOf(
            "classes" to classes,
            "blank" to blank,
            "charsetSize" to charsetSize,
            "inputHeight" to HEIGHT,
            "minWidth" to MIN_WIDTH,
            "maxWidth" to MAX_WIDTH,
            "inputName" to inputName,
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
            val table = JSONObject(assets.open("$ASSET_DIR/charset.json").use { String(it.readBytes(), Charsets.UTF_8) })
            charsetSize = table.getJSONArray("charset").length()
            blank = table.optInt("blank", 0)
        } catch (e: Exception) {
            throw HtrError("model_unreadable", "Cannot read the handwriting model's character table.")
        }
        val env = OrtEnvironment.getEnvironment()
        val options = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(INTRA_OP_THREADS)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
        }
        try {
            val created = env.createSession(modelBytes, options)
            try {
                inputName = created.inputNames.firstOrNull() ?: inputName
                val outputShape = (created.outputInfo.values.firstOrNull()?.info as? TensorInfo)?.shape
                classes = outputShape?.lastOrNull()?.takeIf { it > 0 }?.toInt() ?: charsetSize
                if (classes != charsetSize) {
                    throw HtrError(
                        "model_unreadable",
                        "The model has $classes classes but its character table has $charsetSize.",
                    )
                }
            } catch (t: Throwable) {
                created.close()
                throw t
            }
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
        const val HEIGHT = 48
        const val MIN_WIDTH = 16
        const val MAX_WIDTH = 2400
        const val DEFAULT_CLASSES = 438
        const val INTRA_OP_THREADS = 2
        val NOT_IMPLEMENTED = Any()
    }
}
