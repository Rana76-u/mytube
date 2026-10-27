package com.example.mytube

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.Size
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException

/**
 * Native thumbnail extraction (P7-01, P4-10).
 *
 * Channel: com.example.mytube/thumbnails
 *  - getThumbnail { uri: String, maxSidePx: Int } -> ByteArray (JPEG) or null
 *  - getNetworkThumbnail { uri: String, maxSidePx: Int, headers: Map<String,String> }
 *      -> ByteArray (JPEG) or null
 *
 * Error codes surface as PlatformException on the Dart side:
 *  - PERMISSION_DENIED  : the content grant (MediaStore permission or SAF
 *                         persistable URI) is no longer live.
 *  - NOT_FOUND          : the URI cannot be resolved to a readable file, or
 *                         the URL is not http(s).
 *  - NETWORK            : the remote host could not be reached.
 *  - THUMB_FAILED       : decode/encode problem.
 *
 * Strategy (quality first):
 *  1. MediaMetadataRetriever frame near the 1s mark, decoded straight to the
 *     requested size (getScaledFrameAtTime on API 27+ so a 4K frame never
 *     allocates a full-resolution bitmap) and rotated by the container's
 *     rotation metadata. This is the only path that is both sharp and
 *     correctly oriented for a full-width card.
 *  2. Fallback (local only) — ContentResolver.loadThumbnail (API 29+), the
 *     system's cached preview. It is much cheaper but capped at whatever
 *     MediaStore pre-generated (typically ~512px), so it only fills in when
 *     the frame cannot be decoded.
 *
 * A network source has no local file to decode, so [produceNetworkThumbnail]
 * opens the URL with the caller's headers and reuses the same frame
 * extraction: one synced frame is fetched, never the whole stream. The headers
 * matter — the probe and the player send the app User-Agent (P4-02), so a
 * server that gates on it must not see the preview arrive as a different
 * client.
 *
 * Decoding always happens on the IO dispatcher so the UI thread never
 * blocks (NFR-001), and at most [MAX_CONCURRENT_DECODES] frames are decoded
 * at once so a fast scroll cannot open dozens of decoders.
 */
class ThumbnailPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Bounds decoder pressure: every in-flight decode holds a full frame. */
    private val decodeLimiter = Semaphore(MAX_CONCURRENT_DECODES)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        channel = MethodChannel(binding.binaryMessenger, "com.example.mytube/thumbnails")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getThumbnail" -> getThumbnail(call, result)
            "getNetworkThumbnail" -> getNetworkThumbnail(call, result)
            else -> result.notImplemented()
        }
    }

    private fun getThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val maxSidePx = call.argument<Int>("maxSidePx") ?: DEFAULT_MAX_SIDE_PX
        val context = appContext
        if (uriString.isNullOrEmpty() || context == null) {
            result.error("NOT_FOUND", "Missing uri argument or detached engine", null)
            return
        }
        val uri = Uri.parse(uriString)
        // Decode on IO, reply on the main/channel thread like the other
        // plugins — MethodChannel.Result must be answered on the platform
        // thread it arrived on.
        scope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) {
                    produceThumbnail(context, uri, maxSidePx)
                }
                withContext(Dispatchers.Main) { result.success(bytes) }
            } catch (security: SecurityException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION_DENIED", security.message, null)
                }
            } catch (illegal: IllegalArgumentException) {
                // Unresolvable content URI / revoked document grant.
                withContext(Dispatchers.Main) {
                    result.error("NOT_FOUND", illegal.message, null)
                }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("THUMB_FAILED", error.message, null)
                }
            }
        }
    }

    /**
     * A frame of the stream at `uri`, decoded natively (P4-10).
     *
     * Only http(s) is accepted: a network preview is a frame of the player's
     * own target, and refusing anything else keeps this from becoming a
     * generic "fetch and decode whatever the caller passes" channel.
     */
    private fun getNetworkThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("uri")
        val maxSidePx = call.argument<Int>("maxSidePx") ?: DEFAULT_MAX_SIDE_PX
        if (url.isNullOrEmpty()) {
            result.error("NOT_FOUND", "Missing uri argument", null)
            return
        }
        if (!url.startsWith("http://", true) && !url.startsWith("https://", true)) {
            result.error("NOT_FOUND", "Only http(s) URLs have network previews", null)
            return
        }
        // Copy the caller's identity verbatim: whatever the probe and the
        // player present is what this request must present too.
        val headers = mutableMapOf<String, String>()
        call.argument<Map<*, *>>("headers")?.forEach { (key, value) ->
            if (key is String && value is String && key.isNotBlank() && value.isNotEmpty()) {
                headers[key] = value
            }
        }
        scope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) {
                    produceNetworkThumbnail(url, headers.toMap(), maxSidePx)
                }
                withContext(Dispatchers.Main) { result.success(bytes) }
            } catch (io: IOException) {
                // The host could not be reached — distinct from "decoded but
                // no frame", so the Dart side can report reachability.
                withContext(Dispatchers.Main) { result.error("NETWORK", io.message, null) }
            } catch (illegal: IllegalArgumentException) {
                withContext(Dispatchers.Main) { result.error("NOT_FOUND", illegal.message, null) }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) { result.error("THUMB_FAILED", error.message, null) }
            }
        }
    }

    private suspend fun produceThumbnail(
        context: Context,
        uri: Uri,
        maxSidePx: Int,
    ): ByteArray? = decodeLimiter.withPermit {
        val target = maxSidePx.coerceIn(MIN_MAX_SIDE_PX, MAX_MAX_SIDE_PX)
        // A real frame first: sharp and correctly oriented.
        val frame = decodeFrame(context, uri, target)
        val bitmap = frame ?: systemThumbnail(context, uri, target) ?: return@withPermit null
        bitmap.toJpegBytes()
    }

    /**
     * One frame of the network video at [url], fetched with [headers], encoded
     * as JPEG — or `null` when the host, the stream, or a frame is unusable.
     *
     * The retriever pulls only what it needs for the requested frame; the
     * stream is never downloaded in full. It runs under the same decode permit
     * as a local decode, so a grid of URL cards cannot open a burst of
     * downloaders. The cost of sharing the permit: a host that accepts the
     * connection and then stalls keeps one of [MAX_CONCURRENT_DECODES] busy
     * until the platform call returns. That only delays other tiles — the grid
     * keeps showing its placeholder, and nothing blocks the UI thread.
     */
    private suspend fun produceNetworkThumbnail(
        url: String,
        headers: Map<String, String>,
        maxSidePx: Int,
    ): ByteArray? = decodeLimiter.withPermit {
        val target = maxSidePx.coerceIn(MIN_MAX_SIDE_PX, MAX_MAX_SIDE_PX)
        val frame = decodeNetworkFrame(url, headers, target) ?: return@withPermit null
        frame.toJpegBytes()
    }

    /**
     * One frame near the 1s mark, scaled to [maxSidePx] and rotated according
     * to the container metadata, or `null` when the media cannot be decoded.
     */
    private fun decodeFrame(context: Context, uri: Uri, maxSidePx: Int): Bitmap? =
        withRetriever({ retriever -> retriever.setDataSource(context, uri) }, maxSidePx)

    /**
     * The same frame extraction for a network source: the retriever reads the
     * container straight off the URL, so only the headers and the data source
     * differ from [decodeFrame].
     */
    private fun decodeNetworkFrame(
        url: String,
        headers: Map<String, String>,
        maxSidePx: Int,
    ): Bitmap? = withRetriever({ retriever -> retriever.setDataSource(url, headers) }, maxSidePx)

    /** Opens one retriever via [open], extracts the frame, and always releases. */
    private fun withRetriever(
        open: (MediaMetadataRetriever) -> Unit,
        maxSidePx: Int,
    ): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            open(retriever)
            val frame = frameNear(retriever, maxSidePx) ?: return null
            val rotation = retriever.intMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
            ) ?: 0
            val rotated = rotate(frame, rotation)
            if (rotated !== frame) frame.recycle()
            rotated
        } catch (_: RuntimeException) {
            // Some devices throw on unparseable media; the caller falls back.
            null
        } catch (_: IllegalArgumentException) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // Best effort.
            }
        }
    }

    private fun frameNear(retriever: MediaMetadataRetriever, maxSidePx: Int): Bitmap? {
        val sourceWidth = retriever.intMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
        val sourceHeight = retriever.intMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
        // API 27+ can decode straight to the target size: a 4K frame never
        // lands in memory at full resolution. Aspect ratio is preserved so the
        // scaler cannot stretch the preview.
        val target: Pair<Int, Int>? = if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 &&
            sourceWidth != null && sourceWidth > 0 &&
            sourceHeight != null && sourceHeight > 0
        ) {
            scaledSize(sourceWidth, sourceHeight, maxSidePx)
        } else {
            null
        }

        for (timeUs in FRAME_TIMES_US) {
            if (target != null) {
                val scaled = retriever.getScaledFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    target.first,
                    target.second,
                )
                if (scaled != null) return scaled
            }
            val raw = retriever.getFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            )
            if (raw != null) {
                val downscaled = downscale(raw, maxSidePx)
                if (downscaled !== raw) raw.recycle()
                return downscaled
            }
        }
        return null
    }

    /** The system's pre-generated preview (Q+), or `null` when unavailable. */
    private fun systemThumbnail(context: Context, uri: Uri, maxSidePx: Int): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            context.contentResolver.loadThumbnail(uri, Size(maxSidePx, maxSidePx), null)
        } catch (_: Exception) {
            // Unresolvable or unsupported media.
            null
        }
    }

    private fun scaledSize(width: Int, height: Int, maxSidePx: Int): Pair<Int, Int> {
        val longest = maxOf(width, height)
        if (longest <= maxSidePx) return width to height
        val ratio = maxSidePx.toFloat() / longest.toFloat()
        return (width * ratio).toInt().coerceAtLeast(1) to
            (height * ratio).toInt().coerceAtLeast(1)
    }

    private fun downscale(source: Bitmap, maxSidePx: Int): Bitmap {
        val (width, height) = scaledSize(source.width, source.height, maxSidePx)
        if (width == source.width && height == source.height) return source
        return Bitmap.createScaledBitmap(source, width, height, true)
    }

    /** Applies rotation metadata so portrait clips are not shown sideways. */
    private fun rotate(source: Bitmap, degrees: Int): Bitmap {
        val normalized = ((degrees % 360) + 360) % 360
        if (normalized == 0) return source
        val matrix = Matrix().apply { postRotate(normalized.toFloat()) }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun MediaMetadataRetriever.intMetadata(key: Int): Int? =
        extractMetadata(key)?.toIntOrNull()

    /** JPEG-encodes the bitmap, flattening any alpha onto black. */
    private fun Bitmap.toJpegBytes(): ByteArray {
        val opaque = if (hasAlpha()) {
            // ARGB_8888 (not RGB_565): 16-bit colour would visibly band a
            // photographic frame before it is even compressed.
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { copy ->
                val canvas = Canvas(copy)
                canvas.drawColor(Color.BLACK)
                canvas.drawBitmap(this, 0f, 0f, null)
            }
        } else {
            this
        }
        val stream = ByteArrayOutputStream()
        opaque.compress(Bitmap.CompressFormat.JPEG, QUALITY, stream)
        return stream.toByteArray()
    }

    companion object {
        /**
         * Longest side decoded when the caller does not ask for a size. Kept in
         * sync with `ThumbnailBridge.defaultMaxSidePx` on the Dart side: a
         * full-width 16:9 card is ~1100 physical px on a high-density phone, so
         * a small preview is upscaled and reads as blurry.
         */
        private const val DEFAULT_MAX_SIDE_PX = 1080

        /** Guards against an absurd request turning into an OOM. */
        private const val MIN_MAX_SIDE_PX = 64
        private const val MAX_MAX_SIDE_PX = 1440

        /** High enough that the JPEG step is not the quality bottleneck. */
        private const val QUALITY = 90

        private const val MAX_CONCURRENT_DECODES = 2

        /** 1s in — avoids black leading frames in many encodes. */
        private val FRAME_TIMES_US = longArrayOf(1_000_000L, 0L)
    }
}
