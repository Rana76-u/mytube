package com.example.mytube

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class DownloadServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        pendingContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        attach(channel!!)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        detach()
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        when (call.method) {
            "consumePendingCommands" -> result.success(consumePendingCommands(context))
            "start", "update" -> {
                if (context == null) {
                    result.error("SERVICE_UNAVAILABLE", "Download service is unavailable", null)
                    return
                }
                val snapshot = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val intent = serviceIntent(context, snapshot).apply {
                    action = if (call.method == "start") {
                        DownloadService.ACTION_START
                    } else {
                        DownloadService.ACTION_UPDATE
                    }
                }
                try {
                    if (call.method == "start") {
                        ContextCompat.startForegroundService(context, intent)
                    } else if (DownloadService.isServiceRunning) {
                        context.startService(intent)
                    } else {
                        intent.action = DownloadService.ACTION_START
                        ContextCompat.startForegroundService(context, intent)
                    }
                    result.success(null)
                } catch (error: SecurityException) {
                    result.error("SERVICE_START_FAILED", error.message, null)
                } catch (error: IllegalStateException) {
                    result.error("SERVICE_START_FAILED", error.message, null)
                }
            }
            "stop" -> {
                if (context != null) {
                    val args = call.arguments as? Map<*, *>
                    val showCompletion = args?.get("showCompletion") as? Boolean ?: false
                    if (DownloadService.isServiceRunning) {
                        context.startService(
                            Intent(context, DownloadService::class.java)
                                .setAction(DownloadService.ACTION_STOP)
                                .putExtra(
                                    DownloadService.EXTRA_SHOW_COMPLETION,
                                    showCompletion,
                                ),
                        )
                    } else if (showCompletion) {
                        DownloadService.notifyCompletion(context)
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun serviceIntent(context: Context, values: Map<*, *>): Intent =
        Intent(context, DownloadService::class.java)
            .putExtra(DownloadService.EXTRA_JOB_ID, values["jobId"] as? String)
            .putExtra(DownloadService.EXTRA_TITLE, values["title"] as? String)
            .putExtra(DownloadService.EXTRA_STATUS_TEXT, values["statusText"] as? String)
            .putExtra(
                DownloadService.EXTRA_ACTIVE_COUNT,
                (values["activeCount"] as? Number)?.toInt() ?: 1,
            )
            .apply {
                (values["progressPercent"] as? Number)?.toInt()?.let {
                    putExtra(DownloadService.EXTRA_PROGRESS, it)
                }
            }

    companion object {
        private const val CHANNEL = "com.example.mytube/download_service"
        private const val PREFERENCES = "download_service"
        private const val PENDING_COMMANDS = "pending_commands"

        @Volatile
        private var channel: MethodChannel? = null

        fun attach(target: MethodChannel) {
            channel = target
        }

        fun detach() {
            channel = null
        }

        fun handleActivityIntent(
            context: Context,
            intent: Intent?,
            dispatchImmediately: Boolean,
        ) {
            if (intent?.action == DownloadService.ACTION_OPEN_DOWNLOADS) {
                val command = mapOf("action" to "openDownloads", "jobId" to null)
                if (dispatchImmediately && channel != null) {
                    dispatchCommand("openDownloads", null, context)
                } else {
                    savePending(context, command)
                }
            }
        }

        fun dispatchCommand(action: String, jobId: String?, context: Context? = null) {
            val payload = mapOf("action" to action, "jobId" to jobId)
            val target = channel
            if (target != null) {
                target.invokeMethod("onCommand", payload)
            } else if (context != null) {
                savePending(context, payload)
            } else {
                pendingContext?.let { savePending(it, payload) }
            }
        }

        @Volatile
        private var pendingContext: Context? = null

        private fun consumePendingCommands(context: Context?): List<Map<String, Any?>> {
            if (context == null) return emptyList()
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val json = preferences.getString(PENDING_COMMANDS, "[]") ?: "[]"
            preferences.edit().remove(PENDING_COMMANDS).apply()
            val values = JSONArray(json)
            return (0 until values.length()).mapNotNull { index ->
                val entry = values.optJSONObject(index) ?: return@mapNotNull null
                mapOf(
                    "action" to entry.optString("action"),
                    "jobId" to entry.optString("jobId").takeIf { it.isNotEmpty() },
                )
            }
        }

        private fun savePending(context: Context, command: Map<String, Any?>) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val values = JSONArray(preferences.getString(PENDING_COMMANDS, "[]") ?: "[]")
            values.put(
                JSONObject()
                    .put("action", command["action"])
                    .put("jobId", command["jobId"]),
            )
            preferences.edit().putString(PENDING_COMMANDS, values.toString()).apply()
        }
    }

}
