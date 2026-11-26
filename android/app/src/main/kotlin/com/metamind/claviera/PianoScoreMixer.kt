package com.metamind.claviera

import kotlin.math.abs
import kotlin.math.pow

internal data class PianoSample(val sampleRate: Int, val frames: FloatArray)

internal data class PianoNote(
    val midi: Int,
    val startMs: Int,
    val endMs: Int,
    val volume: Int,
)

internal class PianoScoreMixer(
    samples: Map<Int, PianoSample>,
    notes: List<PianoNote>,
    val sampleRate: Int = 44100,
    wet: Float = 0.3f,
    tailMs: Int = 1500,
) {
    private data class Note(
        val start: Long,
        val end: Long,
        val sample: PianoSample,
        val step: Double,
        val volume: Float,
    )

    private val scheduled = notes.map { note ->
        val root = samples.keys.minBy { abs(it - note.midi) }
        val sample = samples.getValue(root)
        Note(
            note.startMs.toLong() * sampleRate / 1000,
            note.endMs.toLong() * sampleRate / 1000,
            sample,
            sample.sampleRate.toDouble() / sampleRate * 2.0.pow((note.midi - root) / 12.0),
            note.volume / 127f,
        )
    }.sortedBy { it.start }
    private val active = mutableListOf<Note>()
    private var next = 0
    private var position = 0L
    private val notesEnd = scheduled.maxOfOrNull { it.end } ?: 0L
    private val reverb = if (wet > 0f) Reverb(sampleRate, wet) else null
    // The reverb keeps ringing after the last note stops.
    val totalFrames = notesEnd + if (reverb != null) tailMs.toLong() * sampleRate / 1000 else 0L
    private val gain: Float
    private val releaseFrames = maxOf(1, sampleRate * 20 / 1000)

    init {
        // One constant gain for the score preserves dynamics without clipping chords.
        val changes = scheduled.flatMap { listOf(it.start to it.volume, it.end to -it.volume) }
            .sortedWith(compareBy<Pair<Long, Float>> { it.first }.thenBy { it.second })
        var level = 0f
        var peak = 1f
        for ((_, change) in changes) {
            level += change
            peak = maxOf(peak, level)
        }
        gain = 1f / peak
    }

    fun read(output: FloatArray): Int {
        val count = minOf(output.size.toLong(), totalFrames - position).toInt()
        if (count == 0) return 0
        output.fill(0f)
        val blockEnd = position + count
        active.removeAll { it.end <= position }
        while (next < scheduled.size && scheduled[next].start < blockEnd) {
            active.add(scheduled[next++])
        }
        for (note in active) {
            val start = maxOf(position, note.start)
            val stop = minOf(blockEnd, note.end)
            val release = minOf(releaseFrames.toLong(), note.end - note.start)
            for (frame in start until stop) {
                val source = (frame - note.start) * note.step
                if (source >= note.sample.frames.size) break
                val index = source.toInt()
                val fraction = (source - index).toFloat()
                val first = note.sample.frames[index]
                val second = note.sample.frames.getOrElse(index + 1) { 0f }
                val envelope = minOf(1f, (note.end - 1 - frame).toFloat() / release)
                output[(frame - position).toInt()] +=
                    (first + (second - first) * fraction) * note.volume * gain * envelope
            }
        }
        for (i in 0 until count) {
            val mixed = reverb?.let { output[i] + it.process(output[i]) } ?: output[i]
            output[i] = mixed.coerceIn(-1f, 1f)
        }
        position = blockEnd
        return count
    }
}

// Small Freeverb-style room: parallel damped combs feeding series allpasses.
private class Reverb(sampleRate: Int, private val wet: Float) {
    private class Comb(size: Int) {
        private val buffer = FloatArray(size)
        private var index = 0
        private var store = 0f

        fun process(input: Float): Float {
            val output = buffer[index]
            store = output * (1 - DAMP) + store * DAMP
            buffer[index] = input + store * FEEDBACK
            index = (index + 1) % buffer.size
            return output
        }
    }

    private class Allpass(size: Int) {
        private val buffer = FloatArray(size)
        private var index = 0

        fun process(input: Float): Float {
            val buffered = buffer[index]
            buffer[index] = input + buffered * 0.5f
            index = (index + 1) % buffer.size
            return buffered - input
        }
    }

    private val combs = COMB_SIZES.map { Comb(maxOf(1, (it * sampleRate / 44100.0).toInt())) }
    private val allpasses = ALLPASS_SIZES.map { Allpass(maxOf(1, (it * sampleRate / 44100.0).toInt())) }

    fun process(input: Float): Float {
        val scaled = input * 0.015f
        var sum = 0f
        for (comb in combs) sum += comb.process(scaled)
        for (allpass in allpasses) sum = allpass.process(sum)
        return sum * wet
    }

    private companion object {
        const val FEEDBACK = 0.78f
        const val DAMP = 0.4f
        val COMB_SIZES = intArrayOf(1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
        val ALLPASS_SIZES = intArrayOf(556, 441, 341, 225)
    }
}
