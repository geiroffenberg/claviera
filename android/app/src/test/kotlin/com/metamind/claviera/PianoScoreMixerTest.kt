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
                PianoNote(60, 10, 70, 127),
                PianoNote(60, 30, 90, 127),
                PianoNote(60, 100, 140, 127),
            ),
            1000,
        )
        val output = FloatArray(140)
        assertEquals(140, mixer.read(output))
        assertTrue(output.slice(0 until 10).all { it == 0f })
        assertTrue(output.slice(10 until 30).all { it == 0.5f })
        assertTrue(output.slice(30 until 50).all { it == 1f })
        assertEquals(0.5f, output[69], 0.00001f)
        assertEquals(0.475f, output[70], 0.00001f)
        assertEquals(0f, output[89], 0.00001f)
        assertTrue(output.slice(90 until 100).all { it == 0f })
        assertTrue(output.slice(100 until 120).all { it == 0.5f })
        assertEquals(0f, output[139], 0.00001f)
    }

    @Test
    fun releaseFadesToSilenceEvenForShortNotes() {
        val mixer = PianoScoreMixer(
            mapOf(60 to PianoSample(1000, FloatArray(100) { 1f })),
            listOf(PianoNote(60, 0, 40, 127), PianoNote(60, 50, 55, 127)),
            1000,
        )
        val output = FloatArray(55)
        assertEquals(55, mixer.read(output))
        assertEquals(1f, output[19], 0.00001f)
        assertEquals(0.95f, output[20], 0.00001f)
        assertEquals(0f, output[39], 0.00001f)
        assertEquals(0.8f, output[50], 0.00001f)
        assertEquals(0f, output[54], 0.00001f)
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
            listOf(PianoNote(60, 0, 30, 64)),
            1000,
        )
        val output = FloatArray(4)
        assertEquals(4, mixer.read(output))
        assertArrayEquals(floatArrayOf(0f, 0.5f * 64 / 127, 0f, 0f), output, 0.00001f)
    }
}
