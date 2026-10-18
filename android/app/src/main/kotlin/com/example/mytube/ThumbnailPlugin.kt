package com.example.mytube

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
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
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * Native thumbnail extraction for local video content (P7-01).
 *
 * Channel: com.example.mytube/thumbnails
 *  - getThumbnail { uri: String, maxSidePx: Int } -> ByteArray (JPEG) or null
 *
 * Error codes surface as PlatformException on the Dart side:
 *  - PERMISSION_DENIED  : the content grant (MediaStore permission or SAF
 *                         persistable URI) is no longer live.
 *  - NOT_FOUND          : the URI cannot be resolved to a readable file.
 *  - THUMB_FAILED       : decode/encode problem.
 *
 * Strategy:
 *  1. API 29+ — ContentResolver.loadThumbnail, which uses the system's
 *     cached video thumbnails when available (fast path, no full decode).
 *  2. Fallback (or when loadThumbnail fails) — MediaMetadataRetriever frame
 *     near the 1s mark, downscaled to the requested size.
 *
 * Decoding always happens on the IO dispatcher so the UI thread never
 * blocks (NFR-001).
 */
class ThumbnailPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

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

    private fun produceThumbnail(
        context: Context,
        uri: Uri,
        maxSidePx: Int,
    ): ByteArray? {
        // 1. System thumbnails on Q+: cheap — MediaStore keeps them cached.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val bitmap = context.contentResolver.loadThumbnail(uri, Size(maxSidePx, maxSidePx), null)
                return bitmap.toJpegBytes()
            } catch (_: Exception) {
                // Fall through to the retriever path.
            }
        }

        // 2. Frame grab + downscale for pre-Q devices or failed system calls.
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            // 1s in — avoids black leading frames in many encodes.
            val raw =
                retriever.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: return null
            downscale(raw, maxSidePx).toJpegBytes()
        } catch (_: RuntimeException) {
            // Some devices throw on unparseable media.
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // Best effort.
            }
        }
    }

    private fun downscale(source: Bitmap, maxSidePx: Int): Bitmap {
        val longest = maxOf(source.width, source.height)
        if (longest <= maxSidePx) return source
        val ratio = maxSidePx.toFloat() / longest.toFloat()
        return Bitmap.createScaledBitmap(
            source,
            (source.width * ratio).toInt().coerceAtLeast(1),
            (source.height * ratio).toInt().coerceAtLeast(1),
            true,
        )
    }

    /** JPEG-encodes the bitmap, flattening any alpha onto black. */
    private fun Bitmap.toJpegBytes(): ByteArray {
        val opaque = if (hasAlpha()) {
            Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565).also { copy ->
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
        private const val DEFAULT_MAX_SIDE_PX = 256
        private const val QUALITY = 85
    }
}
