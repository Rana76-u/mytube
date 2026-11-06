package com.example.mytube

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/**
 * Native half of the DL3 destination publishers (`com.example.mytube/publish`).
 *
 * The Dart [PublishBridge] dispatcher owns app-storage (a `dart:io` rename);
 * everything that needs a framework API the Dart isolate cannot reach — the
 * MediaStore "MyTube" folders and a SAF-picked tree — is copied here. The
 * staged file is produced by the download runner under the app's staging tree;
 * this plugin reads it and writes a copy to the destination, then reports the
 * resulting content URI back so Dart can discard staging.
 *
 * Contract kept deliberately narrow (ARCHITECTURE §15.7, AGENTS data-integrity):
 *  * It NEVER deletes the staged file — the Dart dispatcher does that only
 *    after a success, and only inside the staging tree.
 *  * MediaStore and `DocumentFile.create` both auto-uniquify a colliding name,
 *    so an existing destination is never overwritten.
 *  * Every failure comes back as a typed PlatformException code the Dart
 *    `_errorFor` maps (PERMISSION_DENIED / DESTINATION_UNAVAILABLE / LOW_STORAGE),
 *    never a crash. A denial/absence of the API 24–28 write permission is
 *    reported as PERMISSION_DENIED so the caller can fall back to app storage.
 *
 * The copy runs on an IO dispatcher and the reply is posted back to the main
 * thread, matching the sibling plugins (SaffBridgePlugin) so a large file never
 * blocks the platform channel.
 */
class PublishPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: android.content.Context
    private var ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        ioScope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "publishToDeviceFolder" -> publishToDeviceFolder(call, result)
            "publishToPickedFolder" -> publishToPickedFolder(call, result)
            "availableBytes" -> availableBytes(call, result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // MediaStore device folders (Movies/MyTube, Music/MyTube)
    // -------------------------------------------------------------------------

    private fun publishToDeviceFolder(call: MethodCall, result: MethodChannel.Result) {
        val stagedPath = call.argument<String>("stagedPath")
        val displayName = call.argument<String>("displayName")
        if (stagedPath.isNullOrEmpty() || displayName.isNullOrEmpty()) {
            result.error(CODE_UNAVAILABLE, "Missing stagedPath/displayName", null)
            return
        }
        val kind = call.argument<String>("kind") ?: KIND_MOVIES
        val mimeType = call.argument<String>("mimeType")
        val staged = File(stagedPath)
        if (!staged.exists()) {
            result.error(CODE_UNAVAILABLE, "staged file missing", null)
            return
        }

        // Below API 29 MediaStore writes require the legacy storage permission.
        // When it is absent we report PERMISSION_DENIED so Dart falls back to
        // app storage rather than blocking on a permission prompt here.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error(CODE_PERMISSION, "WRITE_EXTERNAL_STORAGE not granted", null)
            return
        }

        // Free-space gate before the copy: the primary volume is where MediaStore
        // places the row, so StatFs there is the honest headroom check.
        val size = staged.length()
        if (!hasRoomFor(size, Environment.getExternalStorageDirectory().path)) {
            result.error(CODE_LOW_STORAGE, "insufficient free space", null)
            return
        }

        val resolver = context.contentResolver
        val music = kind == KIND_MUSIC
        ioScope.launch {
            var published: Uri? = null
            try {
                val collection = if (music) {
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                } else {
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                }
                val relativePath = if (music) "Music/$FOLDER/" else "Movies/$FOLDER/"
                val pending = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                    if (!mimeType.isNullOrEmpty()) put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    if (pending) {
                        put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    } else {
                        // Pre-Q has no RELATIVE_PATH; seed the DATA column with the
                        // absolute path so the row lands in Movies|Music/MyTube.
                        val absolute = File(
                            Environment.getExternalStoragePublicDirectory(
                                if (music) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_MOVIES,
                            ),
                            FOLDER,
                        )
                        if (!absolute.exists()) absolute.mkdirs()
                        put(MediaStore.MediaColumns.DATA, File(absolute, displayName).absolutePath)
                    }
                }

                published = resolver.insert(collection, values)
                    ?: throw IOException("MediaStore insert returned null")
                val written = copyFileToUri(resolver, stagedPath, published)

                if (pending) {
                    val finalize = ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    resolver.update(published, finalize, null, null)
                }

                val reply = mapOf(
                    "uri" to published.toString(),
                    "displayName" to displayName,
                    "sizeBytes" to written,
                )
                withContext(Dispatchers.Main) { result.success(reply) }
            } catch (e: SecurityException) {
                cleanupFailedInsert(resolver, published, pending = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                withContext(Dispatchers.Main) {
                    result.error(CODE_PERMISSION, e.message ?: "storage permission revoked", null)
                }
            } catch (e: Exception) {
                cleanupFailedInsert(resolver, published, pending = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                withContext(Dispatchers.Main) {
                    result.error(CODE_UNAVAILABLE, e.message ?: "MediaStore publish failed", null)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // SAF picked tree folder
    // -------------------------------------------------------------------------

    private fun publishToPickedFolder(call: MethodCall, result: MethodChannel.Result) {
        val stagedPath = call.argument<String>("stagedPath")
        val treeUriString = call.argument<String>("treeUri")
        val displayName = call.argument<String>("displayName")
        if (stagedPath.isNullOrEmpty() || treeUriString.isNullOrEmpty() || displayName.isNullOrEmpty()) {
            result.error(CODE_UNAVAILABLE, "Missing stagedPath/treeUri/displayName", null)
            return
        }
        val mimeType = call.argument<String>("mimeType")
        val staged = File(stagedPath)
        if (!staged.exists()) {
            result.error(CODE_UNAVAILABLE, "staged file missing", null)
            return
        }

        val resolver = context.contentResolver
        ioScope.launch {
            try {
                val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUriString))
                if (tree == null || !tree.exists() || !tree.canWrite()) {
                    // A revoked or read-only grant: keep staging, tell the user.
                    withContext(Dispatchers.Main) {
                        result.error(CODE_UNAVAILABLE, "SAF grant missing or read-only", null)
                    }
                    return@launch
                }
                // createFile never overwrites: the provider uniquifies the name.
                val created = tree.createFile(mimeType ?: "application/octet-stream", displayName)
                if (created == null) {
                    withContext(Dispatchers.Main) {
                        result.error(CODE_UNAVAILABLE, "could not create document", null)
                    }
                    return@launch
                }
                val written = copyFileToUri(resolver, stagedPath, created.uri)
                val reply = mapOf(
                    "uri" to created.uri.toString(),
                    "displayName" to (created.name ?: displayName),
                    "sizeBytes" to written,
                )
                withContext(Dispatchers.Main) { result.success(reply) }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    result.error(CODE_UNAVAILABLE, e.message ?: "folder access revoked", null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error(CODE_UNAVAILABLE, e.message ?: "SAF publish failed", null)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Free-space probe
    // -------------------------------------------------------------------------

    private fun availableBytes(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.success(null)
            return
        }
        try {
            // Walk up to the nearest existing directory so a not-yet-created
            // destination folder still reports its volume's headroom.
            var dir = File(path)
            while (!dir.exists() && dir.parent != null) {
                dir = dir.parentFile!!
            }
            val stat = StatFs(dir.absolutePath)
            result.success(stat.availableBytes)
        } catch (e: Exception) {
            result.success(null)
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /** Streams [stagedPath] into [dest]; returns the exact byte count written. */
    private fun copyFileToUri(resolver: ContentResolver, stagedPath: String, dest: Uri): Long {
        val src = File(stagedPath)
        var total = 0L
        src.inputStream().use { input ->
            val output = resolver.openOutputStream(dest)
                ?: throw IOException("could not open destination stream")
            output.use { sink ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buffer)
                    if (n <= 0) break
                    sink.write(buffer, 0, n)
                    total += n
                }
                sink.flush()
            }
        }
        return total
    }

    private fun hasRoomFor(bytes: Long, volumePath: String): Boolean {
        if (bytes <= 0L) return true
        return try {
            StatFs(volumePath).availableBytes > bytes
        } catch (e: Exception) {
            // Unknown headroom is treated as "proceed"; the write itself will
            // surface a real failure rather than a false refusal.
            true
        }
    }

    /** Removes a half-written MediaStore row so a failed publish leaves no orphan. */
    private fun cleanupFailedInsert(resolver: ContentResolver, uri: Uri?, pending: Boolean) {
        if (uri == null || !pending) return
        try {
            resolver.delete(uri, null, null)
        } catch (_: Exception) {
            // Best-effort; a lingering IS_PENDING row is invisible to the gallery.
        }
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/publish"
        private const val KIND_MOVIES = "movies"
        private const val KIND_MUSIC = "music"
        private const val FOLDER = "MyTube"
        private const val CODE_PERMISSION = "PERMISSION_DENIED"
        private const val CODE_UNAVAILABLE = "DESTINATION_UNAVAILABLE"
        private const val CODE_LOW_STORAGE = "LOW_STORAGE"
    }
}
