package com.metamind.claviera

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

class PianoScoreMixerTest {
    @Test
    fun allFourPitchesExistInTheSameOutputStream() {
        val rate = 8000
        val frequency = 261.625565
        val sample = PianoSample(rate, FloatArray(rate * 2) {
            sin(2 * PI * frequency * it / rate).toFloat()
        })
        val pitches = listOf(60, 64, 67, 72)
        val mixer = PianoScoreMixer(
            mapOf(60 to sample),
            pitches.map { PianoNote(it, 0, 500, 127) },
            rate,
        )
        val output = FloatArray(rate / 2)
        assertEquals(output.size, mixer.read(output))
        for (pitch in pitches) {
            val expected = frequency * 2.0.pow((pitch - 60) / 12.0)
            var real = 0.0
            var imaginary = 0.0
            for (i in output.indices) {
                val phase = 2 * PI * expected * i / rate
                real += output[i] * cos(phase)
                imaginary += output[i] * sin(phase)
            }
            val amplitude = 2 * kotlin.math.sqrt(real * real + imaginary * imaginary) / output.size
            assertTrue("Missing MIDI pitch $pitch: amplitude $amplitude", amplitude > 0.20)
        }
        assertEquals(0, mixer.read(output))
    }

    @Test
    fun noteStopsAndGapsDoNotRemoveOtherVoices() {
        val mixer = PianoScoreMixer(
            mapOf(60 to PianoSample(1000, FloatArray(1000) { 1f })),
            listOf(
                PianoNote(60, 10, 30, 127),
                PianoNote(60, 20, 40, 127),
                PianoNote(60, 50, 60, 127),
            ),
            1000,
        )
        val output = FloatArray(60)
        assertEquals(60, mixer.read(output))
        assertTrue(output.slice(0 until 10).all { it == 0f })
        assertTrue(output.slice(10 until 20).all { it == 0.5f })
        assertTrue(output.slice(20 until 30).all { it == 1f })
        assertTrue(output.slice(30 until 40).all { it == 0.5f })
        assertTrue(output.slice(40 until 50).all { it == 0f })
        assertTrue(output.slice(50 until 60).all { it == 0.5f })
    }

    @Test
    fun chunkBoundariesPreservePitchTimingAndDynamics() {
        val notes = listOf(PianoNote(67, 13, 57, 64), PianoNote(60, 30, 70, 127))
        val samples = mapOf(60 to PianoSample(1000, FloatArray(100) { sin(it.toDouble()).toFloat() }))
        val whole = FloatArray(70)
        PianoScoreMixer(samples, notes, 1000).read(whole)
        val mixer = PianoScoreMixer(samples, notes, 1000)
        val chunks = mutableListOf<Float>()
        val buffer = FloatArray(7)
        while (true) {
            val count = mixer.read(buffer)
            if (count == 0) break
            chunks.addAll(buffer.take(count))
        }
        assertArrayEquals(whole, chunks.toFloatArray(), 0.00001f)
        assertTrue(whole.all { abs(it) <= 1f })
    }

    @Test
    fun sampleRateConversionAndQuietNotesRetainTheirValues() {
        val mixer = PianoScoreMixer(
            mapOf(60 to PianoSample(2000, floatArrayOf(0f, 0.25f, 0.5f, 0.75f))),
            listOf(PianoNote(60, 0, 4, 64)),
            1000,
        )
        val output = FloatArray(4)
        assertEquals(4, mixer.read(output))
        assertArrayEquals(floatArrayOf(0f, 0.5f * 64 / 127, 0f, 0f), output, 0.00001f)
    }
}
