package com.example.mytube

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit test for the argument-safety invariants in [ExtractorArgsBuilder]
 * (DL2.3). Runs on plain JUnit4 with no Android or engine dependency, so the
 * security rules are enforced by CI without a device.
 */
class ExtractorArgsBuilderTest {

    private fun request(
        url: String = "https://example.com/watch?v=1",
        extraArgs: List<String> = emptyList(),
        cookiesFilePath: String? = null,
    ) = ExtractorArgsBuilder.Request(
        url = url,
        outputTemplate = "/storage/emulated/0/Download/MyTube/staging/j1/%(title)s.%(ext)s",
        container = "mp4",
        videoFormatId = "137",
        audioFormatId = "140",
        merge = true,
        concurrentFragments = 8,
        useAria2c = true,
        rateLimitKbps = 0,
        subtitleLangs = emptyList(),
        embedSubtitles = true,
        sponsorBlock = "off",
        extraArgs = extraArgs,
        cookiesFilePath = cookiesFilePath,
    )

    @Test
    fun rejectsUrlStartingWithDash() {
        assertThrows(IllegalArgumentException::class.java) {
            ExtractorArgsBuilder.buildProbe("-f --exec rm")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ExtractorArgsBuilder.buildDownload(request(url = "--no-check-certificates"))
        }
    }

    @Test
    fun rejectsNonHttpSchemes() {
        for (bad in listOf("file:///x/y.mp4", "javascript:alert(1)", "ftp://h/f", "data:text/plain,hi")) {
            assertThrows("scheme: $bad", IllegalArgumentException::class.java) {
                ExtractorArgsBuilder.requireSafeUrl(bad)
            }
        }
    }

    @Test
    fun acceptsHttpAndHttps() {
        ExtractorArgsBuilder.requireSafeUrl("http://example.com/a")
        ExtractorArgsBuilder.requireSafeUrl("https://example.com/a")
    }

    @Test
    fun urlIsTheSoleTrailingArgAfterSeparator() {
        val probe = ExtractorArgsBuilder.buildProbe("https://example.com/v/1")
        assertEquals("https://example.com/v/1", probe.last())
        assertEquals("--", probe[probe.size - 2])

        val dl = ExtractorArgsBuilder.buildDownload(request())
        assertEquals("https://example.com/watch?v=1", dl.last())
        assertEquals("--", dl[dl.size - 2])
    }

    @Test
    fun neverEmitsForbiddenFlagsFromProbeOrDownload() {
        val all = ExtractorArgsBuilder.buildProbe("https://e/x") +
            ExtractorArgsBuilder.buildDownload(request())
        for (token in all) {
            if (token.startsWith("-")) {
                assertFalse("forbidden flag leaked: $token", isForbidden(token))
            }
        }
    }

    @Test
    fun rejectsForbiddenFlagInExtraArgs() {
        for (bad in listOf("--exec", "--exec-location", "--config-locations", "--netrc", "--netrc-cmd", "--plugin-dirs", "--cookies")) {
            assertThrows("extra: $bad", IllegalArgumentException::class.java) {
                ExtractorArgsBuilder.buildDownload(request(extraArgs = listOf(bad, "value")))
            }
        }
    }

    @Test
    fun allowsBenignExtraArgsBeforeSeparator() {
        val dl = ExtractorArgsBuilder.buildDownload(request(extraArgs = listOf("--limit-rate", "1M")))
        val dashDash = dl.indexOf("--")
        assertTrue(dl.contains("--limit-rate"))
        // extra args sit before the URL separator
        assertTrue(dl.indexOf("--limit-rate") < dashDash)
        assertEquals("https://example.com/watch?v=1", dl.last())
    }

    @Test
    fun cookiesOnlyFromAppGeneratedPath() {
        // No cookies path -> no --cookies flag at all.
        val none = ExtractorArgsBuilder.buildDownload(request())
        assertFalse(none.contains("--cookies"))

        // App-generated path -> exactly one --cookies followed by that path.
        val with = ExtractorArgsBuilder.buildDownload(
            request(cookiesFilePath = "/data/user/0/com.example.mytube/files/.run/j1/cookies.txt"),
        )
        val idx = with.indexOf("--cookies")
        assertTrue(idx >= 0)
        assertEquals("/data/user/0/com.example.mytube/files/.run/j1/cookies.txt", with[idx + 1])
    }

    @Test
    fun forbiddenFlagDetectionCoversLongForms() {
        assertTrue(ExtractorArgsBuilder.isForbiddenFlag("--exec"))
        assertTrue(ExtractorArgsBuilder.isForbiddenFlag("--exec-location"))
        assertTrue(ExtractorArgsBuilder.isForbiddenFlag("--config-locations"))
        assertTrue(ExtractorArgsBuilder.isForbiddenFlag("--netrc-cmd"))
        assertTrue(ExtractorArgsBuilder.isForbiddenFlag("--plugin-dirs"))
        assertTrue(ExtractorArgsBuilder.isForbiddenFlag("--cookies"))
        assertFalse(ExtractorArgsBuilder.isForbiddenFlag("--limit-rate"))
        assertFalse(ExtractorArgsBuilder.isForbiddenFlag("-f"))
        assertFalse(ExtractorArgsBuilder.isForbiddenFlag("https://not-a-flag"))
    }

    @Test
    fun streamBuilderHonoursModeAndCap() {
        val hls = ExtractorArgsBuilder.buildStream("https://e/x", "hls", 720)
        assertEquals("https://e/x", hls.last())
        assertEquals("--", hls[hls.size - 2])
        val fIndex = hls.indexOf("-f")
        assertTrue(hls[fIndex + 1].contains("m3u8"))
        assertTrue(hls[fIndex + 1].contains("720"))
    }

    private fun isForbidden(token: String): Boolean =
        ExtractorArgsBuilder.FORBIDDEN_PREFIXES.any { token.startsWith(it) }
}
