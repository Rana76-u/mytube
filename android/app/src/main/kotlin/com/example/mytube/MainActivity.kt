package com.example.mytube

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
    }
}
