package com.example.mytube

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Native sidecar-subtitle picker for the player settings sheet (VP4.3).
 *
 * MethodChannel "com.example.mytube/captions":
 *  - pickSidecar : opens the system document picker filtered to subtitle text
 *                types, reads the chosen file to a UTF-8 string off the main
 *                thread, and replies with `{name, text}`. Cancelling replies
 *                with null so the Dart sheet can simply stay on its current
 *                state instead of showing an error.
 *
 * Kept separate from [SaffBridgePlugin] on purpose: that bridge is about video
 * *folders* and their persisted tree grants, whereas a caption is a one-shot
 * document read that needs no durable URI. The Dart caller drops the text
 * straight into the domain parser and never persists the URI, matching the
 * "never store a signed URI as identity" rule (AGENTS privacy).
 *
 * Nothing here logs the file name or contents; a subtitle could quote personal
 * context and the URI can reveal the storage layout.
 */
class CaptionsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private val SIDECAR_PICKER_REQUEST_CODE = 1003

    /** The mime types a subtitle sidecar is normally served as. */
    private val SUBTITLE_MIME_TYPES = arrayOf(
        "text/plain",
        "text/vtt",
        "application/x-subrip",
        "application/octet-stream",
    )

    /** Coroutine scope for the background file read; cancelled on detach. */
    private var ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // -------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        ioScope.cancel()
    }

    // -------------------------------------------------------------------------
    // ActivityAware
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    // -------------------------------------------------------------------------
    // MethodCallHandler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickSidecar" -> pickSidecar(result)
            else -> result.notImplemented()
        }
    }

    private fun pickSidecar(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
            ?: run {
                result.error("NO_ACTIVITY", "No activity attached", null)
                return
            }
        if (pendingPickResult != null) {
            // A second open while one is in flight: refuse rather than clobber
            // the pending reply so the first caller still completes.
            result.error("PICK_IN_PROGRESS", "A pick is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, SUBTITLE_MIME_TYPES)
            // One-shot read: no persistable grant is requested, so nothing is
            // left behind on the device after the file has been read.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, SIDECAR_PICKER_REQUEST_CODE)
    }

    // -------------------------------------------------------------------------
    // ActivityResultListener
    // -------------------------------------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SIDECAR_PICKER_REQUEST_CODE) return false
        val pending = pendingPickResult ?: return false
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            // Cancelled: reply null so the sheet stays on its current state.
            pending.success(null)
            return true
        }

        val uri = data.data!!
        val resolver = flutterPluginBinding.applicationContext.contentResolver
        val name = queryDisplayName(uri) ?: "subtitles"
        ioScope.launch {
            val outcome = runCatching {
                resolver.openInputStream(uri)?.use { input ->
                    input.readBytes().toString(Charsets.UTF_8)
                }
            }
            withContext(Dispatchers.Main) {
                val text = outcome.getOrNull()
                if (text == null) {
                    // Read failed (revoked grant, unreadable provider): surface a
                    // coded error the Dart side maps to a plain error state.
                    pending.error("READ_FAILED", "Could not read the file", null)
                } else {
                    pending.success(mapOf("name" to name, "text" to text))
                }
            }
        }
        return true
    }

    /** Resolves a human-readable display name; never throws, never logged. */
    private fun queryDisplayName(uri: Uri): String? {
        val resolver = flutterPluginBinding.applicationContext.contentResolver
        return runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) cursor.getString(index) else null
                    } else {
                        null
                    }
                }
        }.getOrNull()
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/captions"
    }
}
