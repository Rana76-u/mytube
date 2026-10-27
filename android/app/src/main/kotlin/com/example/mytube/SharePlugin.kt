package com.example.mytube

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android "share this video" bridge (plan M8 — DESIGN.md action toolbar).
 *
 * MethodChannel "com.example.mytube/share":
 *  - shareFile : hands a video URI to the system chooser through
 *                [Intent.ACTION_SEND], granting the receiver temporary read
 *                access with [Intent.FLAG_GRANT_READ_URI_PERMISSION]. Returns
 *                true when a chooser was shown and false when nothing could
 *                handle the request, so the Dart side can degrade to a
 *                user-safe message instead of a dead button (NFR-006).
 *
 * Two URI shapes arrive here and both work unchanged:
 *  - SAF `content://com.android.externalstorage.documents/...` (the tree grant
 *    the app already holds, P3-02) and MediaStore `content://media/...` — the
 *    grant flag lets the receiver read them for the duration of the intent;
 *  - plain `file://` URIs, which modern Android forbids in an intent
 *    (`FileUriExposedException`), so they are re-served through the app's
 *    [FileProvider] (see res/xml/file_paths.xml) before sharing.
 *
 * The URI is never logged: it can identify the user's local storage layout
 * (AGENTS privacy rules).
 */
class SharePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {

    private var channel: MethodChannel? = null
    private var activity: android.app.Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        appContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareFile" -> {
                val args = call.arguments as? Map<*, *>
                val rawUri = args?.get("uri") as? String
                val mimeType = (args?.get("mimeType") as? String) ?: "video/*"
                if (rawUri.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                result.success(share(rawUri, mimeType))
            }
            else -> result.notImplemented()
        }
    }

    /** Returns true when a chooser was shown. Never throws. */
    private fun share(rawUri: String, mimeType: String): Boolean {
        val current = activity ?: return false
        return runCatching {
            val shareUri = when {
                rawUri.startsWith("file://") -> fileToContentUri(rawUri) ?: return false
                else -> Uri.parse(rawUri)
            }
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, shareUri)
                // The receiver must not be able to hold on to the grant.
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, null)
            current.startActivity(chooser)
            true
        }.getOrDefault(false)
    }

    /**
     * Re-serves a `file://` path through the app's [androidx.core.content.FileProvider]
     * so the receiver gets a grantable `content://` URI instead of an
     * unreadable (and on API 24+ illegal) file path.
     */
    private fun fileToContentUri(rawUri: String): Uri? {
        val context = appContext ?: return null
        val path = Uri.parse(rawUri).path ?: return null
        return runCatching {
            androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                java.io.File(path),
            )
        }.getOrNull()
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/share"

        // Held statically so file:// re-serving works even before an activity
        // attaches; cleared on engine detach.
        @Volatile
        private var appContext: android.content.Context? = null
    }
}
