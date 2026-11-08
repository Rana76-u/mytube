package com.example.mytube

import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ClipboardProbePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probeClipboard" -> {
                val clip = appContext?.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                val primary = clip?.primaryClip
                val text = if (primary != null && primary.itemCount > 0) {
                    primary.getItemAt(0).coerceToText(appContext).toString()
                } else null
                val payload = mapOf(
                    "text" to text,
                    "timestampMs" to System.currentTimeMillis(),
                )
                result.success(payload)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/clipboard_probe"
    }
}
