package com.example.mytube

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class SaffBridgePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingFolderPickerResult: MethodChannel.Result? = null
    private val FOLDER_PICKER_REQUEST_CODE = 1002

    // -------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        channel = MethodChannel(binding.binaryMessenger, "com.example.mytube/saf")
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
            "openFolderPicker" -> openFolderPicker(result)
            "getPersistedFolderUris" -> getPersistedFolderUris(result)
            "releasePersistedUri" -> releasePersistedUri(call, result)
            "listVideosInFolder" -> listVideosInFolder(call, result)
            "checkFolderAccess" -> checkFolderAccess(call, result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Folder picker
    // -------------------------------------------------------------------------

    private fun openFolderPicker(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
            ?: run {
                result.error("NO_ACTIVITY", "No activity attached", null)
                return
            }
        pendingFolderPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        activity.startActivityForResult(intent, FOLDER_PICKER_REQUEST_CODE)
    }

    // -------------------------------------------------------------------------
    // ActivityResultListener
    // -------------------------------------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != FOLDER_PICKER_REQUEST_CODE) return false
        val pending = pendingFolderPickerResult ?: return false
        pendingFolderPickerResult = null

        if (resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            try {
                flutterPluginBinding.applicationContext.contentResolver
                    .takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (e: SecurityException) {
                // Permission could not be persisted; return null so caller can retry.
                pending.success(null)
                return true
            }
            pending.success(uri.toString())
        } else {
            pending.success(null)
        }
        return true
    }

    // -------------------------------------------------------------------------
    // Persisted URIs
    // -------------------------------------------------------------------------

    private fun getPersistedFolderUris(result: MethodChannel.Result) {
        val context = flutterPluginBinding.applicationContext
        val uris = context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { it.uri.toString() }
        result.success(uris)
    }

    private fun releasePersistedUri(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
            ?: run {
                result.error("INVALID_ARGUMENT", "Missing 'uri' argument", null)
                return
            }
        try {
            flutterPluginBinding.applicationContext.contentResolver
                .releasePersistableUriPermission(
                    Uri.parse(uriString),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
        } catch (e: SecurityException) {
            // Already released or never granted — treat as success (idempotent).
        }
        result.success(null)
    }

    // -------------------------------------------------------------------------
    // Video listing
    // -------------------------------------------------------------------------

    private fun listVideosInFolder(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
            ?: run {
                result.error("INVALID_ARGUMENT", "Missing 'uri' argument", null)
                return
            }
        try {
            val context = flutterPluginBinding.applicationContext
            val docFile = DocumentFile.fromTreeUri(context, Uri.parse(uriString))
            val videoList = mutableListOf<Map<String, Any?>>()
            collectVideoFiles(docFile, videoList)
            result.success(videoList)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Folder access revoked", null)
        } catch (e: Exception) {
            result.error("LIST_FAILED", e.message, null)
        }
    }

    private fun collectVideoFiles(
        docFile: DocumentFile?,
        results: MutableList<Map<String, Any?>>,
    ) {
        if (docFile == null || !docFile.exists()) return
        if (docFile.isDirectory) {
            docFile.listFiles().forEach { collectVideoFiles(it, results) }
        } else if (isVideoFile(docFile)) {
            results.add(
                mapOf(
                    "uri" to docFile.uri.toString(),
                    "displayName" to (docFile.name ?: ""),
                    "mimeType" to docFile.type,
                    "sizeBytes" to docFile.length().takeIf { it > 0L },
                    "lastModifiedMs" to docFile.lastModified().takeIf { it > 0L },
                ),
            )
        }
    }

    private fun isVideoFile(file: DocumentFile): Boolean {
        val mime = file.type
        if (mime != null) return mime.startsWith("video/")
        val name = file.name ?: return false
        val ext = name.substringAfterLast('.', "").lowercase()
        return ext in listOf("mp4", "mkv", "avi", "mov", "webm", "3gp", "ts", "m4v", "wmv", "flv")
    }

    // -------------------------------------------------------------------------
    // Access check
    // -------------------------------------------------------------------------

    private fun checkFolderAccess(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
            ?: run {
                result.error("INVALID_ARGUMENT", "Missing 'uri' argument", null)
                return
            }
        try {
            val context = flutterPluginBinding.applicationContext
            val accessible = DocumentFile.fromTreeUri(context, Uri.parse(uriString))?.exists() ?: false
            result.success(accessible)
        } catch (e: SecurityException) {
            result.success(false)
        }
    }
}
