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
            wet = 0f,
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
            wet = 0f,
        )
        val output = FloatArray(140)
        assertEquals(140, mixer.read(output))
        assertTrue(output.slice(0 until 10).all { it == 0f })
        assertTrue(output.slice(10 until 30).all { it == 0.5f })
        assertTrue(output.slice(30 until 50).all { it == 1f })
        assertEquals(0.5f, output[69], 0.00001f)
        assertEquals(0.5f, output[70], 0.00001f)
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
            wet = 0f,
        )
        val output = FloatArray(55)
        assertEquals(55, mixer.read(output))
        assertEquals(1f, output[29], 0.00001f)
        assertEquals(0.9f, output[30], 0.00001f)
        assertEquals(0f, output[39], 0.00001f)
        assertEquals(0.8f, output[50], 0.00001f)
        assertEquals(0f, output[54], 0.00001f)
    }

    @Test
    fun releaseIsTenMillisecondsAtPlaybackSampleRate() {
        val rate = 44100
        val mixer = PianoScoreMixer(
            mapOf(60 to PianoSample(rate, FloatArray(rate) { 1f })),
            listOf(PianoNote(60, 0, 100, 127)),
            rate,
            wet = 0f,
        )
        val output = FloatArray(rate / 10)
        assertEquals(output.size, mixer.read(output))
        assertEquals(1f, output[output.size - 442], 0.00001f)
        assertEquals(440f / 441, output[output.size - 441], 0.00001f)
        assertEquals(0f, output.last(), 0f)
        assertEquals(0, mixer.read(output))
    }

    @Test
    fun chunkBoundariesPreservePitchTimingAndDynamics() {
        val notes = listOf(PianoNote(67, 13, 57, 64), PianoNote(60, 30, 70, 127))
        val samples = mapOf(60 to PianoSample(1000, FloatArray(100) { sin(it.toDouble()).toFloat() }))
        val whole = FloatArray(70)
        PianoScoreMixer(samples, notes, 1000, wet = 0f).read(whole)
        val mixer = PianoScoreMixer(samples, notes, 1000, wet = 0f)
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
            wet = 0f,
        )
        val output = FloatArray(4)
        assertEquals(4, mixer.read(output))
        assertArrayEquals(floatArrayOf(0f, 0.5f * 64 / 127 * 2, 0f, 0f), output, 0.00001f)
    }

    @Test
    fun quieterSamplesAreAmplifiedWithoutClippingChords() {
        val samples = mapOf(60 to PianoSample(1000, FloatArray(100) { 0.2f }))
        val solo = PianoScoreMixer(samples, listOf(PianoNote(60, 0, 100, 127)), 1000, wet = 0f)
        val soloOutput = FloatArray(100)
        solo.read(soloOutput)
        assertEquals(0.4f, soloOutput[0], 0.00001f)

        val chord = PianoScoreMixer(samples, List(8) { PianoNote(60, 0, 100, 127) }, 1000, wet = 0f)
        val chordOutput = FloatArray(100)
        chord.read(chordOutput)
        assertEquals(1f, chordOutput[0], 0.00001f)
        assertTrue(chordOutput.all { abs(it) <= 1f })
    }

    @Test
    fun gainRemainsConstantAcrossNotesWithDifferentDynamics() {
        val samples = mapOf(60 to PianoSample(1000, FloatArray(200) { 0.2f }))
        val notes = listOf(PianoNote(60, 0, 100, 127), PianoNote(60, 100, 200, 64))
        val mixer = PianoScoreMixer(samples, notes, 1000, wet = 0f)
        val output = FloatArray(200)
        mixer.read(output)
        assertEquals(0.4f, output[0], 0.00001f)
        assertEquals(0.4f * 64 / 127, output[100], 0.00001f)
    }

    @Test
    fun reverbRingsAfterTheLastNoteThenDecays() {
        val rate = 8000
        val mixer = PianoScoreMixer(
            mapOf(60 to PianoSample(rate, FloatArray(rate) { sin(2 * PI * 440 * it / rate).toFloat() })),
            listOf(PianoNote(60, 0, 250, 127)),
            rate,
            tailMs = 1500,
        )
        assertEquals(250L * rate / 1000 + 1500L * rate / 1000, mixer.totalFrames)
        val output = FloatArray(mixer.totalFrames.toInt())
        assertEquals(output.size, mixer.read(output))
        assertEquals(0, mixer.read(output))
        val noteEnd = 250 * rate / 1000
        fun peak(from: Int, to: Int) = output.slice(from until to).maxOf { abs(it) }
        assertTrue(peak(noteEnd + 200, noteEnd + 2200) > 0.001f)
        assertTrue(peak(output.size - 1000, output.size) < peak(noteEnd + 200, noteEnd + 2200))
        assertTrue(output.all { abs(it) <= 1f })
    }

    @Test
    fun reverbSettingsChangeTailAndFeedback() {
        val rate = 8000
        val samples = mapOf(60 to PianoSample(rate, FloatArray(rate) {
            sin(2 * PI * 440 * it / rate).toFloat()
        }))
        val notes = listOf(PianoNote(60, 0, 250, 127))
        fun render(feedback: Float): FloatArray {
            val mixer = PianoScoreMixer(samples, notes, rate, wet = 0.8f,
                tailMs = 2000, feedback = feedback, damping = 0.4f)
            return FloatArray(mixer.totalFrames.toInt()).also { mixer.read(it) }
        }
        val low = render(0.5f)
        val high = render(0.9f)
        val start = rate
        val end = rate * 2
        assertTrue(high.slice(start until end).sumOf { (it * it).toDouble() } >
            low.slice(start until end).sumOf { (it * it).toDouble() })
        assertEquals(0f, high.last(), 0f)
        val dry = PianoScoreMixer(samples, notes, rate, wet = 0f, tailMs = 2000)
        assertEquals(2000L, dry.totalFrames)
    }

    @Test
    fun dampingAndLevelAffectReverbOutput() {
        val rate = 8000
        val samples = mapOf(60 to PianoSample(rate, FloatArray(rate) {
            sin(2 * PI * 1800 * it / rate).toFloat()
        }))
        val notes = listOf(PianoNote(60, 0, 250, 127))
        fun render(wet: Float, damping: Float): FloatArray {
            val mixer = PianoScoreMixer(samples, notes, rate, wet = wet, damping = damping)
            return FloatArray(mixer.totalFrames.toInt()).also { mixer.read(it) }
        }
        fun energy(output: FloatArray) =
            output.slice(2000 until 5000).sumOf { (it * it).toDouble() }
        val quiet = render(0.2f, 0f)
        val loud = render(0.8f, 0f)
        val damped = render(0.8f, 0.8f)
        assertTrue(energy(loud) > energy(quiet))
        assertTrue(energy(damped) < energy(loud))
    }
}
