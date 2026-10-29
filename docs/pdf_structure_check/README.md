# PDF bookmarks and forms check

`PdfStructureCheck.java` mirrors `android/.../PdfStructure.kt` (which carries a
source PDF's bookmarks and form fields over to the exported PDF) with Apache
PDFBox 2.0.27, the version PdfBox-Android 2.0.27.0 follows, and checks it on a
generated 4-page PDF exported as pages 2, 0, 1. Run it after changing either:

    M=https://maven-central.storage-download.googleapis.com/maven2
    curl -sSfLO $M/org/apache/pdfbox/pdfbox/2.0.27/pdfbox-2.0.27.jar
    curl -sSfLO $M/org/apache/pdfbox/fontbox/2.0.27/fontbox-2.0.27.jar
    curl -sSfLO $M/commons-logging/commons-logging/1.2/commons-logging-1.2.jar
    CP=pdfbox-2.0.27.jar:fontbox-2.0.27.jar:commons-logging-1.2.jar
    javac -d build -cp $CP PdfStructureCheck.java
    java -cp build:$CP PdfStructureCheck <output dir>

It prints one `ok` line per check and "All checks passed." (2026-10-29: 17 checks
pass). Not checked on the device with PdfBox-Android.
