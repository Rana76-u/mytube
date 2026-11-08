package com.example.mytube

import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ShareIntakePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumeShareText" -> {
                result.success(pendingShareText)
                pendingShareText = null
            }
            "clearPendingShareText" -> {
                pendingShareText = null
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/share_intake"

        @Volatile
        private var pendingShareText: String? = null

        fun handleIncomingIntent(intent: Intent?) {
            if (intent == null) return
            val action = intent.action ?: return
            if (action != Intent.ACTION_SEND) return
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (text != null && text.isNotBlank()) {
                pendingShareText = text
            }
            intent.removeExtra(Intent.EXTRA_TEXT)
            intent.action = Intent.ACTION_MAIN
        }
    }
}
