package com.example.mytube

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android Picture-in-Picture bridge (P13-04, PLAY-010, PLAT-004).
 *
 * MethodChannel "com.example.mytube/pip":
 *  - isSupported : API 26+ *and* the FEATURE_PICTURE_IN_PICTURE system feature.
 *                False everywhere else, so the Dart side never shows a dead
 *                control and API 24–25 no-op safely (NFR-006).
 *  - enter       : requests [Activity.enterPictureInPictureMode] now, hinting the
 *                float window's aspect ratio when the Dart side supplied one
 *                (API 26+). The primary shrink-on-demand path.
 *  - setAutoEnter : toggles [Activity.setAutoEnterEnabled] so a Home press
 *                shrinks the video (API 31+ only; a no-op below that, leaving
 *                [enter] as the only way to float).
 *  - release     : clears the params so a future launch starts from defaults.
 *
 * The reverse path — the activity actually entering or leaving PiP — cannot be
 * observed from a plugin (the framework calls [android.app.Activity.onPictureInPictureModeChanged]
 * on the activity itself), so [MainActivity] overrides it and forwards here via
 * [notifyPipMode], which calls `onPipModeChanged` back on Dart. The Dart
 * `PipCoordinator` mirrors that onto its `inPip` listenable so the surfaces can
 * hide overlay chrome while floating; nothing here decides policy.
 */
class PipPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null

    // PiP params are a single immutable object, so the float aspect ratio and
    // the auto-enter flag must be carried together and re-applied whenever
    // either changes (a bare setPictureInPictureParams would drop the other).
    private var aspect: Rational? = null
    private var autoEnter = false

    /// Builds params from the tracked [aspect] and [autoEnter]. `setAspectRatio`
    /// needs API 26+ (guarded by [isSupported]); `setAutoEnterEnabled` is API 31+
    /// and is simply omitted below that, leaving the explicit enter() path.
    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
        aspect?.let { runCatching { builder.setAspectRatio(it) } }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            runCatching { builder.setAutoEnterEnabled(autoEnter) }
        }
        return builder.build()
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        PipPlugin.attach(channel!!)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        PipPlugin.detach()
    }

    // -- ActivityAware (PiP drives the Activity window) ------------------------

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

    // -- MethodChannel ---------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "enter" -> {
                val current = activity
                if (current == null || !isSupported()) {
                    result.success(null)
                    return
                }
                val args = call.arguments as? Map<*, *>
                val width = (args?.get("width") as? Number)?.toInt()
                val height = (args?.get("height") as? Number)?.toInt()
                // Android requires a positive ratio inside [1:2.39, 2.39:1]; the
                // Dart pipAspectFor already clamps, so guard only the nulls.
                aspect = if (width != null && height != null && width > 0 && height > 0) {
                    Rational(width, height)
                } else {
                    null
                }
                runCatching { current.enterPictureInPictureMode(buildParams()) }
                result.success(null)
            }
            "setAutoEnter" -> {
                val current = activity
                val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                    ?: false
                autoEnter = enabled
                // setAutoEnterEnabled is API 31+; lower levels simply keep the
                // explicit enter() path and ignore this (NFR-006).
                if (current != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    runCatching { current.setPictureInPictureParams(buildParams()) }
                }
                result.success(null)
            }
            "release" -> {
                val current = activity
                aspect = null
                autoEnter = false
                if (current != null && isSupported()) {
                    // Reset to default params so a later session starts clean.
                    runCatching {
                        current.setPictureInPictureParams(PictureInPictureParams.Builder().build())
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val context = activity ?: return false
        return context.packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/pip"

        private val mainHandler = Handler(Looper.getMainLooper())

        // Held statically so MainActivity (which is not a FlutterPlugin) can
        // report mode changes back to Dart. Cleared on engine detach.
        @Volatile
        private var channel: MethodChannel? = null

        fun attach(target: MethodChannel) {
            channel = target
        }

        fun detach() {
            channel = null
        }

        /// Forwards an PiP enter/leave transition from [MainActivity] to Dart.
        fun notifyPipMode(inPip: Boolean) {
            val target = channel ?: return
            // MethodChannel delivery must happen on the platform main thread.
            mainHandler.post { target.invokeMethod("onPipModeChanged", inPip) }
        }
    }
}
