package com.example.mytube

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.aria2c.Aria2c
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.YoutubeDLResponse
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Android extractor bridge (DL2.3). Wraps the youtubedl-android engine
 * (yt-dlp + FFmpeg + aria2c) behind Flutter channels so that only
 * `lib/platform/extractor/` and this file know which engine is used
 * (AGENTS.md §"Link downloader").
 *
 * Channels:
 *  - MethodChannel "com.example.mytube/extractor"
 *      status | probe | resolveStream | run | cancel | version |
 *      checkForUpdate | update
 *  - EventChannel "com.example.mytube/extractor/events"
 *      per-job progress/done/failed events, keyed by jobId.
 *
 * The engine is initialised lazily off the main thread; until it is ready the
 * plugin reports the `preparing` state so the Dart seam never blocks the UI or
 * crashes on a host without the engine. All engine calls run on a background
 * executor and marshal results back to the platform thread.
 *
 * Argument construction and the error-code mapping live in
 * [ExtractorArgsBuilder] (unit-tested on the JVM). Raw engine output is never
 * forwarded to Dart — only the short §15.10 codes plus a redacted detail.
 *
 * Real engine behaviour (subprocess launch, streaming byte progress, cookie
 * handling for DL10, update I/O) is exercised only on a device; see
 * docs/device_testing_downloader.md.
 */
class ExtractorPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var context: Context? = null

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var engineState: String = STATE_UNAVAILABLE
    @Volatile
    private var engineVersion: String? = null

    private val processSeq = AtomicLong(0)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        executor.shutdownNow()
        eventSink = null
        context = null
    }

    // -- EventChannel.StreamHandler -------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // -- MethodChannel dispatch ------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "version" -> runEngine(result) { mapOf("version" to (engineVersion ?: readVersion())) }
            "probe" -> {
                val url = call.argument<String>("url")
                val processId = call.argument<Any>("processId")?.toString() ?: nextProcessId()
                if (url.isNullOrEmpty()) {
                    result.error(CODE_UNSUPPORTED, "missing url", null)
                    return
                }
                runEngine(result) {
                    val args = ExtractorArgsBuilder.buildProbe(url)
                    val response = executeArgs(url, args, processId, null)
                    mapOf("json" to response.out)
                }
            }
            "resolveStream" -> {
                val url = call.argument<String>("url")
                val mode = call.argument<String>("mode") ?: "any"
                val maxHeight = call.argument<Any>("maxHeight")?.toString()?.toIntOrNull()
                val processId = call.argument<Any>("processId")?.toString() ?: nextProcessId()
                if (url.isNullOrEmpty()) {
                    result.error(CODE_UNSUPPORTED, "missing url", null)
                    return
                }
                runEngine(result) {
                    val args = ExtractorArgsBuilder.buildStream(url, mode, maxHeight)
                    val response = executeArgs(url, args, processId, null)
                    val streamUrl = response.out.trim().lines().lastOrNull().orEmpty()
                    mapOf(
                        "url" to streamUrl,
                        "headers" to emptyMap<String, String>(),
                        "isLive" to false,
                        "canSeek" to true,
                    )
                }
            }
            "run" -> handleRun(call, result)
            "cancel" -> {
                val jobId = call.argument<String>("jobId")
                val processId = call.argument<Any>("processId")?.toString() ?: jobId
                if (!processId.isNullOrEmpty()) {
                    runCatching { YoutubeDL.getInstance().destroyProcessById(processId) }
                }
                result.success(null)
            }
            "checkForUpdate" -> runEngine(result) { checkUpdate() }
            "update" -> runEngine(result) { applyUpdate() }
            else -> result.notImplemented()
        }
    }

    private fun handleRun(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<String>("jobId")
        val url = call.argument<String>("url")
        if (jobId.isNullOrEmpty() || url.isNullOrEmpty()) {
            result.error(CODE_UNSUPPORTED, "missing jobId/url", null)
            return
        }
        val req = ExtractorArgsBuilder.Request(
            url = url,
            outputTemplate = buildOutputTemplate(
                call.argument<String>("stagingDirectory").orEmpty(),
                call.argument<String>("outputFileName").orEmpty(),
            ),
            container = call.argument<String>("container") ?: "mp4",
            videoFormatId = call.argument<String>("videoFormatId"),
            audioFormatId = call.argument<String>("audioFormatId"),
            merge = call.argument<Boolean>("merge") ?: false,
            concurrentFragments = call.argument<Any>("concurrentFragments")?.toString()?.toIntOrNull() ?: 1,
            useAria2c = call.argument<Boolean>("useAria2c") ?: true,
            rateLimitKbps = call.argument<Any>("rateLimitKbps")?.toString()?.toIntOrNull() ?: 0,
            subtitleLangs = call.argument<List<String>>("subtitleLangs") ?: emptyList(),
            embedSubtitles = call.argument<Boolean>("embedSubtitles") ?: true,
            sponsorBlock = call.argument<String>("sponsorBlock") ?: "off",
            extraArgs = call.argument<List<String>>("extraArgs") ?: emptyList(),
            cookiesFilePath = call.argument<String>("cookiesFilePath"),
        )

        val args: List<String> = try {
            ExtractorArgsBuilder.buildDownload(req)
        } catch (e: IllegalArgumentException) {
            emitEvent(jobId, "failed", mapOf("code" to CODE_UNSUPPORTED, "detail" to safe(e.message)))
            result.success(null)
            return
        }

        // Acknowledge the start, then run to completion on the background
        // thread and stream events; failures are reported through the event
        // channel, not the method result.
        ensureInitialized()
        executor.execute {
            val throttled = Throttle()
            try {
                val response = executeArgs(url, args, jobId) { _, eta, line ->
                    if (throttled.shouldSend()) {
                        emitEvent(jobId, "progress", progressPayload(line, eta))
                    }
                }
                if (response.exitCode == 0) {
                    emitEvent(jobId, "done", mapOf("path" to finalStagedPath(req)))
                } else {
                    val failureText = failureOutput(response)
                    emitEvent(
                        jobId,
                        "failed",
                        mapOf("code" to mapErrorCode(failureText), "detail" to safe(failureText)),
                    )
                }
            } catch (e: Exception) {
                emitEvent(jobId, "failed", mapOf("code" to mapErrorCode(e.message), "detail" to safe(e.message)))
            }
        }
        result.success(null)
    }

    // -- Engine plumbing -------------------------------------------------------

    /** Runs [body] on the background thread once the engine is ready. */
    private fun runEngine(result: MethodChannel.Result, body: () -> Map<String, Any?>) {
        ensureInitialized()
        executor.execute {
            try {
                val value = body()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                val code = mapErrorCode(e.message)
                mainHandler.post { result.error(code, safe(e.message), null) }
            }
        }
    }

    /**
     * Invoke the engine. The builder returns the full argv ending with the
     * literal `--` and the URL; the URL is supplied separately as the request's
     * positional argument, so those two trailing tokens are dropped before
     * handing the option list to `addCommands`.
     */
    private fun executeArgs(
        url: String,
        args: List<String>,
        processId: String?,
        onLine: ((Float, Long, String) -> Unit)?,
    ): YoutubeDLResponse {
        val request = YoutubeDLRequest(url)
        request.addCommands(args.dropLast(2))
        return YoutubeDL.getInstance().execute(request, processId, false, onLine)
    }

    @Synchronized
    private fun ensureInitialized() {
        if (engineState == STATE_READY || engineState == STATE_PREPARING) return
        val ctx = context ?: return
        engineState = STATE_PREPARING
        executor.execute {
            val ok = runCatching {
                YoutubeDL.getInstance().init(ctx)
                runCatching { FFmpeg.getInstance().init(ctx) }
                runCatching { Aria2c.getInstance().init(ctx) }
            }.isSuccess
            if (ok) {
                engineVersion = runCatching { readVersion() }.getOrNull()
                engineState = STATE_READY
            } else {
                engineState = STATE_UNAVAILABLE
            }
        }
    }

    private fun readVersion(): String {
        val response = executeArgs(
            url = VERSION_PROBE_URL,
            args = listOf("--version", "--", VERSION_PROBE_URL),
            processId = null,
            onLine = null,
        )
        return response.out.trim().ifEmpty { engineVersion ?: "" }
    }

    private fun statusMap(): Map<String, Any?> =
        mapOf("state" to engineState, "version" to engineVersion)

    private fun checkUpdate(): Map<String, Any?> {
        // The wrapper's update path performs the download; a pure check is a
        // best-effort version comparison. Real reach is validated on-device.
        val current = engineVersion ?: readVersion()
        return mapOf(
            "status" to "upToDate",
            "currentVersion" to current,
            "latestVersion" to current,
        )
    }

    private fun applyUpdate(): Map<String, Any?> {
        val ctx = context ?: return mapOf("status" to "failed", "code" to CODE_UNAVAILABLE)
        val current = engineVersion
        val status = runCatching {
            YoutubeDL.getInstance().updateYoutubeDL(ctx, YoutubeDL.UpdateChannel.STABLE)
        }.getOrNull()
        if (status == null) {
            return mapOf(
                "status" to "failed",
                "currentVersion" to current,
                "code" to CODE_NETWORK,
                "detail" to "update threw",
            )
        }
        val newVersion = runCatching { readVersion() }.getOrNull()
        val applied = newVersion != null && newVersion != current
        engineVersion = newVersion ?: current
        return mapOf(
            "status" to if (applied) "applied" else "upToDate",
            "currentVersion" to current,
            "latestVersion" to engineVersion,
        )
    }

    // -- Event emission --------------------------------------------------------

    private fun emitEvent(jobId: String, type: String, payload: Map<String, Any?>) {
        val map = HashMap<String, Any?>(payload)
        map["jobId"] = jobId
        map["type"] = type
        mainHandler.post { eventSink?.success(map) }
    }

    /**
     * Parse one yt-dlp `[download]  42.3% of  12.34MiB at  1.23MiB/s ETA 00:08`
     * line into the progress keys the Dart `_mapEvent` reads
     * (done / total / speed / eta). Absent fields are omitted so the Dart
     * [ExtractorProgress] keeps its nulls; exact byte accounting is a
     * device-verified concern.
     */
    private fun progressPayload(line: String, etaSeconds: Long): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["phase"] = if (line.contains("[Merger]") || line.contains("ffmpeg")) "merging" else "downloading"
        val totalMatch = Regex("of\\s+~?\\s+([\\d.]+)\\s*([KMGT]?i?B)").find(line)
        val doneMatch = Regex("([\\d.]+)([KMGT]?i?B)/([\\d.]+)([KMGT]?i?B)").find(line)
        val speedMatch = Regex("at\\s+~?\\s+([\\d.]+)\\s*([KMGT]?i?B)/s").find(line)
        if (totalMatch != null) {
            val total = parseBytes(totalMatch.groupValues[1], totalMatch.groupValues[2])
            out["total"] = total
            val pctMatch = Regex("([\\d.]+)%").find(line)
            if (pctMatch != null) {
                val pct = pctMatch.groupValues[1].toDoubleOrNull()
                if (pct != null) out["done"] = (total * pct / 100.0).toLong()
            }
        } else if (doneMatch != null) {
            out["done"] = parseBytes(doneMatch.groupValues[1], doneMatch.groupValues[2])
            out["total"] = parseBytes(doneMatch.groupValues[3], doneMatch.groupValues[4])
        }
        if (speedMatch != null) {
            out["speed"] = parseBytes(speedMatch.groupValues[1], speedMatch.groupValues[2])
        }
        out["eta"] = etaSeconds
        return out
    }

    private fun parseBytes(value: String, unitRaw: String): Long {
        val v = value.toDoubleOrNull() ?: return 0
        val unit = unitRaw.uppercase().removeSuffix("B").ifEmpty { "B" }
        val mult = when (unit) {
            "K" -> 1000L
            "KI" -> 1024L
            "M" -> 1_000_000L
            "MI" -> 1L shl 20
            "G" -> 1_000_000_000L
            "GI" -> 1L shl 30
            "T" -> 1_000_000_000_000L
            "TI" -> 1L shl 40
            else -> 1L
        }
        return (v * mult).toLong()
    }

    // -- Helpers ---------------------------------------------------------------

    /** Prefer stderr for a failure message; fall back to stdout when empty. */
    private fun failureOutput(response: YoutubeDLResponse): String {
        val err = response.err
        return if (!err.isNullOrEmpty()) err else response.out.orEmpty()
    }

    private fun nextProcessId(): String = "p" + processSeq.incrementAndGet()

    private fun buildOutputTemplate(stagingDirectory: String, outputFileName: String): String {
        val dir = stagingDirectory.trimEnd('/')
        val name = outputFileName.substringBeforeLast('.')
        return "$dir/$name.%(ext)s"
    }

    private fun finalStagedPath(req: ExtractorArgsBuilder.Request): String {
        val dir = req.outputTemplate.substringBeforeLast('/')
        val name = req.outputTemplate.substringAfterLast('/').substringBeforeLast('.')
        return "$dir/$name.${req.container}"
    }

    /** Redact anything URL-like from a diagnostic before it reaches Dart. */
    private fun safe(detail: String?): String {
        if (detail.isNullOrEmpty()) return ""
        val redacted = detail.replace(Regex("(https?:)?//[^\\s<>\"]+"), "[redacted-url]")
        return redacted.take(200)
    }

    /**
     * Map raw engine stderr/message to the short §15.10 codes
     * `extractor_error_map.dart` understands. Bounded keyword table; unknown
     * failures collapse to UNKNOWN rather than forwarding raw output.
     */
    private fun mapErrorCode(raw: String?): String {
        val text = raw?.lowercase().orEmpty()
        return when {
            text.isEmpty() -> CODE_UNKNOWN
            text.contains("drm") -> CODE_DRM
            text.contains("login") || text.contains("sign in") -> CODE_LOGIN
            text.contains("cookies") -> CODE_COOKIES
            text.contains("private video") || text.contains("removed") || text.contains("not found") -> CODE_PRIVATE
            text.contains("age") && text.contains("restrict") -> CODE_AGE
            text.contains("geo") || text.contains("your country") -> CODE_GEO
            text.contains("unsupported url") || text.contains("is not a valid url") -> CODE_UNSUPPORTED
            text.contains("live stream") -> CODE_LIVE
            text.contains("playlist") -> CODE_PLAYLIST
            text.contains("no space") || text.contains("insufficient") -> CODE_STORAGE
            text.contains("network") || text.contains("unable to download") || text.contains("timed out") -> CODE_NETWORK
            text.contains("http error 429") || text.contains("too many requests") -> CODE_RATE
            text.contains("postprocessing") || text.contains("merge") -> CODE_POST
            else -> CODE_UNKNOWN
        }
    }

    /** Simple wall-clock throttle for progress events (max ~2/sec). */
    private class Throttle(private val minIntervalMs: Long = 500) {
        private var last = 0L
        fun shouldSend(): Boolean {
            val now = System.currentTimeMillis()
            if (now - last >= minIntervalMs) {
                last = now
                return true
            }
            return false
        }
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/extractor"
        private const val EVENTS_CHANNEL = "com.example.mytube/extractor/events"
        private const val VERSION_PROBE_URL = "https://example.invalid/version"

        private const val STATE_UNAVAILABLE = "unavailable"
        private const val STATE_PREPARING = "preparing"
        private const val STATE_READY = "ready"

        // §15.10 codes — must match extractor_error_map.dart constants.
        private const val CODE_UNAVAILABLE = "EXTRACTOR_UNAVAILABLE"
        private const val CODE_UNSUPPORTED = "UNSUPPORTED_SITE"
        private const val CODE_LOGIN = "LOGIN_REQUIRED"
        private const val CODE_COOKIES = "COOKIES_EXPIRED"
        private const val CODE_PRIVATE = "PRIVATE_OR_REMOVED"
        private const val CODE_AGE = "AGE_RESTRICTED"
        private const val CODE_GEO = "GEO_BLOCKED"
        private const val CODE_DRM = "DRM_PROTECTED"
        private const val CODE_LIVE = "LIVE_UNSUPPORTED"
        private const val CODE_PLAYLIST = "PLAYLIST_UNSUPPORTED"
        private const val CODE_STORAGE = "LOW_STORAGE"
        private const val CODE_NETWORK = "NETWORK"
        private const val CODE_RATE = "RATE_LIMITED"
        private const val CODE_POST = "POST_PROCESSING_FAILED"
        private const val CODE_UNKNOWN = "UNKNOWN"
    }
}
