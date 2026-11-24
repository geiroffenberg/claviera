package com.metamind.claviera

import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

internal class PianoScorePlayer(
    private val assets: AssetManager,
    private val roots: List<Int>,
    private val onError: (String) -> Unit,
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicInteger()
    private val trackLock = Any()
    private var track: AudioTrack? = null
    private val samples = mutableMapOf<Int, PianoSample>()

    fun prepare(result: MethodChannel.Result) {
        val revision = generation.get()
        worker.execute {
            try {
                for (root in roots) {
                    if (revision != generation.get()) break
                    if (root !in samples) samples[root] = decodePianoSample(assets, root)
                }
                main.post { result.success(revision == generation.get()) }
            } catch (error: IOException) {
                main.post { result.error("sample_load_failed", error.message, null) }
            } catch (error: IllegalStateException) {
                main.post { result.error("sample_load_failed", error.message, null) }
            } catch (error: IllegalArgumentException) {
                main.post { result.error("sample_load_failed", error.message, null) }
            }
        }
    }

    fun play(notes: List<PianoNote>, result: MethodChannel.Result) {
        if (notes.isEmpty()) {
            result.success(null)
            return
        }
        val revision = generation.get()
        worker.execute {
            var output: AudioTrack? = null
            var started = false
            fun fail(error: Exception) {
                main.post {
                    if (!started) {
                        result.error("play_failed", error.message, null)
                    } else if (revision == generation.get()) {
                        onError("Score playback failed: ${error.message}")
                    }
                }
            }
            try {
                if (samples.size != roots.size) throw IOException("Piano samples are not ready.")
                val mixer = PianoScoreMixer(samples, notes)
                val totalFrames = notes.maxOf { it.endMs.toLong() * mixer.sampleRate / 1000 }
                val attributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    attributes.setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_ALL)
                }
                val minimum = AudioTrack.getMinBufferSize(
                    mixer.sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT,
                )
                if (minimum <= 0) throw IOException("Piano audio output is unavailable.")
                val audio = AudioTrack.Builder()
                    .setAudioAttributes(attributes.build())
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                            .setSampleRate(mixer.sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .setBufferSizeInBytes(maxOf(minimum, 4096 * 4))
                    .build()
                output = audio
                if (audio.state != AudioTrack.STATE_INITIALIZED) {
                    throw IOException("Piano audio output could not be initialized.")
                }
                synchronized(trackLock) {
                    if (revision == generation.get()) track = audio
                }
                val buffer = FloatArray(1024)
                fun write(count: Int) {
                    var written = 0
                    while (written < count && revision == generation.get()) {
                        val size = audio.write(buffer, written, count - written, AudioTrack.WRITE_BLOCKING)
                        if (size <= 0) {
                            if (revision != generation.get()) break
                            throw IOException("Piano audio write failed ($size).")
                        }
                        written += size
                    }
                }
                while (revision == generation.get()) {
                    val count = mixer.read(buffer)
                    if (count == 0) break
                    write(count)
                    synchronized(trackLock) {
                        if (!started && revision == generation.get()) {
                            audio.play()
                            started = true
                            main.post { result.success(null) }
                        }
                    }
                }
                // Short scores must also fill Android's streaming start threshold.
                var padding = maxOf(0L, audio.bufferSizeInFrames - totalFrames)
                buffer.fill(0f)
                while (padding > 0 && revision == generation.get()) {
                    val count = minOf(padding, buffer.size.toLong()).toInt()
                    write(count)
                    padding -= count
                }
                // Blocking writes queue audio; wait for its playback before releasing the track.
                while (revision == generation.get() &&
                    audio.playbackHeadPosition.toLong() < totalFrames
                ) {
                    Thread.sleep(5)
                }
                if (!started) main.post { result.success(null) }
            } catch (error: IOException) {
                fail(error)
            } catch (error: IllegalStateException) {
                fail(error)
            } catch (error: IllegalArgumentException) {
                fail(error)
            } catch (error: UnsupportedOperationException) {
                fail(error)
            } catch (error: InterruptedException) {
                if (!started) main.post { result.success(null) }
                Thread.currentThread().interrupt()
            } finally {
                synchronized(trackLock) {
                    if (track === output) track = null
                    output?.release()
                }
            }
        }
    }

    fun stop() {
        generation.incrementAndGet()
        synchronized(trackLock) {
            track?.pause()
            track?.flush()
        }
    }

    fun close() {
        stop()
        worker.shutdownNow()
    }
}
