package com.metamind.claviera

import android.content.res.AssetManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal fun decodePianoSample(assets: AssetManager, root: Int): PianoSample {
    val extractor = MediaExtractor()
    try {
        assets.openFd("piano/$root.m4a").use {
            extractor.setDataSource(it.fileDescriptor, it.startOffset, it.length)
        }
        val format = extractor.getTrackFormat(0)
        val mime = format.getString(MediaFormat.KEY_MIME)
            ?: throw IOException("Piano sample $root has no audio format.")
        extractor.selectTrack(0)
        val decoder = MediaCodec.createDecoderByType(mime)
        try {
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            decoder.configure(format, null, null, 0)
            decoder.start()
            val info = MediaCodec.BufferInfo()
            val pcm = ByteArrayOutputStream()
            var inputEnded = false
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val deadline = SystemClock.elapsedRealtime() + 15000
            while (true) {
                if (SystemClock.elapsedRealtime() > deadline) {
                    throw IOException("Timed out decoding piano sample $root.")
                }
                if (!inputEnded) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val input = decoder.getInputBuffer(index)
                            ?: throw IOException("Piano decoder input is unavailable.")
                        input.clear()
                        val size = extractor.readSampleData(input, 0)
                        inputEnded = size < 0
                        decoder.queueInputBuffer(
                            index, 0, maxOf(0, size),
                            if (inputEnded) 0 else extractor.sampleTime,
                            if (inputEnded) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0,
                        )
                        if (!inputEnded) extractor.advance()
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val outputFormat = decoder.outputFormat
                    sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) != AudioFormat.ENCODING_PCM_16BIT
                    ) {
                        throw IOException("Piano decoder did not produce 16-bit audio.")
                    }
                } else if (index >= 0) {
                    val output = decoder.getOutputBuffer(index)
                        ?: throw IOException("Piano decoder output is unavailable.")
                    output.position(info.offset)
                    output.limit(info.offset + info.size)
                    val bytes = ByteArray(info.size)
                    output.get(bytes)
                    pcm.write(bytes)
                    decoder.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            if (sampleRate <= 0 || channels <= 0 || pcm.size() == 0 ||
                pcm.size() % (2 * channels) != 0
            ) {
                throw IOException("Piano sample $root contains invalid audio.")
            }
            val bytes = ByteBuffer.wrap(pcm.toByteArray()).order(ByteOrder.LITTLE_ENDIAN)
            val frames = FloatArray(bytes.remaining() / (2 * channels)) {
                var sum = 0f
                repeat(channels) { sum += bytes.short / 32768f }
                sum / channels
            }
            return PianoSample(sampleRate, frames)
        } finally {
            decoder.release()
        }
    } finally {
        extractor.release()
    }
}
