package com.example.mytube

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ShareIntakePlugin.handleIncomingIntent(intent)
        DownloadServicePlugin.handleActivityIntent(
            applicationContext,
            intent,
            dispatchImmediately = false,
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ShareIntakePlugin.handleIncomingIntent(intent)
        DownloadServicePlugin.handleActivityIntent(
            applicationContext,
            intent,
            dispatchImmediately = true,
        )
    }

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
        ShareIntakePlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        ClipboardProbePlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        CaptionsPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        // Link-downloader extraction bridge (DL2.3). Wraps the youtubedl-android
        // engine behind com.example.mytube/extractor.
        ExtractorPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        // Link-downloader destination publisher (DL3.2/DL3.3). MediaStore and
        // SAF-tree copies behind com.example.mytube/publish; app storage stays
        // in Dart (dart:io rename).
        PublishPlugin().also { plugin ->
            flutterEngine.plugins.add(plugin)
        }
        DownloadServicePlugin().also { plugin ->
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
