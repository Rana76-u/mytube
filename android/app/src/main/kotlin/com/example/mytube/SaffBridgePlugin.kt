package com.example.mytube

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
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

    /** Coroutine scope for background traversal; cancelled on engine detach. */
    private var ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Maximum number of video files returned per listVideosInFolder call. */
    private val MAX_VIDEO_FILES = 5_000

    /** Maximum directory depth for the recursive SAF tree walk. */
    private val MAX_DEPTH = 20

    // -------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        channel = MethodChannel(binding.binaryMessenger, "com.example.mytube/saf")
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
        val context = flutterPluginBinding.applicationContext

        // Run the recursive traversal off the main/channel thread to avoid
        // blocking for seconds on large SD cards or deeply nested trees.
        ioScope.launch {
            try {
                val treeUri = Uri.parse(uriString)
                val videoList = mutableListOf<Map<String, Any?>>()
                try {
                    collectVideosViaCursor(context.contentResolver, treeUri, videoList)
                } catch (e: SecurityException) {
                    throw e
                } catch (e: Exception) {
                    // Some providers do not implement child-document queries.
                    // Fall back to the DocumentFile walk, which is universal
                    // but issues several IPC calls per file.
                    videoList.clear()
                    collectVideoFiles(
                        DocumentFile.fromTreeUri(context, treeUri),
                        videoList,
                        depth = 0,
                    )
                }
                withContext(Dispatchers.Main) {
                    result.success(videoList)
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION_DENIED", "Folder access revoked", null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("LIST_FAILED", e.message, null)
                }
            }
        }
    }

    /**
     * Collects video documents with one `ContentResolver.query` per directory.
     *
     * `DocumentFile` resolves each property (`name`, `type`, `length`, …)
     * through its own provider query, so walking a large folder with it costs
     * several IPC round trips per file. Querying the child documents directly
     * with a projection returns everything for a directory in a single call.
     */
    private fun collectVideosViaCursor(
        resolver: ContentResolver,
        treeUri: Uri,
        results: MutableList<Map<String, Any?>>,
    ) {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        collectChildVideos(resolver, treeUri, rootId, results, depth = 0)
    }

    private fun collectChildVideos(
        resolver: ContentResolver,
        treeUri: Uri,
        parentDocumentId: String,
        results: MutableList<Map<String, Any?>>,
        depth: Int,
    ) {
        if (results.size >= MAX_VIDEO_FILES || depth >= MAX_DEPTH) return
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val directories = mutableListOf<String>()
        resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext() && results.size < MAX_VIDEO_FILES) {
                val documentId = cursor.getString(0) ?: continue
                val displayName = cursor.getString(1) ?: ""
                val mimeType = cursor.getString(2)
                val sizeBytes = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                val lastModifiedMs = if (cursor.isNull(4)) 0L else cursor.getLong(4)

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    directories.add(documentId)
                } else if (isVideoDocument(mimeType, displayName)) {
                    results.add(
                        mapOf(
                            "uri" to
                                DocumentsContract
                                    .buildDocumentUriUsingTree(treeUri, documentId)
                                    .toString(),
                            "displayName" to displayName,
                            "mimeType" to mimeType,
                            "sizeBytes" to sizeBytes.takeIf { it > 0L },
                            "lastModifiedMs" to lastModifiedMs.takeIf { it > 0L },
                        ),
                    )
                }
            }
        }
        // Recurse after the cursor is closed so no provider cursor stays open.
        for (childId in directories) {
            if (results.size >= MAX_VIDEO_FILES) return
            collectChildVideos(resolver, treeUri, childId, results, depth + 1)
        }
    }

    private fun isVideoDocument(mimeType: String?, displayName: String): Boolean {
        if (mimeType != null) return mimeType.startsWith("video/")
        val ext = displayName.substringAfterLast('.', "").lowercase()
        return ext in listOf(
            "mp4", "mkv", "avi", "mov", "webm", "3gp", "ts", "m4v", "wmv", "flv",
        )
    }

    private fun collectVideoFiles(
        docFile: DocumentFile?,
        results: MutableList<Map<String, Any?>>,
        depth: Int,
    ) {
        if (docFile == null || !docFile.exists()) return
        if (results.size >= MAX_VIDEO_FILES) return
        if (docFile.isDirectory) {
            if (depth >= MAX_DEPTH) return
            docFile.listFiles().forEach { child ->
                if (results.size >= MAX_VIDEO_FILES) return
                collectVideoFiles(child, results, depth + 1)
            }
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
