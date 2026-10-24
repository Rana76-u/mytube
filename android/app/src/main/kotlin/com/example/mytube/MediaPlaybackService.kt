package com.example.mytube

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

/**
 * `mediaPlayback` foreground service backing the Android media session and
 * notification (P13-03, PLAY-010; the reliable-background-audio prerequisite
 * documented for P13-02, PLAT-004).
 *
 * It owns the [MediaSessionCompat] and the ongoing [MediaStyle] notification.
 * The Dart [MediaSessionCoordinator] drives it purely through [MediaSessionPlugin]
 * method calls that arrive as [Intent] actions here: `render` mirrors the current
 * playback state into the session + notification, `stop` hides the notification,
 * and `release` tears the service down.
 *
 * Transport controls are the reverse path: the notification / lock screen / headset
 * fire into the session [MediaSessionCompat.Callback], which forwards a plain
 * `onTransport` payload back to Dart via [MediaSessionPlugin.dispatchTransport].
 * No playback decision lives here — the session is a mirror and a relay.
 */
class MediaPlaybackService : Service() {

    private var session: MediaSessionCompat? = null

    // Last rendered values, kept so transport toggles (play <-> pause) can rebuild
    // the notification without waiting for the next `render` from Dart.
    private var title: String = NowPlayingFallback
    private var isPlaying = false
    private var positionMs = 0L
    private var durationMs = 0L
    private var canSeek = false
    private var speed = 1f

    /// Whether [startForeground] has been called since the last teardown. Any
    /// start delivered through `startForegroundService` — including stop and
    /// release — must reach `startForeground` within the OS window or the
    /// framework throws `ForegroundServiceDidNotStartInTime`.
    private var foregrounded = false

    private val callback = object : MediaSessionCompat.Callback() {
        override fun onPlay() = MediaSessionPlugin.dispatchTransport(TRANSPORT_PLAY, null)

        override fun onPause() = MediaSessionPlugin.dispatchTransport(TRANSPORT_PAUSE, null)

        override fun onSeekTo(pos: Long) =
            MediaSessionPlugin.dispatchTransport(TRANSPORT_SEEK_TO, pos)

        override fun onStop() {
            MediaSessionPlugin.dispatchTransport(TRANSPORT_STOP, null)
            hideNotification()
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        val token = PendingIntent.getBroadcast(
            this,
            0,
            Intent(Intent.ACTION_MEDIA_BUTTON),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSessionCompat(this, SESSION_TAG, null, token).apply {
            setCallback(callback)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RENDER -> {
                readExtras(intent)
                showForeground()
            }
            ACTION_STOP -> {
                // Promote first (start may have come via startForegroundService),
                // then hide + stop.
                if (!foregrounded) showForeground()
                hideNotification()
            }
            ACTION_RELEASE -> {
                if (!foregrounded) showForeground()
                releaseAndStop()
            }
            else -> {
                // A bare start (e.g. after process restart) keeps the last snapshot.
                showForeground()
            }
        }
        // The app owns lifecycle; a kill never restarts playback on its own.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        session?.release()
        session = null
        super.onDestroy()
    }

    // ---------------------------------------------------------------------------
    // Render
    // ---------------------------------------------------------------------------

    private fun readExtras(intent: Intent) {
        title = intent.getStringExtra(EXTRA_TITLE) ?: NowPlayingFallback
        isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, false)
        positionMs = intent.getLongExtra(EXTRA_POSITION_MS, 0L)
        durationMs = intent.getLongExtra(EXTRA_DURATION_MS, 0L)
        canSeek = intent.getBooleanExtra(EXTRA_CAN_SEEK, false)
        speed = intent.getFloatExtra(EXTRA_SPEED, 1f)
    }

    private fun showForeground() {
        val active = session ?: return
        active.setMetadata(buildMetadata())
        active.setPlaybackState(buildPlaybackState())
        if (!active.isActive) active.setActive(true)

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregrounded = true
    }

    private fun hideNotification() {
        session?.setActive(false)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        foregrounded = false
        stopSelf()
    }

    private fun releaseAndStop() {
        session?.setActive(false)
        session?.release()
        session = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        foregrounded = false
        stopSelf()
    }

    private fun buildMetadata(): MediaMetadataCompat = MediaMetadataCompat.Builder()
        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs.coerceAtLeast(0L))
        .build()

    private fun buildPlaybackState(): PlaybackStateCompat {
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_STOP
        val withSeek = if (canSeek) {
            actions or PlaybackStateCompat.ACTION_SEEK_TO
        } else {
            actions
        }
        val state = when {
            isPlaying -> PlaybackStateCompat.STATE_PLAYING
            else -> PlaybackStateCompat.STATE_PAUSED
        }
        return PlaybackStateCompat.Builder()
            .setActions(withSeek)
            .setState(state, positionMs, speed)
            .build()
    }

    private fun buildNotification(): Notification {
        val active = session ?: return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setOngoing(true)
            .setSilent(true)
            .build()
        val playPause = if (isPlaying) {
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                this, PlaybackStateCompat.ACTION_PAUSE
            )
        } else {
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                this, PlaybackStateCompat.ACTION_PLAY
            )
        }
        val playPauseIcon = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val stop = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this, PlaybackStateCompat.ACTION_STOP
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(title)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(
                MediaStyle()
                    .setMediaSession(active.sessionToken)
                    .setShowActionsInCompactView(0, 1)
            )
        if (playPause != null) {
            builder.addAction(playPauseIcon, if (isPlaying) "Pause" else "Play", playPause)
        }
        if (stop != null) {
            builder.addAction(android.R.drawable.ic_delete, "Stop", stop)
        }
        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Now-playing controls"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val SESSION_TAG = "mytube_media_session"
        private const val CHANNEL_ID = "mytube_media_playback"
        private const val CHANNEL_NAME = "Playback"
        private const val NOTIFICATION_ID = 0x4D54 // "MT"
        private const val NowPlayingFallback = "Video"

        const val ACTION_RENDER = "com.example.mytube.media.RENDER"
        const val ACTION_STOP = "com.example.mytube.media.STOP"
        const val ACTION_RELEASE = "com.example.mytube.media.RELEASE"

        const val EXTRA_TITLE = "title"
        const val EXTRA_IS_PLAYING = "isPlaying"
        const val EXTRA_POSITION_MS = "positionMs"
        const val EXTRA_DURATION_MS = "durationMs"
        const val EXTRA_CAN_SEEK = "canSeek"
        const val EXTRA_SPEED = "speed"

        // Transport strings forwarded to Dart; must match decodeMediaTransport().
        const val TRANSPORT_PLAY = "play"
        const val TRANSPORT_PAUSE = "pause"
        const val TRANSPORT_SEEK_TO = "seekTo"
        const val TRANSPORT_STOP = "stop"
    }
}
