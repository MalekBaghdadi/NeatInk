import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.apache.pdfbox.cos.COSArray;
import org.apache.pdfbox.cos.COSBase;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentNameDictionary;
import org.apache.pdfbox.pdmodel.PDDestinationNameTreeNode;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDResources;
import org.apache.pdfbox.pdmodel.PageMode;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType1Font;
import org.apache.pdfbox.pdmodel.interactive.action.PDActionGoTo;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotation;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotationWidget;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDNamedDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageFitDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageXYZDestination;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem;
import org.apache.pdfbox.pdmodel.interactive.form.PDAcroForm;
import org.apache.pdfbox.pdmodel.interactive.form.PDCheckBox;
import org.apache.pdfbox.pdmodel.interactive.form.PDField;
import org.apache.pdfbox.pdmodel.interactive.form.PDNonTerminalField;
import org.apache.pdfbox.pdmodel.interactive.form.PDTerminalField;
import org.apache.pdfbox.pdmodel.interactive.form.PDTextField;

/**
 * JVM check of PdfStructure.kt (bookmarks and form fields carried over to an
 * exported PDF) with Apache PDFBox 2.0.27, the version PdfBox-Android
 * 2.0.27.0 follows. The two methods below mirror the Kotlin line by line;
 * change both together.
 *
 *   javac -cp pdfbox-2.0.27.jar:fontbox-2.0.27.jar:commons-logging-1.2.jar PdfStructureCheck.java
 *   java  -cp .:pdfbox-2.0.27.jar:fontbox-2.0.27.jar:commons-logging-1.2.jar PdfStructureCheck <dir>
 *
 * Builds a 4-page source with bookmarks (an x/y/zoom one, a child, a named
 * destination, a GoTo action) and form fields (a text field, a checkbox, a
 * field with widgets on two pages), "exports" source pages 2, 0, 1 (page 3
 * left out, order changed) the way PdfExportPlugin does, and checks the
 * result after saving and reloading it.
 */
public class PdfStructureCheck {
    // ---- Mirror of PdfStructure.kt ----------------------------------------

    static void copyOutline(PDDocument source, PDDocument out, Map<Integer, PDPage> exported) throws Exception {
        PDDocumentOutline outline = source.getDocumentCatalog().getDocumentOutline();
        if (outline == null) return;
        PDDocumentOutline copy = new PDDocumentOutline();
        boolean any = false;
        for (PDOutlineItem item : outline.children()) {
            PDOutlineItem c = copyItem(item, source, exported);
            if (c == null) continue;
            copy.addLast(c);
            any = true;
        }
        if (!any) return;
        out.getDocumentCatalog().setDocumentOutline(copy);
        if (source.getDocumentCatalog().getPageMode() == PageMode.USE_OUTLINES) {
            out.getDocumentCatalog().setPageMode(PageMode.USE_OUTLINES);
        }
    }

    static PDOutlineItem copyItem(PDOutlineItem item, PDDocument source, Map<Integer, PDPage> exported) {
        PDOutlineItem copy = new PDOutlineItem();
        copy.setTitle(item.getTitle() == null ? "" : item.getTitle());
        copy.setBold(item.isBold());
        copy.setItalic(item.isItalic());
        if (item.getTextColor() != null) copy.setTextColor(item.getTextColor());
        PDPageDestination target = pageDestination(item, source);
        int index = -1;
        if (target != null) {
            try { index = target.retrievePageNumber(); } catch (Exception e) { index = -1; }
        }
        PDPage page = exported.get(index);
        if (target != null && page != null) copy.setDestination(retarget(target, page));
        boolean kids = false;
        for (PDOutlineItem child : item.children()) {
            PDOutlineItem c = copyItem(child, source, exported);
            if (c == null) continue;
            copy.addLast(c);
            kids = true;
        }
        if (page == null && !kids) return null;
        if (kids && item.isNodeOpen()) copy.openNode();
        return copy;
    }

    static PDPageDestination pageDestination(PDOutlineItem item, PDDocument source) {
        try {
            PDDestination dest = item.getDestination();
            if (dest == null && item.getAction() instanceof PDActionGoTo) dest = ((PDActionGoTo) item.getAction()).getDestination();
            if (dest instanceof PDNamedDestination) dest = source.getDocumentCatalog().findNamedDestinationPage((PDNamedDestination) dest);
            return dest instanceof PDPageDestination ? (PDPageDestination) dest : null;
        } catch (Exception e) {
            return null;
        }
    }

    static PDDestination retarget(PDPageDestination dest, PDPage page) {
        COSArray array = new COSArray();
        array.addAll(dest.getCOSObject());
        array.set(0, page.getCOSObject());
        try { return PDDestination.create(array); } catch (Exception e) { throw new RuntimeException(e); }
    }

