package com.example.mytube

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.Assert.assertThrows

class ExtractorProbeResponseTest {
    @Test
    fun successfulProbeReturnsJsonOutput() {
        assertEquals(
            """{"title":"sample"}""",
            ExtractorProbeResponse.json(0, """{"title":"sample"}""", null),
        )
    }

    @Test
    fun failedProbeThrowsStderrInsteadOfReturningNonJsonOutput() {
        val error = assertThrows(IllegalStateException::class.java) {
            ExtractorProbeResponse.json(1, """{"incomplete":""", "ERROR: blocked")
        }
        assertEquals("ERROR: blocked", error.message)
    }

    @Test
    fun failedProbeFallsBackToStdoutThenExitCode() {
        val outputError = assertThrows(IllegalStateException::class.java) {
            ExtractorProbeResponse.json(2, "extractor error", " ")
        }
        assertEquals("extractor error", outputError.message)

        val emptyError = assertThrows(IllegalStateException::class.java) {
            ExtractorProbeResponse.json(3, null, null)
        }
        assertEquals("extractor probe failed (exit code 3)", emptyError.message)
    }
}
