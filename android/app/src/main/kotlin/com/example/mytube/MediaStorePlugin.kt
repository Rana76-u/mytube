package com.example.mytube

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class MediaStorePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val PERMISSION_REQUEST_CODE = 1001

    /** Delete confirmation intent in flight, and the ids it was asked about. */
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteUris: List<String> = emptyList()
    private val DELETE_REQUEST_CODE = 1003

    // -------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        channel = MethodChannel(binding.binaryMessenger, "com.example.mytube/media_store")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // -------------------------------------------------------------------------
    // ActivityAware
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    // -------------------------------------------------------------------------
    // MethodCallHandler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "queryVideos" -> queryVideos(result)
            "checkPermission" -> result.success(checkPermissionStatus())
            "requestPermission" -> requestPermission(result)
            "deleteVideos" -> deleteVideos(call, result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Permission helpers
    // -------------------------------------------------------------------------

    /**
     * Returns the current permission status as one of:
     * "granted", "partiallyGranted", "denied", "permanentlyDenied".
     *
     * Limitation: `permanentlyDenied` requires an attached Activity to call
     * `shouldShowRequestPermissionRationale`. If this method is called before
     * the activity attaches (e.g. during background wake), it cannot distinguish
     * "denied" from "permanentlyDenied" and returns "denied" as a safe fallback.
     * Callers should ensure this is invoked while a foreground Activity is
     * attached (i.e. after [onAttachedToActivity]).
     */
    private fun checkPermissionStatus(): String {
        val context = flutterPluginBinding.applicationContext
        val activity = activityBinding?.activity

        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                // API 34+: READ_MEDIA_VIDEO + READ_MEDIA_VISUAL_USER_SELECTED
                val videoGranted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.READ_MEDIA_VIDEO,
                ) == PackageManager.PERMISSION_GRANTED
                val partialGranted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                ) == PackageManager.PERMISSION_GRANTED

                when {
                    videoGranted -> "granted"
                    partialGranted -> "partiallyGranted"
                    else -> {
                        if (activity != null &&
                            !ActivityCompat.shouldShowRequestPermissionRationale(
                                activity,
                                Manifest.permission.READ_MEDIA_VIDEO,
                            )
                        ) {
                            "permanentlyDenied"
                        } else {
                            "denied"
                        }
                    }
                }
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                // API 33: READ_MEDIA_VIDEO
                val granted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.READ_MEDIA_VIDEO,
                ) == PackageManager.PERMISSION_GRANTED

                if (granted) {
                    "granted"
                } else if (activity != null &&
                    !ActivityCompat.shouldShowRequestPermissionRationale(
                        activity,
                        Manifest.permission.READ_MEDIA_VIDEO,
                    )
                ) {
                    "permanentlyDenied"
                } else {
                    "denied"
                }
            }
            else -> {
                // API 24–32: READ_EXTERNAL_STORAGE
                val granted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                ) == PackageManager.PERMISSION_GRANTED

                if (granted) {
                    "granted"
                } else if (activity != null &&
                    !ActivityCompat.shouldShowRequestPermissionRationale(
                        activity,
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                    )
                ) {
                    "permanentlyDenied"
                } else {
                    "denied"
                }
            }
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
            ?: run {
                result.error("NO_ACTIVITY", "No activity attached", null)
                return
            }

        pendingPermissionResult = result

        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                arrayOf(
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
            else ->
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        ActivityCompat.requestPermissions(activity, permissions, PERMISSION_REQUEST_CODE)
    }

    // -------------------------------------------------------------------------
    // RequestPermissionsResultListener
    // -------------------------------------------------------------------------

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        pendingPermissionResult?.success(checkPermissionStatus())
        pendingPermissionResult = null
        return true
    }

    // -------------------------------------------------------------------------
    // Delete (ADR-017)
    // -------------------------------------------------------------------------

    /**
     * Deletes the given MediaStore rows.
     *
     * API 30+ routes through `MediaStore.createDeleteRequest`, which shows one
     * system confirmation for the whole batch — an app may not silently delete
     * another app's media. Below API 30 there is no such request, so the rows are
     * deleted directly and each URI is reported on its own.
     *
     * Every requested id is accounted for in the reply: the Dart side treats a
     * missing id as "kept", so this method must never drop one.
     */
    private fun deleteVideos(call: MethodCall, result: MethodChannel.Result) {
        val requested = call.argument<List<String>>("contentUris")
        if (requested.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "Missing 'contentUris' argument", null)
            return
        }
        val uris = requested.map { Uri.parse(it) }
        val context = flutterPluginBinding.applicationContext

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val activity = activityBinding?.activity
                ?: run {
                    result.error("NO_ACTIVITY", "No activity attached", null)
                    return
                }
            try {
                val confirmation =
                    MediaStore.createDeleteRequest(context.contentResolver, uris)
                pendingDeleteResult = result
                pendingDeleteUris = requested
                activity.startIntentSenderForResult(
                    confirmation.intentSender,
                    DELETE_REQUEST_CODE,
                    null,
                    0,
                    0,
                    0,
                )
            } catch (e: Exception) {
                pendingDeleteResult = null
                pendingDeleteUris = emptyList()
                result.error(
                    "DELETE_FAILED",
                    "Delete request could not start: ${e.message}",
                    null,
                )
            }
            return
        }

        val deleted = mutableListOf<String>()
        val failed = mutableListOf<String>()
        requested.forEachIndexed { index, id ->
            try {
                val rows = context.contentResolver.delete(uris[index], null, null)
                if (rows > 0) deleted.add(id) else failed.add(id)
            } catch (e: Exception) {
                // Most often a RecoverableSecurityException: the app no longer
                // owns this row and cannot ask for it below API 30.
                failed.add(id)
            }
        }
        result.success(mapOf("deleted" to deleted, "failed" to failed))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != DELETE_REQUEST_CODE) return false
        val pending = pendingDeleteResult ?: return false
        val requested = pendingDeleteUris
        pendingDeleteResult = null
        pendingDeleteUris = emptyList()

        // The system dialog reports approval for the batch, not per item.
        val deleted: List<String>
        val failed: List<String>
        if (resultCode == Activity.RESULT_OK) {
            deleted = requested
            failed = emptyList()
        } else {
            deleted = emptyList()
            failed = requested
        }
        pending.success(mapOf("deleted" to deleted, "failed" to failed))
        return true
    }

    // -------------------------------------------------------------------------
    // Query
    // -------------------------------------------------------------------------

    private fun queryVideos(result: MethodChannel.Result) {
        val context = flutterPluginBinding.applicationContext
        val status = checkPermissionStatus()
        if (status != "granted" && status != "partiallyGranted") {
            result.error("PERMISSION_DENIED", "Video read permission not granted", null)
            return
        }

        val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.MIME_TYPE,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.DATE_MODIFIED,
        )

        val cursor = try {
            context.contentResolver.query(uri, projection, null, null, null)
        } catch (e: Exception) {
            result.error("QUERY_FAILED", "ContentResolver query threw: ${e.message}", null)
            return
        }

        if (cursor == null) {
            result.error("QUERY_FAILED", "ContentResolver returned null cursor", null)
            return
        }

        try {
            cursor.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val durationCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val widthCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
                val heightCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
                val mimeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)
                val sizeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                val dateAddedCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                val dateModifiedCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)

                val videoList = mutableListOf<Map<String, Any?>>()
                while (c.moveToNext()) {
                    val id = c.getLong(idCol)
                    val contentUri = "content://media/external/video/media/$id"
                    videoList.add(
                        mapOf(
                            "mediaStoreId" to id.toString(),
                            "contentUri" to contentUri,
                            "displayName" to c.getString(nameCol),
                            "durationMs" to if (c.isNull(durationCol)) null else c.getLong(durationCol),
                            "widthPx" to if (c.isNull(widthCol)) null else c.getInt(widthCol),
                            "heightPx" to if (c.isNull(heightCol)) null else c.getInt(heightCol),
                            "mimeType" to c.getString(mimeCol),
                            "sizeBytes" to if (c.isNull(sizeCol)) null else c.getLong(sizeCol),
                            "dateAddedSeconds" to if (c.isNull(dateAddedCol)) null else c.getLong(dateAddedCol),
                            "dateModifiedSeconds" to if (c.isNull(dateModifiedCol)) null else c.getLong(dateModifiedCol),
                        ),
                    )
                }
                result.success(videoList)
            }
        } catch (e: Exception) {
            result.error("QUERY_FAILED", "Error reading cursor: ${e.message}", null)
        }
    }
}
