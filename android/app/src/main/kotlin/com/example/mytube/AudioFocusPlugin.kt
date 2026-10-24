package com.example.mytube

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android audio-focus bridge (P13-01, PLAY-011; P13-02, PLAY-010).
 *
 * Channels:
 *  - MethodChannel "com.example.mytube/audio_focus"
 *      requestFocus  : request AUDIOFOCUS_GAIN tagged as media playback
 *      abandonFocus  : abandon previously requested focus (idempotent)
 *      release       : abandon + drop the Dart event sink
 *  - EventChannel "com.example.mytube/audio_focus/events"
 *      pushes focus transitions to Dart as stable string tags
 *      (gained / lostTransientCanDuck / lostTransient / lostEphemeral / lost)
 *      which the Dart AudioFocusBridgeImpl maps onto AudioFocusChange.
 *
 * Holding AUDIOFOCUS_GAIN is what lets audio keep playing while the app is
 * backgrounded (P13-02); the transition callbacks let the app-owned
 * AudioFocusCoordinator pause or duck on an interruption and resume when it
 * ends. Nothing here decides playback policy — it only reports focus state.
 */
class AudioFocusPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var audioManager: AudioManager? = null

    private var eventSink: EventChannel.EventSink? = null
    private var focusRequest: AudioFocusRequest? = null
    private var holdingFocus = false

    // Legacy (< API 26) focus listener; the same object must be passed to
    // request and abandon so the system can match them.
    private val legacyListener = AudioManager.OnAudioFocusChangeListener { change ->
        dispatch(change)
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        dispatch(change)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context: Context = binding.applicationContext
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        abandon()
        audioManager = null
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestFocus" -> {
                request()
                result.success(null)
            }
            "abandonFocus" -> {
                abandon()
                result.success(null)
            }
            "release" -> {
                abandon()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // -- EventChannel.StreamHandler -------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // -- Focus handling --------------------------------------------------------

    private fun request() {
        val manager = audioManager ?: return
        if (holdingFocus) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setWillPauseWhenDucked(false)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = request
            val status = manager.requestAudioFocus(request)
            holdingFocus = status == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val status = manager.requestAudioFocus(
                legacyListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
            holdingFocus = status == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandon() {
        val manager = audioManager ?: return
        if (!holdingFocus && focusRequest == null) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { manager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(legacyListener)
        }
        holdingFocus = false
    }

    /// Maps an [AudioManager] focus-change constant to the Dart vocabulary and
    /// forwards it. The main thread is required for EventSink delivery.
    private fun dispatch(change: Int) {
        val tag = when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> "gained"
            AudioManager.AUDIOFOCUS_LOSS -> "lost"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "lostTransient"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "lostTransientCanDuck"
            // AUDIOFOCUS_LOSS_EPHEMERAL is only defined on API 34+; its raw
            // value is stable, so compare the integer directly.
            EPHEMERAL_LOSS -> "lostEphemeral"
            else -> null
        }
        val sink = eventSink ?: return
        if (tag != null) sink.success(tag)
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/audio_focus"
        private const val EVENTS_CHANNEL = "com.example.mytube/audio_focus/events"
        private const val EPHEMERAL_LOSS = -3 // AudioManager.AUDIOFOCUS_LOSS_EPHEMERAL
    }
}
