package com.neatink.neatink

import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PageMode
import com.tom_roush.pdfbox.pdmodel.interactive.action.PDActionGoTo
import com.tom_roush.pdfbox.pdmodel.interactive.annotation.PDAnnotationWidget
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDNamedDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDAcroForm
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDField
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDNonTerminalField
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDTerminalField

/**
 * Carries the source PDF's bookmarks (outline) and form fields (AcroForm)
 * over to the exported PDF (v1.7.0). The export builds a new document from
 * imported pages, which keeps each page's text and annotations but not the
 * document-level structure; this puts it back, pointing at the exported
 * pages. A bookmark to a page that was not exported is dropped (its
 * children are kept); a form field keeps only the widgets on exported pages.
 *
 * Mirrored for a JVM check with Apache PDFBox in
 * `docs/pdf_structure_check/PdfStructureCheck.java`: change both together.
 */
object PdfStructure {
    /**
     * Copies [source]'s outline into [out]. [exported] maps a source page
     * index to the first exported page made from it.
     */
    fun copyOutline(source: PDDocument, out: PDDocument, exported: Map<Int, PDPage>) {
        val outline = source.documentCatalog.documentOutline ?: return
        val copy = PDDocumentOutline()
        var any = false
        for (item in outline.children()) {
            val c = copyItem(item, source, exported) ?: continue
            copy.addLast(c)
            any = true
        }
        if (!any) return
        out.documentCatalog.documentOutline = copy
        if (source.documentCatalog.pageMode == PageMode.USE_OUTLINES) {
            out.documentCatalog.pageMode = PageMode.USE_OUTLINES
        }
    }

    private fun copyItem(item: PDOutlineItem, source: PDDocument, exported: Map<Int, PDPage>): PDOutlineItem? {
        val copy = PDOutlineItem()
        copy.title = item.title ?: ""
        copy.isBold = item.isBold
        copy.isItalic = item.isItalic
        item.textColor?.let { copy.textColor = it }
        val target = pageDestination(item, source)
        val index = target?.let { safe { it.retrievePageNumber() } } ?: -1
        val page = exported[index]
        if (target != null && page != null) copy.setDestination(retarget(target, page))
        var kids = false
        for (child in item.children()) {
            val c = copyItem(child, source, exported) ?: continue
            copy.addLast(c)
            kids = true
        }
        if (page == null && !kids) return null
        if (kids && item.isNodeOpen) copy.openNode()
        return copy
    }

    /** Where [item] goes in [source]: its destination, a GoTo action's, or a named one. */
    private fun pageDestination(item: PDOutlineItem, source: PDDocument): PDPageDestination? = safe {
        var dest: PDDestination? = item.destination
        if (dest == null) dest = (item.action as? PDActionGoTo)?.destination
        if (dest is PDNamedDestination) dest = source.documentCatalog.findNamedDestinationPage(dest)
        dest as? PDPageDestination
    }

    /** The same kind of destination (fit, x/y/zoom...) on [page]. */
    private fun retarget(dest: PDPageDestination, page: PDPage): PDDestination {
        val array = COSArray()
        array.addAll(dest.cosObject)
        array.set(0, page.cosObject)
        return PDDestination.create(array)
    }

    /**
     * Copies [source]'s form into [out]: the fields that have a widget on an
     * exported page, their widgets pointing at the exported pages.
     */
    fun copyForm(source: PDDocument, out: PDDocument) {
        val form = source.documentCatalog.acroForm ?: return
        val widgets = HashSet<COSBase>()
        for (page in out.pages) {
            for (annotation in safe { page.annotations } ?: emptyList()) {
                if (annotation is PDAnnotationWidget) {
                    annotation.page = page
                    widgets.add(annotation.cosObject)
                }
            }
        }
        if (widgets.isEmpty()) return
        val kept = form.fields.filter { keep(it, widgets) }
        if (kept.isEmpty()) return
        val copy = PDAcroForm(out)
        for (key in listOf(COSName.DA, COSName.DR, COSName.Q, COSName.NEED_APPEARANCES)) {
            form.cosObject.getDictionaryObject(key)?.let { copy.cosObject.setItem(key, it) }
        }
        copy.fields = kept
        out.documentCatalog.acroForm = copy
    }

    /**
     * Whether [field] has a widget among [widgets]; drops its other widgets
     * and children (they are on pages that were not exported).
     */
    private fun keep(field: PDField, widgets: Set<COSBase>): Boolean = when (field) {
        is PDNonTerminalField -> {
            val children = field.children.filter { keep(it, widgets) }
            if (children.size != field.children.size) field.children = children
            children.isNotEmpty()
        }
        is PDTerminalField -> {
            val on = field.widgets.filter { it.cosObject in widgets }
            if (on.isNotEmpty() && on.size != field.widgets.size) field.widgets = on
            on.isNotEmpty()
        }
        else -> false
    }

    private inline fun <T> safe(block: () -> T): T? = try {
        block()
    } catch (_: Exception) {
        null
    }
}
