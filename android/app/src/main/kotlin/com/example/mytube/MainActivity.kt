package com.example.mytube

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaStorePlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        SaffBridgePlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        ThumbnailPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        AudioFocusPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        MediaSessionPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        PipPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        SharePlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        CaptionsPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
    }

    // PiP enter/leave is reported by the framework on the activity, not on a
    // plugin, so relay it to PipPlugin which forwards `onPipModeChanged` to the
    // Dart coordinator (P13-04). configChanges already covers the PiP resize so
    // the activity is not recreated here.
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        PipPlugin.notifyPipMode(isInPictureInPictureMode)
    }
}
