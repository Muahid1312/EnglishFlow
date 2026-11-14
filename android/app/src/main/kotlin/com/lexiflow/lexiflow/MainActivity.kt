package com.lexiflow.lexiflow

import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.Writer
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val extractor = Executors.newSingleThreadExecutor()
    private var pendingSave: MethodChannel.Result? = null
    private var saveSource: File? = null
    private var saveHash: String? = null
    private var tts: TextToSpeech? = null
    private var speechReply: MethodChannel.Result? = null
    private var speechText: String? = null
    private var speechReady = false
    private var utterance = 0L
    private var speechOffline = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PDFBoxResourceLoader.init(applicationContext)
        val main = Handler(Looper.getMainLooper())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexiflow/listening")
            .setMethodCallHandler { call, result ->
                if (call.method != "openOnline") {
                    result.notImplemented()
                } else {
                    try {
                        val url = java.net.URI(requireNotNull(call.argument<String>("url")))
                        val allowed = setOf("learningenglish.voanews.com", "www.bbc.co.uk", "www.bbc.com", "learnenglish.britishcouncil.org", "elllo.org")
                        require(url.scheme == "https" && url.host in allowed && url.rawUserInfo == null && (url.port == -1 || url.port == 443))
                        startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url.toASCIIString())))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexiflow/pronunciation")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "stop" -> { stopSpeech(); result.success(null) }
                    "speak" -> {
                        val text = call.argument<String>("text")?.trim()
                        if (text.isNullOrEmpty() || text.length > 100) {
                            result.error("TEXT", "Choose a word or short phrase", null)
                        } else {
                            stopSpeech()
                            speechReply = result
                            speechText = text
                            if (tts == null) {
                                tts = TextToSpeech(applicationContext) { status ->
                                    runOnUiThread {
                                        if (status == TextToSpeech.SUCCESS) {
                                            speechReady = true
                                            speakPending()
                                        } else {
                                            speechReply?.error("ENGINE", "No working text-to-speech engine. Install an English TTS engine and voice data.", null)
                                            speechReply = null
                                            tts?.shutdown()
                                            tts = null
                                        }
                                    }
                                }
                            } else if (speechReady) { speakPending() }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexiflow/backup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availableBytes" -> {
                        try {
                            result.success(StatFs(filesDir.absolutePath).availableBytes)
                        } catch (_: Exception) {
                            result.error("STORAGE", "Could not check available storage", null)
                        }
                    }
                    "saveBackup" -> {
                        if (pendingSave != null) {
                            result.error("BUSY", "A document save is already open", null)
                        } else {
                            try {
                                val source = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                                require(source.path.startsWith(cacheDir.canonicalPath + File.separator))
                                require(source.isFile && source.length() <= 513L * 1024 * 1024)
                                val hash = requireNotNull(call.argument<String>("sha256"))
                                require(hash.matches(Regex("[a-f0-9]{64}")))
                                saveSource = source
                                saveHash = hash
                                pendingSave = result
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/octet-stream"
                                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "LexiFlow.lexiflowbackup")
                                }, 7401)
                            } catch (_: Exception) {
                                pendingSave = null
                                saveSource = null
                                saveHash = null
                                result.error("SAVE", "Could not open the document save picker", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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
                                    // Enforce the text limit while extracting.
                                    // getText() builds the whole result before
                                    // the old post-extraction size check ran.
                                    val text = StringBuilder()
                                    val bounded = object : Writer() {
                                        override fun write(chars: CharArray, offset: Int, length: Int) {
                                            require(length <= 1_000_000 - text.length)
                                            text.append(chars, offset, length)
                                        }
                                        override fun flush() { }
                                        override fun close() { }
                                    }
                                    PDFTextStripper().writeText(document, bounded)
                                    text.toString()
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

    private fun stopSpeech() {
        utterance++
        tts?.stop()
        speechReply?.success(mapOf("stopped" to true))
        speechReply = null
        speechText = null
    }

    private fun speakPending() {
        val engine = tts ?: return
        val text = speechText ?: return
        try {
            if (engine.setLanguage(Locale.US) < TextToSpeech.LANG_AVAILABLE) {
                require(engine.setLanguage(Locale.ENGLISH) >= TextToSpeech.LANG_AVAILABLE)
            }
            val voices = engine.voices.orEmpty().filter {
                it.locale.language == "en" && !it.features.orEmpty().contains("notInstalled")
            }.sortedWith(compareBy({ if (it.locale.country == "US") 0 else 1 },
                { if (it.isNetworkConnectionRequired) 1 else 0 }, { it.name }))
            require(voices.isNotEmpty())
            val offlineUs = voices.firstOrNull { it.locale.country == "US" && !it.isNetworkConnectionRequired }
            val voice = offlineUs ?: voices.first()
            require(engine.setVoice(voice) != TextToSpeech.ERROR)
            speechOffline = !voice.isNetworkConnectionRequired
            val token = (++utterance).toString()
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) { }
                override fun onDone(id: String?) {
                    runOnUiThread {
                        if (id == utterance.toString()) {
                            speechReply?.success(mapOf("offlineVoice" to speechOffline, "locale" to voice.locale.toLanguageTag()))
                            speechReply = null
                            speechText = null
                        }
                    }
                }
                @Deprecated("Android compatibility callback")
                override fun onError(id: String?) {
                    runOnUiThread {
                        if (id == utterance.toString()) {
                            speechReply?.error("SPEECH", "Pronunciation failed. Check installed English voice data and engine settings.", null)
                            speechReply = null
                            speechText = null
                        }
                    }
                }
            })
            require(engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, token) != TextToSpeech.ERROR)
        } catch (_: Exception) {
            speechReply?.error("VOICE", "No usable English voice. Install English (United States) voice data in Android text-to-speech settings.", null)
            speechReply = null
            speechText = null
        }
    }

    @Deprecated("Deprecated in Android; retained for Flutter plugin compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7401) return
        val reply = pendingSave ?: return
        val source = saveSource
        val expected = saveHash
        pendingSave = null
        saveSource = null
        saveHash = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(false)
            return
        }
        extractor.execute {
            try {
                requireNotNull(source)
                val output = requireNotNull(contentResolver.openOutputStream(uri, "wt"))
                output.use { destination -> source.inputStream().use { it.copyTo(destination) }; destination.flush() }
                val digest = MessageDigest.getInstance("SHA-256")
                var length = 0L
                requireNotNull(contentResolver.openInputStream(uri)).use { input ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        length += n
                        require(length <= source.length())
                        digest.update(buffer, 0, n)
                    }
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                require(length == source.length() && actual == expected)
                runOnUiThread { reply.success(true) }
            } catch (_: Exception) {
                try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { }
                runOnUiThread { reply.error("SAVE_VERIFY", "Backup destination could not be written and verified", null) }
            }
        }
    }

    override fun onDestroy() {
        stopSpeech()
        tts?.shutdown()
        tts = null
        pendingSave?.error("INTERRUPTED", "Document save was interrupted", null)
        pendingSave = null
        extractor.shutdown()
        super.onDestroy()
    }
}
