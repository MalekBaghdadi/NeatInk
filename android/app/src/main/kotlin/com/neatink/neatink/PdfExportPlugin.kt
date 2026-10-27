package com.neatink.neatink

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDDocumentInformation
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.font.PDFont
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.pdmodel.graphics.state.RenderingMode
import com.tom_roush.pdfbox.util.Matrix
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Vector PDF export with PdfBox-Android, driven from Dart over the
 * `neatink/pdf_export` MethodChannel (see `lib/pdf/pdf_exporter.dart`, which
 * is the other half of this protocol; change both together).
 *
 * | Dart -> Kotlin | arguments                                      | reply      |
 * |----------------|------------------------------------------------|------------|
 * | `begin`        | outputPath, sourcePdfPath?, title?, pageCount  | session id |
 * | `addPage`      | session, index, page (`ExportPage.toMap`)      | null       |
 * | `finish`       | session                                        | outputPath |
 * | `cancel`       | session                                        | null       |
 *
 * Kotlin -> Dart: `progress` {session, done, total} after each drawn page.
 *
 * Every call runs on one background thread, in the order it arrived, and the
 * reply (and the progress call) is posted to the main thread, so the UI never
 * blocks. Failures are `PlatformException`s whose code is one of
 * `source_missing`, `source_unreadable`, `out_of_memory`, `write_failed`,
 * `empty`, `bad_session`, `bad_page` or `export_failed`.
 *
 * Output pages are always built in a new document: PDF-backed pages are
 * copied in from the source with `importPage` (so reordered, repeated or
 * interleaved pages work, and their text stays selectable), blank pages are
 * created at the app's size. The ink is appended as filled paths.
 */
class PdfExportPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "neatink-pdf-export")
    }
    private val sessions = ConcurrentHashMap<Int, Session>()
    private val nextSession = AtomicInteger(1)

    /** Reads the bundled text-box fonts (Flutter assets); null when detached. */
    @Volatile
    private var fontAssets: FontAssets? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        initPdfBox(binding.applicationContext)
        fontAssets = FontAssets(binding.applicationContext, binding.flutterAssets)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        fontAssets = null
        // Frees native documents and partial files of exports the engine
        // abandoned; queued behind any page that is still being drawn.
        executor.execute { sessions.values.toList().forEach { dispose(it, deleteOutput = true) } }
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("export_failed", "Missing arguments for ${call.method}.", null)
            return
        }
        try {
            executor.execute {
                try {
                    val value: Any? = when (call.method) {
                        "begin" -> begin(args)
                        "addPage" -> addPage(args)
                        "finish" -> finish(args)
                        "cancel" -> cancel(args)
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
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            result.error("export_failed", "The exporter is shutting down.", null)
        }
    }

    // --- Protocol ----------------------------------------------------------

    private fun begin(args: Map<*, *>): Int {
        val outputPath = args["outputPath"] as? String
            ?: throw ExportError("export_failed", "outputPath is missing.")
        val sourcePath = args["sourcePdfPath"] as? String
        var source: PDDocument? = null
        var out: PDDocument? = null
        try {
            if (sourcePath != null) {
                val file = File(sourcePath)
                if (!file.isFile) throw ExportError("source_missing", "No file at $sourcePath.")
                source = try {
                    PDDocument.load(file, MemoryUsageSetting.setupMixed(SCRATCH_MEMORY_BYTES))
                } catch (e: IOException) {
                    throw ExportError("source_unreadable", e.message ?: "Cannot read $sourcePath.")
                }
            }
            out = PDDocument(MemoryUsageSetting.setupMixed(SCRATCH_MEMORY_BYTES))
            val id = nextSession.getAndIncrement()
            sessions[id] = Session(
                id = id,
                outputPath = outputPath,
                title = args["title"] as? String,
                pageCount = (args["pageCount"] as? Number)?.toInt() ?: 0,
                source = source,
                doc = out,
                fontAssets = fontAssets,
            )
            return id
        } catch (t: Throwable) {
            closeQuietly(out)
            closeQuietly(source)
            throw t
        }
    }

    private fun addPage(args: Map<*, *>): Any? {
        val s = session(args)
        val page = args["page"] as? Map<*, *>
            ?: throw ExportError("bad_page", "page is missing.")
        try {
            drawPage(s, page)
        } catch (t: Throwable) {
            // The Dart side cancels after a failure; dropping the partial
            // result right away frees memory sooner.
            dispose(s, deleteOutput = true)
            throw t
        }
        s.done++
        val progress = mapOf("session" to s.id, "done" to s.done, "total" to s.pageCount)
        main.post { channel?.invokeMethod("progress", progress) }
        return null
    }

    private fun finish(args: Map<*, *>): String {
        val s = session(args)
        try {
            if (s.doc.numberOfPages == 0) throw ExportError("empty", "There are no pages to export.")
            s.doc.documentInformation = PDDocumentInformation().apply {
                s.title?.let { title = it }
                producer = "NeatInk"
            }
            val target = File(s.outputPath)
            target.parentFile?.mkdirs()
            val part = File(s.outputPath + ".part")
            try {
                s.doc.save(part)
            } catch (e: IOException) {
                throw ExportError("write_failed", e.message ?: "Cannot write the PDF.")
            }
            // Atomic replace: the output either keeps its old content or
            // becomes the complete new file.
            if (!part.renameTo(target)) {
                target.delete()
                if (!part.renameTo(target)) {
                    throw ExportError("write_failed", "Cannot move the PDF to ${s.outputPath}.")
                }
            }
            dispose(s, deleteOutput = false)
            return s.outputPath
        } catch (t: Throwable) {
            dispose(s, deleteOutput = true)
            throw t
        }
    }

    private fun cancel(args: Map<*, *>): Any? {
        // Unknown sessions are fine: a failed addPage already disposed it.
        val id = (args["session"] as? Number)?.toInt() ?: return null
        sessions[id]?.let { dispose(it, deleteOutput = true) }
        return null
    }

    private fun session(args: Map<*, *>): Session {
        val id = (args["session"] as? Number)?.toInt()
        return id?.let { sessions[it] }
            ?: throw ExportError("bad_session", "Unknown export session $id.")
    }

    private fun dispose(s: Session, deleteOutput: Boolean) {
        sessions.remove(s.id)
        closeQuietly(s.doc)
        closeQuietly(s.source)
        s.images.clear()
        s.fonts.clear()
        s.typefaces.clear()
        if (deleteOutput) File(s.outputPath + ".part").delete()
    }

    // --- Drawing -----------------------------------------------------------

    private fun drawPage(s: Session, p: Map<*, *>) {
        val width = p.num("width", 595.0)
        val height = p.num("height", 842.0)
        val pdfIndex = (p["pdfPageIndex"] as? Number)?.toInt()

        val page: PDPage
        if (pdfIndex != null) {
            val source = s.source
                ?: throw ExportError("source_missing", "The notebook has no source PDF.")
            if (pdfIndex < 0 || pdfIndex >= source.numberOfPages) {
                throw ExportError("bad_page", "PDF page $pdfIndex does not exist.")
            }
            page = s.doc.importPage(source.getPage(pdfIndex))
        } else {
            page = PDPage(PDRectangle(width.toFloat(), height.toFloat()))
            s.doc.addPage(page)
        }

        val box = PdfCoords.visibleBox(page.mediaBox.toBox(), page.cropBox.toBox())
        // PdfBox's getRotation() normalises differently from PDFium; read the
        // raw value like the app does (importPage copied it onto the page).
        val turns = PdfCoords.quarterTurns(page.getCOSObject().getInt(COSName.ROTATE, 0))
        val m = PdfCoords.appToPdfMatrix(box, turns, width, height)

        PDPageContentStream(s.doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
            val d = Drawer(cs, s)
            // Everything below is in app coordinates (points, y down).
            cs.saveGraphicsState()
            cs.transform(Matrix(m[0].toFloat(), m[1].toFloat(), m[2].toFloat(), m[3].toFloat(), m[4].toFloat(), m[5].toFloat()))
            d.background(p, width, height)
            d.lines(p.list("lines"))
            d.dots(p)
            d.images(p.list("images"))
            d.polygons(p.list("highlighter"))
            d.textRects(p.list("textRects"))
            d.textLines(p.list("textLines"))
            d.polygons(p.list("ink"))
            d.resetAlpha()
            cs.restoreGraphicsState()
        }
    }

    /** Draws one page's layers into [cs], whose current matrix maps app space. */
    private class Drawer(val cs: PDPageContentStream, val s: Session) {
        private var fillAlpha = 1f
        private var strokeAlpha = 1f

        fun background(p: Map<*, *>, width: Double, height: Double) {
            val color = (p["background"] as? Number)?.toLong() ?: return
            if (alphaOf(color) == 0) return
            setFill(color)
            cs.addRect(0f, 0f, width.toFloat(), height.toFloat())
            cs.fill()
        }

        fun lines(list: List<Map<*, *>>) {
            for (l in list) {
                val color = (l["color"] as? Number)?.toLong() ?: continue
                setStroke(color)
                cs.setLineWidth(l.num("width", 1.0).toFloat())
                cs.moveTo(l.num("x1", 0.0).toFloat(), l.num("y1", 0.0).toFloat())
                cs.lineTo(l.num("x2", 0.0).toFloat(), l.num("y2", 0.0).toFloat())
                cs.stroke()
            }
        }

        fun dots(p: Map<*, *>) {
            val xy = floats(p["dots"])
            if (xy.size < 2) return
            val color = (p["dotColor"] as? Number)?.toLong() ?: return
            val r = p.num("dotRadius", 0.9).toFloat()
            val k = r * CIRCLE_K
            setFill(color)
            var i = 0
            while (i + 1 < xy.size) {
                val x = xy[i]
                val y = xy[i + 1]
                cs.moveTo(x + r, y)
                cs.curveTo(x + r, y + k, x + k, y + r, x, y + r)
                cs.curveTo(x - k, y + r, x - r, y + k, x - r, y)
                cs.curveTo(x - r, y - k, x - k, y - r, x, y - r)
                cs.curveTo(x + k, y - r, x + r, y - k, x + r, y)
                cs.closePath()
                i += 2
            }
            // One fill for all dots: a single path object stays small.
            cs.fill()
        }

        fun images(list: List<Map<*, *>>) {
            for (img in list) {
                val path = img["path"] as? String ?: continue
                val x = img.num("x", 0.0).toFloat()
                val y = img.num("y", 0.0).toFloat()
                val w = img.num("width", 0.0).toFloat()
                val h = img.num("height", 0.0).toFloat()
                if (w <= 0f || h <= 0f) continue
                val image = loadImage(path) ?: continue
                setAlphaOpaque()
                // Image space is the unit square with y up; app space is y down.
                cs.drawImage(image, Matrix(w, 0f, 0f, -h, x, y + h))
            }
        }

        fun polygons(list: List<Map<*, *>>) {
            for (poly in list) {
                val xy = floats(poly["xy"])
                if (xy.size < 6) continue
                setFill((poly["color"] as? Number)?.toLong() ?: continue)
                cs.moveTo(xy[0], xy[1])
                var i = 2
                while (i + 1 < xy.size) {
                    cs.lineTo(xy[i], xy[i + 1])
                    i += 2
                }
                cs.closePath()
                // Non-zero winding, like the screen painter, so
                // self-overlapping outlines fill the same way.
                cs.fill()
            }
        }

        fun textRects(list: List<Map<*, *>>) {
            for (r in list) {
                val color = (r["color"] as? Number)?.toLong() ?: continue
                if (alphaOf(color) == 0) continue
                setFill(color)
                cs.addRect(
                    r.num("x", 0.0).toFloat(), r.num("y", 0.0).toFloat(),
                    r.num("width", 0.0).toFloat(), r.num("height", 0.0).toFloat(),
                )
                cs.fill()
            }
        }

        fun textLines(list: List<Map<*, *>>) {
            for (t in list) {
                val text = t["text"] as? String ?: continue
                if (text.isBlank()) continue
                val color = (t["color"] as? Number)?.toLong() ?: continue
                val x = t.num("x", 0.0).toFloat()
                val baseline = t.num("baselineY", 0.0).toFloat()
                val size = t.num("fontSize", 12.0).toFloat()
                val bold = t["bold"] == true
                val italic = t["italic"] == true
                val kind = t["font"] as? String ?: "sans"
                // The bundled TTF Dart resolved for this weight/slant, and
                // which styles that file really has (the rest is faked).
                val asset = t["fontAsset"] as? String
                val fileBold = t["fontAssetBold"] == true
                val fileItalic = t["fontAssetItalic"] == true
                val embedded = asset?.let { embeddedFont(it) }
                val font = embedded ?: pdfFont(kind, bold, italic)
                // Faking applies to embedded files; the standard-14 fallback
                // already picks the bold/italic variant.
                val fakeBold = embedded != null && bold && !fileBold
                val fakeItalic = embedded != null && italic && !fileItalic

                var shownWidth = t.num("width", 0.0).toFloat()
                if (encodable(font, text)) {
                    setFill(color)
                    if (fakeBold) {
                        setStroke(color)
                        cs.setLineWidth(max(0.2f, size / 28f))
                        cs.setRenderingMode(RenderingMode.FILL_STROKE)
                    }
                    cs.beginText()
                    cs.setFont(font, size)
                    // Inside the page's app-space matrix y points down, so the
                    // text matrix flips it back to draw upright glyphs. The
                    // shear (c) slants the glyphs for a faked italic.
                    cs.setTextMatrix(Matrix(1f, 0f, if (fakeItalic) FAKE_ITALIC_SHEAR else 0f, -1f, x, baseline))
                    cs.showText(text)
                    cs.endText()
                    if (fakeBold) cs.setRenderingMode(RenderingMode.FILL)
                } else {
                    // Characters the font cannot encode (Arabic, CJK, emoji,
                    // ...): draw the line as an image so it is visible, at
                    // the cost of not being selectable.
                    shownWidth = drawTextAsImage(
                        text, kind, asset, fileBold, fileItalic, bold, italic, size, color, x, baseline,
                    )
                }
                if (t["underline"] == true && shownWidth > 0f) {
                    setStroke(color)
                    cs.setLineWidth(max(0.5f, size / 16f))
                    val y = baseline + size * 0.12f
                    cs.moveTo(x, y)
                    cs.lineTo(x + shownWidth, y)
                    cs.stroke()
                }
            }
        }

        /** Returns the width in points that the line occupies. */
        private fun drawTextAsImage(
            text: String, kind: String, asset: String?, fileBold: Boolean, fileItalic: Boolean,
            bold: Boolean, italic: Boolean, size: Float, argb: Long, x: Float, baseline: Float,
        ): Float {
            val scale = TEXT_IMAGE_SCALE
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                val bundled = asset?.let { embeddedTypeface(it) }
                typeface = if (bundled != null) {
                    // The bundled file already has its own weight/slant; the
                    // platform fakes only what the file lacks.
                    Typeface.create(bundled, styleFlags(bold && !fileBold, italic && !fileItalic))
                } else {
                    Typeface.create(
                        when (kind) {
                            "serif" -> Typeface.SERIF
                            "mono" -> Typeface.MONOSPACE
                            else -> Typeface.SANS_SERIF
                        },
                        styleFlags(bold, italic),
                    )
                }
                textSize = size * scale
                this.color = argb.toInt() or (0xFF shl 24) // alpha is applied by the PDF
            }
            val fm = paint.fontMetrics
            val pxW = max(1, ceil(paint.measureText(text).toDouble()).toInt() + 2)
            val pxH = max(1, ceil((fm.descent - fm.ascent).toDouble()).toInt() + 2)
            if (pxW.toLong() * pxH > MAX_TEXT_IMAGE_PIXELS) return 0f
            val bitmap = Bitmap.createBitmap(pxW, pxH, Bitmap.Config.ARGB_8888)
            try {
                Canvas(bitmap).drawText(text, 1f, 1f - fm.ascent, paint)
                val image = LosslessFactory.createFromImage(s.doc, bitmap)
                setFill(argb) // only to publish the alpha
                val w = pxW / scale
                val h = pxH / scale
                val top = baseline - (1f - fm.ascent) / scale
                cs.drawImage(image, Matrix(w, 0f, 0f, -h, x, top + h))
                return w
            } finally {
                bitmap.recycle()
            }
        }

        /** Image alpha is whatever the graphics state says; keep it opaque. */
        private fun setAlphaOpaque() = applyAlpha(1f, 1f)

        fun resetAlpha() = applyAlpha(1f, 1f)

        private fun setFill(argb: Long) {
            applyAlpha(alphaOf(argb) / 255f, strokeAlpha)
            cs.setNonStrokingColor(redOf(argb) / 255f, greenOf(argb) / 255f, blueOf(argb) / 255f)
        }

        private fun setStroke(argb: Long) {
            applyAlpha(fillAlpha, alphaOf(argb) / 255f)
            cs.setStrokingColor(redOf(argb) / 255f, greenOf(argb) / 255f, blueOf(argb) / 255f)
        }

        /** Emits an ExtGState only when the alpha actually changes. */
        private fun applyAlpha(fill: Float, stroke: Float) {
            val f = (fill * 1000f).roundToInt() / 1000f
            val st = (stroke * 1000f).roundToInt() / 1000f
            if (f == fillAlpha && st == strokeAlpha) return
            val state = PDExtendedGraphicsState()
            state.nonStrokingAlphaConstant = f
            state.strokingAlphaConstant = st
            cs.setGraphicsStateParameters(state)
            fillAlpha = f
            strokeAlpha = st
        }

        private fun loadImage(path: String): PDImageXObject? {
            if (s.images.containsKey(path)) return s.images[path]
            val image = try {
                decodeImage(path)
            } catch (e: OutOfMemoryError) {
                throw e
            } catch (e: Exception) {
                null // A broken picture must not fail the whole export.
            }
            if (image != null) s.images[path] = image
            return image
        }

        private fun decodeImage(path: String): PDImageXObject? {
            val file = File(path)
            if (!file.isFile) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            val head = ByteArray(3)
            val isJpeg = file.inputStream().use { it.read(head) == 3 } &&
                head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte() && head[2] == 0xFF.toByte()
            if (isJpeg && max(bounds.outWidth, bounds.outHeight) <= MAX_IMAGE_SIDE) {
                // Embeds the JPEG data as is (no re-encoding, small output).
                return JPEGFactory.createFromByteArray(s.doc, file.readBytes())
            }

            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_IMAGE_SIDE) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = BitmapFactory.decodeFile(path, options) ?: return null
            try {
                return LosslessFactory.createFromImage(s.doc, bitmap)
            } finally {
                bitmap.recycle()
            }
        }

        private fun styleFlags(bold: Boolean, italic: Boolean): Int = when {
            bold && italic -> Typeface.BOLD_ITALIC
            bold -> Typeface.BOLD
            italic -> Typeface.ITALIC
            else -> Typeface.NORMAL
        }

        /**
         * The bundled TTF [asset] embedded in the output (subset, selectable
         * text), loaded once per export; null when it cannot be read so the
         * caller falls back to the standard-14 fonts.
         */
        private fun embeddedFont(asset: String): PDFont? {
            if (s.fonts.containsKey(asset)) return s.fonts[asset]
            val font = try {
                s.fontAssets?.open(asset)?.use { PDType0Font.load(s.doc, it, true) }
            } catch (e: OutOfMemoryError) {
                throw e
            } catch (e: Exception) {
                null // A missing or unreadable font must not fail the export.
            }
            s.fonts[asset] = font
            return font
        }

        private fun embeddedTypeface(asset: String): Typeface? {
            if (s.typefaces.containsKey(asset)) return s.typefaces[asset]
            val tf = try {
                s.fontAssets?.typeface(asset)
            } catch (e: Exception) {
                null
            }
            s.typefaces[asset] = tf
            return tf
        }

        private fun pdfFont(kind: String, bold: Boolean, italic: Boolean): PDFont = when (kind) {
            "serif" -> when {
                bold && italic -> PDType1Font.TIMES_BOLD_ITALIC
                bold -> PDType1Font.TIMES_BOLD
                italic -> PDType1Font.TIMES_ITALIC
                else -> PDType1Font.TIMES_ROMAN
            }
            "mono" -> when {
                bold && italic -> PDType1Font.COURIER_BOLD_OBLIQUE
                bold -> PDType1Font.COURIER_BOLD
                italic -> PDType1Font.COURIER_OBLIQUE
                else -> PDType1Font.COURIER
            }
            else -> when {
                bold && italic -> PDType1Font.HELVETICA_BOLD_OBLIQUE
                bold -> PDType1Font.HELVETICA_BOLD
                italic -> PDType1Font.HELVETICA_OBLIQUE
                else -> PDType1Font.HELVETICA
            }
        }

        private fun encodable(font: PDFont, text: String): Boolean = try {
            font.encode(text)
            true
        } catch (e: IllegalArgumentException) {
            false
        } catch (e: IOException) {
            false
        }
    }

    // --- Helpers -----------------------------------------------------------

    private class Session(
        val id: Int,
        val outputPath: String,
        val title: String?,
        val pageCount: Int,
        val source: PDDocument?,
        val doc: PDDocument,
        val fontAssets: FontAssets?,
    ) {
        var done = 0

        /** Decoded images by file path, so one picture used twice is embedded once. */
        val images = HashMap<String, PDImageXObject>()

        /**
         * Embedded fonts by asset path (family + weight + slant), so a font
         * used on many lines is embedded once. A null value remembers a
         * failed load.
         */
        val fonts = HashMap<String, PDFont?>()
        val typefaces = HashMap<String, Typeface?>()
    }

    /** Access to the font files the app bundles (declared in pubspec.yaml). */
    private class FontAssets(
        private val context: Context,
        private val flutterAssets: FlutterPlugin.FlutterAssets,
    ) {
        private fun path(asset: String) = flutterAssets.getAssetFilePathByName(asset)

        fun open(asset: String): InputStream = context.assets.open(path(asset))

        fun typeface(asset: String): Typeface = Typeface.createFromAsset(context.assets, path(asset))
    }

    private class ExportError(val code: String, message: String) : Exception(message)

    private fun classify(t: Throwable): ExportError = when (t) {
        is ExportError -> t
        is OutOfMemoryError -> ExportError("out_of_memory", "Out of memory.")
        is IOException -> ExportError("export_failed", t.message ?: "I/O error.")
        else -> ExportError("export_failed", t.message ?: t.javaClass.simpleName)
    }

    private fun closeQuietly(doc: PDDocument?) {
        try {
            doc?.close()
        } catch (_: Exception) {
        }
    }

    companion object {
        const val CHANNEL = "neatink/pdf_export"

        private val NOT_IMPLEMENTED = Any()

        /** PdfBox keeps this much in memory before spilling to temp files. */
        private const val SCRATCH_MEMORY_BYTES = 48L * 1024 * 1024

        /** Longest side of an embedded picture, in pixels. */
        private const val MAX_IMAGE_SIDE = 3000

        /** Pixels per point when a text line has to be drawn as an image. */
        private const val TEXT_IMAGE_SCALE = 3f
        private const val MAX_TEXT_IMAGE_PIXELS = 16L * 1024 * 1024

        /** Shear for an italic faked on a font that has no italic file (about 11.5 degrees). */
        private const val FAKE_ITALIC_SHEAR = 0.2f

        /** Bezier control distance for a quarter circle. */
        private const val CIRCLE_K = 0.5523f

        @Volatile
        private var pdfBoxReady = false

        private fun initPdfBox(context: Context) {
            if (pdfBoxReady) return
            synchronized(this) {
                if (!pdfBoxReady) {
                    PDFBoxResourceLoader.init(context.applicationContext)
                    pdfBoxReady = true
                }
            }
        }

        private fun alphaOf(argb: Long) = ((argb shr 24) and 0xFF).toInt()
        private fun redOf(argb: Long) = ((argb shr 16) and 0xFF).toInt()
        private fun greenOf(argb: Long) = ((argb shr 8) and 0xFF).toInt()
        private fun blueOf(argb: Long) = (argb and 0xFF).toInt()

        private fun Map<*, *>.num(key: String, fallback: Double): Double =
            (this[key] as? Number)?.toDouble() ?: fallback

        @Suppress("UNCHECKED_CAST")
        private fun Map<*, *>.list(key: String): List<Map<*, *>> =
            (this[key] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()

        /** The standard codec delivers number lists as FloatArray, DoubleArray or List. */
        private fun floats(value: Any?): FloatArray = when (value) {
            is FloatArray -> value
            is DoubleArray -> FloatArray(value.size) { value[it].toFloat() }
            is List<*> -> FloatArray(value.size) { (value[it] as? Number)?.toFloat() ?: 0f }
            else -> FloatArray(0)
        }

        private fun PDRectangle?.toBox(): PdfCoords.Box? = this?.let {
            PdfCoords.Box.fromCorners(
                it.lowerLeftX.toDouble(), it.lowerLeftY.toDouble(),
                it.upperRightX.toDouble(), it.upperRightY.toDouble(),
            )
        }
    }
}