    static void copyForm(PDDocument source, PDDocument out) throws Exception {
        PDAcroForm form = source.getDocumentCatalog().getAcroForm();
        if (form == null) return;
        Set<COSBase> widgets = new HashSet<>();
        for (PDPage page : out.getPages()) {
            for (PDAnnotation annotation : page.getAnnotations()) {
                if (annotation instanceof PDAnnotationWidget) {
                    annotation.setPage(page);
                    widgets.add(annotation.getCOSObject());
                }
            }
        }
        if (widgets.isEmpty()) return;
        List<PDField> kept = new ArrayList<>();
        for (PDField f : form.getFields()) if (keep(f, widgets)) kept.add(f);
        if (kept.isEmpty()) return;
        PDAcroForm copy = new PDAcroForm(out);
        for (COSName key : new COSName[] {COSName.DA, COSName.DR, COSName.Q, COSName.NEED_APPEARANCES}) {
            COSBase v = form.getCOSObject().getDictionaryObject(key);
            if (v != null) copy.getCOSObject().setItem(key, v);
        }
        copy.setFields(kept);
        out.getDocumentCatalog().setAcroForm(copy);
    }

    static boolean keep(PDField field, Set<COSBase> widgets) {
        if (field instanceof PDNonTerminalField) {
            PDNonTerminalField n = (PDNonTerminalField) field;
            List<PDField> children = new ArrayList<>();
            for (PDField c : n.getChildren()) if (keep(c, widgets)) children.add(c);
            if (children.size() != n.getChildren().size()) n.setChildren(children);
            return !children.isEmpty();
        }
        if (field instanceof PDTerminalField) {
            PDTerminalField t = (PDTerminalField) field;
            List<PDAnnotationWidget> on = new ArrayList<>();
            for (PDAnnotationWidget w : t.getWidgets()) if (widgets.contains(w.getCOSObject())) on.add(w);
            if (!on.isEmpty() && on.size() != t.getWidgets().size()) t.setWidgets(on);
            return !on.isEmpty();
        }
        return false;
    }

    // ---- The check ---------------------------------------------------------

