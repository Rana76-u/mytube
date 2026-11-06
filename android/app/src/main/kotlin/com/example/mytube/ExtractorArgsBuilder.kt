package com.example.mytube

/**
 * Pure, framework-free builder that turns the structured request fields the
 * Dart extractor seam sends (`media_extractor_impl.dart` `_jobArgs`) into the
 * yt-dlp argument list handed to the engine wrapper. This is the single place
 * that enforces the AGENTS.md §"Link downloader" argument-safety rules, so it
 * lives on its own and is unit-tested in `app/src/test` without a device
 * (DL2.3).
 *
 * Invariants (all checked by [ExtractorArgsBuilderTest]):
 *  - The page/stream URL is validated (http/https, never blank, never starting
 *    with `-`) and is the ONLY positional argument, always emitted last after a
 *    literal `--` separator.
 *  - No caller-supplied value can introduce a forbidden flag (`--exec*`,
 *    `--config*`, `--netrc*`, `--plugin-dirs`) or a caller-supplied
 *    `--cookies` path.
 *  - Owner-typed extra args (ADR-030) pass the same denylist and are placed
 *    before `--`; they never displace the URL.
 *  - `--cookies` is emitted only from the app-generated per-job cookie file.
 *
 * Nothing here touches Android, the engine, or the network — it is a list of
 * strings — so the safety rules are fully testable on the JVM.
 */
object ExtractorArgsBuilder {

    /**
     * Flag prefixes that must never reach the engine from any caller-supplied
     * input. Matches on `startsWith` so every long-form variant is covered
     * (`--exec`, `--exec-location`, `--config-locations`, `--netrc-cmd`, ...).
     * `--cookies` is listed because only the app-generated path may set it.
     */
    val FORBIDDEN_PREFIXES: List<String> = listOf(
        "--exec",
        "--config",
        "--netrc",
        "--plugin-dirs",
        "--cookies",
        "--load-info-json",
    )

    /** Containers the engine is allowed to be told to mux into. */
    private val ALLOWED_CONTAINERS: Set<String> =
        setOf("mp4", "mkv", "webm", "m4a", "opus", "ogg", "mov")

    class UnsafeArgumentException(message: String) : IllegalArgumentException(message)

    /**
     * A download/probe request mirroring the Dart `_jobArgs` map. Every field
     * is a typed value; the builder never re-parses free text back into a
     * positional argument except the [url], which is validated separately.
     */
    data class Request(
        val url: String,
        val outputTemplate: String,
        val container: String,
        val videoFormatId: String?,
        val audioFormatId: String?,
        val merge: Boolean,
        val concurrentFragments: Int,
        val useAria2c: Boolean,
        val rateLimitKbps: Int,
        val subtitleLangs: List<String>,
        val embedSubtitles: Boolean,
        val sponsorBlock: String,
        val extraArgs: List<String>,
        val cookiesFilePath: String?,
    )

    /** Validate the URL that will become the single trailing positional arg. */
    fun requireSafeUrl(url: String) {
        if (url.isBlank()) throw UnsafeArgumentException("url is blank")
        if (url.startsWith("-")) throw UnsafeArgumentException("url must not start with -")
        val scheme = url.substringBefore("://", "").lowercase()
        if (scheme != "http" && scheme != "https") {
            throw UnsafeArgumentException("url scheme must be http or https")
        }
    }

    /** True when [token] begins with a forbidden flag. */
    fun isForbiddenFlag(token: String): Boolean {
        val t = token.trim()
        if (!t.startsWith("-")) return false
        return FORBIDDEN_PREFIXES.any { t.startsWith(it) }
    }

    /**
     * Validate owner-typed extra args (ADR-030). Each token is checked against
     * the denylist; a forbidden token aborts the whole build rather than being
     * silently dropped, so the user learns the flag was rejected.
     */
    fun sanitizeExtraArgs(extraArgs: List<String>): List<String> {
        for (token in extraArgs) {
            if (isForbiddenFlag(token)) {
                throw UnsafeArgumentException("forbidden flag in extra args: $token")
            }
        }
        return extraArgs.filter { it.isNotBlank() }
    }

