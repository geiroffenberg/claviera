package com.example.claviera

import android.media.AudioAttributes
import android.media.SoundPool
import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import kotlin.math.abs
import kotlin.math.pow

class MainActivity : FlutterActivity() {
    private val roots = listOf(22, 34, 46, 58, 70, 82, 94, 104, 116, 127)
    private val samples = mutableMapOf<Int, Int>()
    private val handler = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null
    private var pendingInit: MethodChannel.Result? = null
    private var loaded = 0
    private var loadingFailed = false
    private var stream = 0
    private var startedAt = 0L
    private var pendingStop: Runnable? = null
    private val scheduledPlayback = mutableListOf<Runnable>()
    private val playbackStreams = mutableSetOf<Int>()
    private var channel: MethodChannel? = null
    private var pdfResult: MethodChannel.Result? = null
    private var pdfPages: List<ByteArray>? = null
    private val pdfRequest = 7463
    private val midiRequest = 7464
    private var midiResult: MethodChannel.Result? = null
    private var midiBytes: ByteArray? = null
    private val musicXmlRequest = 7465
    private var musicXmlResult: MethodChannel.Result? = null
    private var musicXmlBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "claviera/projects")
            .setMethodCallHandler { call, result ->
                if (call.method == "directory") result.success(filesDir.absolutePath)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "claviera/pdf")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                } else if (pdfResult != null) {
                    result.error("busy", "A PDF export is already in progress.", null)
                } else {
                    val pages = call.argument<List<ByteArray>>("pages")
                    val name = call.argument<String>("name")
                    if (pages.isNullOrEmpty() || name.isNullOrBlank()) {
                        result.error("invalid_pdf", "PDF pages and a name are required.", null)
                    } else {
                        pdfPages = pages
                        pdfResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("application/pdf")
                            .putExtra(Intent.EXTRA_TITLE, name)
                        try {
                            startActivityForResult(intent, pdfRequest)
                        } catch (error: android.content.ActivityNotFoundException) {
                            pdfPages = null
                            pdfResult = null
                            result.error("unavailable", "No app is available to save the PDF.", null)
                        }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "claviera/midi")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                } else if (midiResult != null) {
                    result.error("busy", "A MIDI export is already in progress.", null)
                } else {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name")
                    if (bytes == null || bytes.isEmpty() || name.isNullOrBlank()) {
                        result.error("invalid_midi", "MIDI data and a name are required.", null)
                    } else {
                        midiBytes = bytes
                        midiResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("audio/midi")
                            .putExtra(Intent.EXTRA_TITLE, name)
                        try {
                            startActivityForResult(intent, midiRequest)
                        } catch (error: android.content.ActivityNotFoundException) {
                            midiBytes = null
                            midiResult = null
                            result.error("unavailable", "No app is available to save the MIDI file.", null)
                        }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "claviera/musicxml")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                } else if (musicXmlResult != null) {
                    result.error("busy", "A MusicXML export is already in progress.", null)
                } else {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name")
                    if (bytes == null || bytes.isEmpty() || name.isNullOrBlank()) {
                        result.error("invalid_musicxml", "MusicXML data and a name are required.", null)
                    } else {
                        musicXmlBytes = bytes
                        musicXmlResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("application/vnd.recordare.musicxml+xml")
                            .putExtra(Intent.EXTRA_TITLE, name)
                        try {
                            startActivityForResult(intent, musicXmlRequest)
                        } catch (error: android.content.ActivityNotFoundException) {
                            musicXmlBytes = null
                            musicXmlResult = null
                            result.error("unavailable", "No app is available to save the MusicXML file.", null)
                        }
                    }
                }
            }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "claviera/piano_preview")
        channel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> initialize(result)
                    "play" -> {
                        val note = call.argument<Int>("midi")
                        if (note == null || note !in 0..127) {
                            result.error("invalid_note", "MIDI note must be between 0 and 127.", null)
                        } else {
                            play(note, result)
                        }

                    }
                    "stop" -> {
                        stopAfterMinimumDuration()
                        result.success(null)
                    }
                    "playScore" -> {
                        val notes = call.argument<List<Map<String, Int>>>("notes")
                        if (notes == null || notes.any {
                                val midi = it["midi"]
                                val start = it["startMs"]
                                val end = it["endMs"]
                                midi == null || midi !in 0..127 || start == null ||
                                    end == null || start < 0 || end <= start
                            }) {
                            result.error("invalid_score", "Invalid score playback data.", null)
                        } else if (pool == null || pendingInit != null || loadingFailed) {
                            result.error("not_ready", "Piano samples are not ready.", null)
                        } else {
                            startScore(notes)
                            result.success(null)
                        }
                    }
                    "stopScore" -> {
                        stopScore()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == musicXmlRequest) {
            val response = musicXmlResult ?: return
            val bytes = musicXmlBytes
            musicXmlResult = null
            musicXmlBytes = null
            if (resultCode != Activity.RESULT_OK) {
                response.success(false)
                return
            }
            val uri = data?.data
            if (uri == null || bytes == null) {
                response.error("save_failed", "The MusicXML destination is unavailable.", null)
                return
            }
            try {
                val output = contentResolver.openOutputStream(uri)
                    ?: throw IOException("Could not open the selected destination.")
                output.use { it.write(bytes) }
                response.success(true)
            } catch (error: IOException) {
                response.error("save_failed", "Could not save MusicXML: ${error.message}", null)
            } catch (error: SecurityException) {
                response.error("save_failed", "Cannot access MusicXML destination: ${error.message}", null)
            }
            return
        }
        if (requestCode == midiRequest) {
            val response = midiResult ?: return
            val bytes = midiBytes
            midiResult = null
            midiBytes = null
            if (resultCode != Activity.RESULT_OK) {
                response.success(false)
                return
            }
            val uri = data?.data
            if (uri == null || bytes == null) {
                response.error("save_failed", "The MIDI destination is unavailable.", null)
                return
            }
            try {
                val output = contentResolver.openOutputStream(uri)
                    ?: throw IOException("Could not open the selected destination.")
                output.use { it.write(bytes) }
                response.success(true)
            } catch (error: IOException) {
                response.error("save_failed", "Could not save MIDI: ${error.message}", null)
            } catch (error: SecurityException) {
                response.error("save_failed", "Cannot access MIDI destination: ${error.message}", null)
            }
            return
        }
        if (requestCode != pdfRequest) return
        val response = pdfResult ?: return
        val pages = pdfPages
        pdfResult = null
        pdfPages = null
        if (resultCode != Activity.RESULT_OK) {
            response.success(false)
            return
        }
        val uri: Uri? = data?.data
        if (uri == null || pages == null) {
            response.error("save_failed", "The PDF destination is unavailable.", null)
            return
        }
        val document = PdfDocument()
        try {
            for ((index, bytes) in pages.withIndex()) {
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw IOException("Could not decode PDF page ${index + 1}.")
                try {
                    val page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, index + 1).create())
                    page.canvas.drawBitmap(bitmap, null, Rect(0, 0, 595, 842), null)
                    document.finishPage(page)
                } finally {
                    bitmap.recycle()
                }
            }
            val output = contentResolver.openOutputStream(uri)
                ?: throw IOException("Could not open the selected destination.")
            output.use { document.writeTo(it) }
            response.success(true)
        } catch (error: IOException) {
            response.error("save_failed", "Could not save PDF: ${error.message}", null)
        } catch (error: SecurityException) {
            response.error("save_failed", "Cannot access PDF destination: ${error.message}", null)
        } finally {
            document.close()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (pool != null) {
            if (pendingInit != null) {
                result.error("initializing", "Piano samples are still loading.", null)
            } else if (loadingFailed) {
                result.error("sample_load_failed", "Unable to load piano samples.", null)
            } else {
                result.success(null)
            }
            return
        }
        val soundPool = SoundPool.Builder()
            .setMaxStreams(64)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
        pool = soundPool
        pendingInit = result
        soundPool.setOnLoadCompleteListener { _, _, status ->
            if (status != 0) loadingFailed = true
            loaded++
            if (loaded == roots.size) {
                val response = pendingInit
                pendingInit = null
                if (loadingFailed) {
                    response?.error("sample_load_failed", "Unable to decode piano samples.", null)
                } else {
                    response?.success(null)
                }
            }
        }
        try {
            for (root in roots) {
                assets.openFd("piano/$root.m4a").use { asset ->
                    val id = soundPool.load(asset, 1)
                    if (id == 0) {
                        throw IOException("Could not load sample $root.")
                    }
                    samples[root] = id
                }
            }
        } catch (error: IOException) {
            pendingInit = null
            loadingFailed = true
            soundPool.release()
            pool = null
            result.error("sample_load_failed", "Unable to load piano samples: ${error.message}", null)
        }
    }

    private fun startScore(notes: List<Map<String, Int>>) {
        stopScore()
        pendingStop?.let(handler::removeCallbacks)
        pendingStop = null
        if (stream != 0) pool?.stop(stream)
        stream = 0
        val epoch = SystemClock.uptimeMillis()
        for (note in notes) {
            val midi = note.getValue("midi")
            val root = roots.minBy { abs(it - midi) }
            val rate = 2.0.pow((midi - root) / 12.0).toFloat()
            val start = note.getValue("startMs").toLong()
            val end = note.getValue("endMs").toLong()
            val playTask = Runnable {
                val sound = pool?.play(samples.getValue(root), 1f, 1f, 1, 0, rate) ?: 0
                if (sound == 0) {
                    stopScore()
                    channel?.invokeMethod("playbackError", "Unable to play a score note.")
                } else {
                    playbackStreams.add(sound)
                    val stopTask = Runnable {
                        pool?.stop(sound)
                        playbackStreams.remove(sound)
                    }
                    scheduledPlayback.add(stopTask)
                    handler.postAtTime(stopTask, epoch + end)
                }
            }
            scheduledPlayback.add(playTask)
            handler.postAtTime(playTask, epoch + start)
        }
    }

    private fun stopScore() {
        for (task in scheduledPlayback) handler.removeCallbacks(task)
        scheduledPlayback.clear()
        for (sound in playbackStreams) pool?.stop(sound)
        playbackStreams.clear()
    }

    private fun play(note: Int, result: MethodChannel.Result) {
        val soundPool = pool
        if (soundPool == null || pendingInit != null || loadingFailed) {
            result.error("not_ready", "Piano samples are not ready.", null)
            return
        }
        val root = roots.minBy { abs(it - note) }
        val rate = 2.0.pow((note - root) / 12.0).toFloat()
        if (rate !in 0.5f..2.0f) {
            result.error("unsupported_pitch", "This pitch is outside the preview range.", null)
            return
        }
        pendingStop?.let(handler::removeCallbacks)
        pendingStop = null
        if (stream != 0) soundPool.stop(stream)
        stream = soundPool.play(samples.getValue(root), 1f, 1f, 1, 0, rate)
        if (stream == 0) {
            result.error("play_failed", "Unable to play the piano preview.", null)
        } else {
            startedAt = SystemClock.uptimeMillis()
            result.success(null)
        }
    }

    private fun stopAfterMinimumDuration() {
        pendingStop?.let(handler::removeCallbacks)
        val delay = (150 - (SystemClock.uptimeMillis() - startedAt)).coerceAtLeast(0)
        val stop = Runnable {
            if (stream != 0) pool?.stop(stream)
            stream = 0
            pendingStop = null
        }
        pendingStop = stop
        handler.postDelayed(stop, delay)
    }

    override fun onPause() {
        stopScore()
        pendingStop?.let(handler::removeCallbacks)
        pendingStop = null
        if (stream != 0) pool?.stop(stream)
        stream = 0
        super.onPause()
    }

    override fun onDestroy() {
        stopScore()
        pendingStop?.let(handler::removeCallbacks)
        pendingInit?.error("disposed", "Piano preview closed while loading.", null)
        pendingInit = null
        pool?.release()
        pool = null
        super.onDestroy()
    }
}
