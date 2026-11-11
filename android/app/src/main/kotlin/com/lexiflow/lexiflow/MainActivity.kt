package com.lexiflow.lexiflow

import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val extractor = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PDFBoxResourceLoader.init(applicationContext)
        val main = Handler(Looper.getMainLooper())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexiflow/pdf_text")
            .setMethodCallHandler { call, result ->
                if (call.method != "extract") {
                    result.notImplemented()
                } else {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_FILE", "Missing PDF path", null)
                    } else {
                        extractor.execute {
                            try {
                                val file = File(path)
                                require(file.isFile && file.length() <= 40L * 1024 * 1024)
                                val text = PDDocument.load(file).use { document ->
                                    require(!document.isEncrypted && document.numberOfPages <= 2000)
                                    require(document.currentAccessPermission.canExtractContent())
                                    PDFTextStripper().getText(document)
                                }
                                require(text.length <= 1000000)
                                main.post { result.success(text) }
                            } catch (_: Exception) {
                                main.post { result.error("PDF_EXTRACTION", "Cannot extract text from this PDF", null) }
                            }
                        }
                    }
                }
            }
    }
    override fun onDestroy() {
        extractor.shutdown()
        super.onDestroy()
    }
}