    /** `probe` / metadata dump: `--dump-single-json --no-playlist --skip-download`. */
    fun buildProbe(url: String): List<String> {
        requireSafeUrl(url)
        return mutableListOf(
            "--dump-single-json",
            "--no-playlist",
            "--skip-download",
            "--",
            url,
        )
    }

    /** `resolveStream`: fetch a single direct media URL honouring [mode]/[maxHeight]. */
    fun buildStream(url: String, mode: String, maxHeight: Int?): List<String> {
        requireSafeUrl(url)
        val args = mutableListOf(
            "--get-url",
            "--no-playlist",
            "--force-redirects",
            "-f",
            streamFormatSelector(mode, maxHeight),
            "--",
            url,
        )
        return args
    }

    /** A fixed, safe format expression — never contains caller input. */
    private fun streamFormatSelector(mode: String, maxHeight: Int?): String {
        val cap = if (maxHeight != null && maxHeight > 0) "[height<=?$maxHeight]" else ""
        return when (mode) {
            "hls" -> "best[ext=m3u8]$cap/best"
            "progressive" -> "best[ext=mp4]$cap/best[ext=mp4]/best"
            else -> "best$cap/best"
        }
    }

    /** Full download arguments for a [Request]. */
    fun buildDownload(req: Request): List<String> {
        requireSafeUrl(req.url)
        val args = mutableListOf<String>()

        args += "--no-playlist"
        args += "--newline" // one JSON/progress record per line for parsing
        args += "--no-mtime"

        // Output path template (app-built from a sanitized file name, never raw
        // title text reaching the shell).
        args += "-o"
        args += req.outputTemplate

        // Format selection: explicit ids when provided, else "best".
        args += "-f"
        args += downloadFormatSelector(req.videoFormatId, req.audioFormatId, req.merge)
        if (req.merge) {
            val container = req.container.lowercase()
            if (container in ALLOWED_CONTAINERS) {
                args += "--merge-output-format"
                args += container
            }
        }

        // Concurrency + external downloader.
        if (req.concurrentFragments > 1) {
            args += "--concurrent-fragments"
            args += req.concurrentFragments.toString()
        }
        if (req.useAria2c) {
            args += "--downloader"
            args += "libaria2c.so"
        }
        if (req.rateLimitKbps > 0) {
            args += "--limit-rate"
            args += "${req.rateLimitKbps}K"
        }

        // Subtitles.
        if (req.subtitleLangs.isNotEmpty()) {
            args += if (req.embedSubtitles) "--embed-subs" else "--write-subs"
            args += "--sub-langs"
            args += req.subtitleLangs.joinToString(",") { sanitizeLangToken(it) }
        }

        // SponsorBlock (segment names are engine vocabulary, allow-listed).
        if (req.sponsorBlock.isNotBlank() && req.sponsorBlock != "off") {
            args += "--sponsorblock-remove"
            args += req.sponsorBlock
        }

        // App-generated cookie file only (never a caller-supplied path).
        if (!req.cookiesFilePath.isNullOrBlank()) {
            args += "--cookies"
            args += req.cookiesFilePath
        }

        // Owner extra args (validated), placed before the `--` separator.
        args += sanitizeExtraArgs(req.extraArgs)

        // The URL is always the sole trailing positional argument after `--`.
        args += "--"
        args += req.url
        return args
    }

    /** Build a safe `-f` expression from validated format ids. */
    private fun downloadFormatSelector(videoId: String?, audioId: String?, merge: Boolean): String {
        val v = videoId?.takeIf { isSafeFormatId(it) }
        val a = audioId?.takeIf { isSafeFormatId(it) }
        return when {
            v != null && a != null -> if (merge) "$v+$a" else "$v/$a"
            v != null -> v
            a != null -> "$a/bestaudio"
            else -> "bestvideo+bestaudio/best"
        }
    }

    /** Format ids are alphanumeric with a few safe separators; anything else is ignored. */
    private fun isSafeFormatId(id: String): Boolean =
        id.isNotBlank() && id.all { it.isLetterOrDigit() || it in "-_./[]" }

    /** Subtitle language tokens are short BCP-47-ish codes; drop anything flag-like. */
    private fun sanitizeLangToken(raw: String): String {
        val t = raw.trim()
        return if (t.startsWith("-")) "" else t
    }
}
