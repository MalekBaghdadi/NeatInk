package com.neatink.neatink

import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import kotlin.math.max
import kotlin.math.min

/**
 * Writing margins beside a page copied from the source PDF.
 *
 * The page's visible box grows by the margins on the sides *as displayed*
 * (after /Rotate), so the original content stays as it is (text stays
 * selectable) and simply sits between the margins. The original content is
 * clipped to its old visible box, so anything the PDF had outside it (bleed,
 * printer marks) does not appear in the margins, where the app shows paper.
 */
object PdfMargins {
    /**
     * Gives [page] (already in [doc]) margins of [marginLeft] and
     * [marginRight] app points on an app page [appWidth] points wide, and
     * returns the new visible box. [box] and [quarterTurns] describe the
     * page before (its visible box and rotation).
     */
    fun apply(
        doc: PDDocument,
        page: PDPage,
        box: PdfCoords.Box,
        quarterTurns: Int,
        appWidth: Double,
        marginLeft: Double,
        marginRight: Double,
    ): PdfCoords.Box {
        val (shownWidth, _) = PdfCoords.displayedSize(box, quarterTurns)
        val contentWidth = appWidth - marginLeft - marginRight
        // App points to PDF units (1 unless the sizes were rounded).
        val k = if (contentWidth > 0) shownWidth / contentWidth else 1.0
        val grown = PdfCoords.withSideMargins(box, quarterTurns, marginLeft * k, marginRight * k)

        PDPageContentStream(doc, page, PDPageContentStream.AppendMode.PREPEND, true).use { cs ->
            cs.saveGraphicsState()
            cs.addRect(box.left.toFloat(), box.bottom.toFloat(), box.width.toFloat(), box.height.toFloat())
            cs.clip()
        }
        PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, false).use { cs ->
            cs.restoreGraphicsState()
        }

        val media = page.mediaBox
        val mediaBox = PdfCoords.Box(
            min(media.lowerLeftX.toDouble(), grown.left),
            min(media.lowerLeftY.toDouble(), grown.bottom),
            max(media.upperRightX.toDouble(), grown.right),
            max(media.upperRightY.toDouble(), grown.top),
        )
        page.mediaBox = rectangle(mediaBox)
        page.cropBox = rectangle(grown)
        // These default to the crop box; an old, smaller one would cut the
        // margins off when printing or trimming.
        page.cosObject.removeItem(COSName.BLEED_BOX)
        page.cosObject.removeItem(COSName.TRIM_BOX)
        page.cosObject.removeItem(COSName.ART_BOX)
        return grown
    }

    private fun rectangle(b: PdfCoords.Box) =
        PDRectangle(b.left.toFloat(), b.bottom.toFloat(), b.width.toFloat(), b.height.toFloat())
}
