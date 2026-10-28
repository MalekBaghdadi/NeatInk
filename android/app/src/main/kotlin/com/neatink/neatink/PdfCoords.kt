package com.neatink.neatink

import kotlin.math.max
import kotlin.math.min

/**
 * Mapping from app page coordinates to PDF user space.
 *
 * This file mirrors `lib/pdf/pdf_coords.dart` line for line (the Dart copy
 * is unit-tested). Change both together.
 *
 * App coordinates: points, origin at the top-left of the page *as displayed*
 * (after /Rotate), y pointing down.
 *
 * PDF user space: points, origin at the bottom-left of the unrotated page,
 * y pointing up. The visible area is the CropBox (clipped to the MediaBox),
 * whose lower-left corner is often not (0, 0). Viewers show the page turned
 * clockwise by /Rotate degrees.
 */
object PdfCoords {
    /** A rectangle in PDF user space (y up). */
    data class Box(val left: Double, val bottom: Double, val right: Double, val top: Double) {
        val width: Double get() = right - left
        val height: Double get() = top - bottom
        val isEmpty: Boolean get() = width <= 0 || height <= 0

        companion object {
            /** Builds a box from any two opposite corners, like PDF rectangle arrays. */
            fun fromCorners(x1: Double, y1: Double, x2: Double, y2: Double) =
                Box(min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))
        }
    }

    /** US Letter, the PDF default when a page has no usable MediaBox. */
    val LETTER = Box(0.0, 0.0, 612.0, 792.0)

    /**
     * The visible box of a page: the CropBox intersected with the MediaBox,
     * or the MediaBox when the CropBox is missing or the intersection is
     * empty. Same rule as PDFium (what the app shows).
     */
    fun visibleBox(mediaBox: Box?, cropBox: Box?): Box {
        val media = if (mediaBox == null || mediaBox.isEmpty) LETTER else mediaBox
        if (cropBox == null || cropBox.isEmpty) return media
        val clipped = Box(
            max(cropBox.left, media.left),
            max(cropBox.bottom, media.bottom),
            min(cropBox.right, media.right),
            min(cropBox.top, media.top),
        )
        return if (clipped.isEmpty) media else clipped
    }

    /**
     * Number of clockwise quarter turns for a /Rotate value, interpreted like
     * PDFium (`rotate / 90 % 4`, truncating): 90 -> 1, -90 -> 3, 450 -> 1,
     * and values that are not multiples of 90 round toward zero (45 -> 0,
     * 135 -> 1). PdfBox's own getRotation() treats those differently, so it
     * is not used.
     */
    fun quarterTurns(rotate: Int): Int = Math.floorMod(rotate / 90, 4)

    /** Page size as displayed (after rotation) for a visible [box]: (width, height). */
    fun displayedSize(box: Box, quarterTurns: Int): Pair<Double, Double> {
        val q = Math.floorMod(quarterTurns, 4)
        return if (q % 2 == 1) Pair(box.height, box.width) else Pair(box.width, box.height)
    }

    /**
     * The affine map from app coordinates (top-left origin, y down, displayed
     * orientation, page of [appWidth] x [appHeight] points) to PDF user space
     * of a page whose visible box is [box], shown turned clockwise by
     * [quarterTurns] x 90 degrees.
     *
     * Returns `[a, b, c, d, e, f]` with `u = a*x + c*y + e`, `v = b*x + d*y + f`,
     * i.e. exactly the operands of a PDF `cm` operator.
     *
     * Derivation: let (X, Y) be the display position scaled to the PDF's
     * displayed size. Turning the unrotated page clockwise by 90 degrees moves
     * its bottom-left corner to the display's top-left, so per rotation:
     *
     * | turns | u (PDF x)   | v (PDF y)   |
     * |-------|-------------|-------------|
     * | 0     | left + X    | top - Y     |
     * | 1     | left + Y    | bottom + X  |
     * | 2     | right - X   | bottom + Y  |
     * | 3     | right - Y   | top - X     |
     */
    fun appToPdfMatrix(box: Box, quarterTurns: Int, appWidth: Double, appHeight: Double): DoubleArray {
        val q = Math.floorMod(quarterTurns, 4)
        val (shownWidth, shownHeight) = displayedSize(box, q)
        val sx = if (appWidth > 0) shownWidth / appWidth else 1.0
        val sy = if (appHeight > 0) shownHeight / appHeight else 1.0
        return when (q) {
            0 -> doubleArrayOf(sx, 0.0, 0.0, -sy, box.left, box.top)
            1 -> doubleArrayOf(0.0, sx, sy, 0.0, box.left, box.bottom)
            2 -> doubleArrayOf(-sx, 0.0, 0.0, sy, box.right, box.bottom)
            else -> doubleArrayOf(0.0, -sx, -sy, 0.0, box.right, box.top)
        }
    }

    /**
     * [box] grown by [left] and [right] PDF units beside the page *as
     * displayed* (turned clockwise by [quarterTurns] x 90 degrees): the
     * visible box of a PDF page given writing margins. Mirrors
     * `pdfBoxWithSideMargins` in `pdf_coords.dart`:
     *
     * | turns | displayed left | displayed right |
     * |-------|----------------|-----------------|
     * | 0     | left           | right           |
     * | 1     | bottom         | top             |
     * | 2     | right          | left            |
     * | 3     | top            | bottom          |
     */
    fun withSideMargins(box: Box, quarterTurns: Int, left: Double, right: Double): Box =
        when (Math.floorMod(quarterTurns, 4)) {
            0 -> Box(box.left - left, box.bottom, box.right + right, box.top)
            1 -> Box(box.left, box.bottom - left, box.right, box.top + right)
            2 -> Box(box.left - right, box.bottom, box.right + left, box.top)
            else -> Box(box.left, box.bottom - right, box.right, box.top + left)
        }
}