    static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
        System.out.println("ok  " + what);
    }

    static PDAnnotationWidget widget(PDPage page, PDField parent, float y) throws Exception {
        PDAnnotationWidget w = new PDAnnotationWidget();
        w.setRectangle(new PDRectangle(50, y, 200, 20));
        w.setPage(page);
        w.setParent(parent instanceof PDTerminalField ? (PDTerminalField) parent : null);
        page.getAnnotations().add(w);
        return w;
    }

    public static void main(String[] args) throws Exception {
        File dir = new File(args.length > 0 ? args[0] : ".");
        File src = new File(dir, "source.pdf"), outFile = new File(dir, "exported.pdf");

        try (PDDocument doc = new PDDocument()) {
            for (int i = 0; i < 4; i++) doc.addPage(new PDPage(PDRectangle.A4));
            // Bookmarks.
            PDDocumentOutline outline = new PDDocumentOutline();
            PDOutlineItem ch1 = new PDOutlineItem();
            ch1.setTitle("Chapter 1");
            PDPageXYZDestination xyz = new PDPageXYZDestination();
            xyz.setPage(doc.getPage(0));
            xyz.setTop(700);
            ch1.setDestination(xyz);
            PDOutlineItem s11 = new PDOutlineItem();
            s11.setTitle("Section 1.1");
            PDPageFitDestination fit = new PDPageFitDestination();
            fit.setPage(doc.getPage(1));
            s11.setDestination(fit);
            ch1.addLast(s11);
            ch1.openNode();
            outline.addLast(ch1);
            PDOutlineItem ch2 = new PDOutlineItem();
            ch2.setTitle("Chapter 2");
            ch2.setDestination(new PDNamedDestination("ch2"));
            outline.addLast(ch2);
            PDOutlineItem app = new PDOutlineItem();
            app.setTitle("Appendix");
            PDActionGoTo go = new PDActionGoTo();
            PDPageFitDestination appDest = new PDPageFitDestination();
            appDest.setPage(doc.getPage(3));
            go.setDestination(appDest);
            app.setAction(go);
            outline.addLast(app);
            doc.getDocumentCatalog().setDocumentOutline(outline);
            doc.getDocumentCatalog().setPageMode(PageMode.USE_OUTLINES);
            PDDestinationNameTreeNode dests = new PDDestinationNameTreeNode();
            Map<String, PDPageDestination> named = new HashMap<>();
            PDPageFitDestination ch2Dest = new PDPageFitDestination();
            ch2Dest.setPage(doc.getPage(2));
            named.put("ch2", ch2Dest);
            dests.setNames(named);
            PDDocumentNameDictionary names = new PDDocumentNameDictionary(doc.getDocumentCatalog());
            names.setDests(dests);
            doc.getDocumentCatalog().setNames(names);
            // Form.
            PDAcroForm form = new PDAcroForm(doc);
            PDResources dr = new PDResources();
            dr.put(COSName.getPDFName("Helv"), PDType1Font.HELVETICA);
            form.setDefaultResources(dr);
            form.setDefaultAppearance("/Helv 10 Tf 0 g");
            doc.getDocumentCatalog().setAcroForm(form);
            PDTextField name = new PDTextField(form);
            name.setPartialName("name");
            List<PDAnnotationWidget> nw = new ArrayList<>();
            nw.add(widget(doc.getPage(0), name, 600));
            name.setWidgets(nw);
            PDCheckBox agree = new PDCheckBox(form);
            agree.setPartialName("agree");
            List<PDAnnotationWidget> aw = new ArrayList<>();
            aw.add(widget(doc.getPage(2), agree, 500));
            agree.setWidgets(aw);
            PDTextField initials = new PDTextField(form);
            initials.setPartialName("initials");
            List<PDAnnotationWidget> iw = new ArrayList<>();
            iw.add(widget(doc.getPage(1), initials, 100));
            iw.add(widget(doc.getPage(3), initials, 100));
            initials.setWidgets(iw);
            List<PDField> fields = new ArrayList<>();
            fields.add(name);
            fields.add(agree);
            fields.add(initials);
            form.setFields(fields);
            name.setValue("Mariam");
            initials.setValue("MB");
            doc.save(src);
        }

        try (PDDocument source = PDDocument.load(src); PDDocument out = new PDDocument()) {
            Map<Integer, PDPage> exported = new HashMap<>();
            for (int index : new int[] {2, 0, 1}) {
                PDPage page = out.importPage(source.getPage(index));
                exported.putIfAbsent(index, page);
            }
            copyOutline(source, out, exported);
            copyForm(source, out);
            out.save(outFile);
        }

        try (PDDocument doc = PDDocument.load(outFile)) {
            check(doc.getNumberOfPages() == 3, "3 pages exported");
            PDDocumentOutline outline = doc.getDocumentCatalog().getDocumentOutline();
            List<String> titles = new ArrayList<>();
            for (PDOutlineItem i : outline.children()) titles.add(i.getTitle());
            check(titles.equals(List.of("Chapter 1", "Chapter 2")), "top bookmarks " + titles + " (Appendix's page was not exported)");
            PDOutlineItem ch1 = outline.getFirstChild();
            PDPageDestination d1 = (PDPageDestination) ch1.getDestination();
            check(d1.retrievePageNumber() == 1, "Chapter 1 -> exported page 2 (source page 1)");
            check(d1 instanceof PDPageXYZDestination && ((PDPageXYZDestination) d1).getTop() == 700, "Chapter 1 keeps its x/y/zoom destination");
            PDOutlineItem s11 = ch1.getFirstChild();
            check(s11 != null && "Section 1.1".equals(s11.getTitle()), "Section 1.1 is under Chapter 1");
            check(((PDPageDestination) s11.getDestination()).retrievePageNumber() == 2, "Section 1.1 -> exported page 3");
            check(ch1.isNodeOpen(), "Chapter 1 stays open");
            PDPageDestination d2 = (PDPageDestination) ch1.getNextSibling().getDestination();
            check(d2.retrievePageNumber() == 0, "Chapter 2 (a named destination) -> exported page 1");
            check(doc.getDocumentCatalog().getPageMode() == PageMode.USE_OUTLINES, "opens with the bookmarks shown");

            PDAcroForm form = doc.getDocumentCatalog().getAcroForm();
            check(form != null, "the exported PDF has a form");
            List<String> names = new ArrayList<>();
            for (PDField f : form.getFields()) names.add(f.getFullyQualifiedName());
            check(names.equals(List.of("name", "agree", "initials")), "fields " + names);
            check("Mariam".equals(form.getField("name").getValueAsString()), "the filled-in value is kept");
            PDTerminalField initials = (PDTerminalField) form.getField("initials");
            check(initials.getWidgets().size() == 1, "initials keeps only its widget on an exported page");
            PDAnnotationWidget w = ((PDTerminalField) form.getField("name")).getWidgets().get(0);
            check(w.getPage() != null && w.getPage().getCOSObject() == doc.getPage(1).getCOSObject(), "a widget points at its exported page");
            check(form.getDefaultAppearance().contains("Helv"), "default appearance kept");
            check(form.getDefaultResources() != null && form.getDefaultResources().getFont(COSName.getPDFName("Helv")) != null, "default font kept");
            // A field can still be filled in.
            form.getField("name").setValue("Malek");
            check("Malek".equals(form.getField("name").getValueAsString()), "fields can be filled in");
        }
        System.out.println("All checks passed.");
    }
}
