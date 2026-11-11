# PDFBox Android explicitly supports an absent optional JPX image decoder:
# https://github.com/TomRoush/PdfBox-Android#reading-jpx-images
# It skips JPX images when the codec is unavailable. Our PDFBox integration
# extracts selectable text; PDF display uses pdfx's separate renderer.
# Do not disable R8 or ignore missing classes generally.
-dontwarn com.gemalto.jp2.JP2Decoder
