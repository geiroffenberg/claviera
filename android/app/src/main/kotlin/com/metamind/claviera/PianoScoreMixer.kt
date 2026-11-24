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
    private val end = scheduled.maxOfOrNull { it.end } ?: 0L
    private val gain: Float

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
        val count = minOf(output.size.toLong(), end - position).toInt()
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
            for (frame in start until stop) {
                val source = (frame - note.start) * note.step
                if (source >= note.sample.frames.size) break
                val index = source.toInt()
                val fraction = (source - index).toFloat()
                val first = note.sample.frames[index]
                val second = note.sample.frames.getOrElse(index + 1) { 0f }
                output[(frame - position).toInt()] +=
                    (first + (second - first) * fraction) * note.volume * gain
            }
        }
        for (i in 0 until count) output[i] = output[i].coerceIn(-1f, 1f)
        position = blockEnd
        return count
    }
}
