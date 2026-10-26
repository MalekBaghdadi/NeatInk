# R8 rules for NeatInk release builds.
#
# PdfBox-Android (PDF export, see PdfExportPlugin.kt) creates some classes
# reflectively (security handlers, filters, font and CMap resources), which
# R8 cannot see. Keep the library whole: losing a constructor here would only
# show up as a failed export on the device.
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
-keep class com.tom_roush.harmony.** { *; }

# Optional PdfBox-Android dependencies that NeatInk does not ship:
# JPEG 2000 decoding and BouncyCastle (only needed for certificate-encrypted
# or signed PDFs, which the importer does not open anyway).
-dontwarn com.gemalto.jp2.**
-dontwarn org.bouncycastle.**
