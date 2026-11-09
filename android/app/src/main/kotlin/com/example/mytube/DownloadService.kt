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

class DownloadService : Service() {
    private var foregrounded = false
    private var jobId: String? = null
    private var title = "Download"
    private var statusText = "Downloading"
    private var activeCount = 1
    private var progressPercent: Int? = null

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_UPDATE -> {
                readSnapshot(intent)
                showForeground()
            }
            ACTION_STOP -> {
                val showCompletion = intent.getBooleanExtra(EXTRA_SHOW_COMPLETION, false)
                stopForegroundAndOptionallyNotify(showCompletion)
                stopSelfResult(startId)
            }
            ACTION_PAUSE, ACTION_CANCEL -> {
                DownloadServicePlugin.dispatchCommand(
                    if (intent.action == ACTION_PAUSE) "pause" else "cancel",
                    intent.getStringExtra(EXTRA_JOB_ID),
                    applicationContext,
                )
                if (!foregrounded) stopSelfResult(startId)
            }
            else -> stopSelfResult(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTimeout(startId: Int, fgsType: Int) {
        DownloadServicePlugin.dispatchCommand("timeout", null, applicationContext)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        foregrounded = false
        isServiceRunning = false
        stopSelf(startId)
    }

    override fun onDestroy() {
        isServiceRunning = false
        foregrounded = false
        super.onDestroy()
    }

    private fun readSnapshot(intent: Intent) {
        jobId = intent.getStringExtra(EXTRA_JOB_ID)
        title = intent.getStringExtra(EXTRA_TITLE)?.take(MAX_TITLE_LENGTH) ?: "Download"
        statusText = intent.getStringExtra(EXTRA_STATUS_TEXT) ?: "Downloading"
        activeCount = intent.getIntExtra(EXTRA_ACTIVE_COUNT, 1).coerceAtLeast(1)
        progressPercent = if (intent.hasExtra(EXTRA_PROGRESS)) {
            intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
        } else {
            null
        }
    }

    private fun showForeground() {
        val notification = buildProgressNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregrounded = true
    }

    private fun stopForegroundAndOptionallyNotify(showCompletion: Boolean) {
        if (foregrounded) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            foregrounded = false
        }
        if (showCompletion) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(COMPLETION_NOTIFICATION_ID, buildCompletionNotification())
        }
    }

    private fun buildProgressNotification(): Notification {
        val openDownloads = openDownloadsPendingIntent()
        val id = jobId
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (activeCount > 1) "$activeCount downloads" else title)
            .setContentText(statusText)
            .setContentIntent(openDownloads)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setProgress(100, progressPercent ?: 0, progressPercent == null)
        if (id != null) {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "Pause",
                serviceActionPendingIntent(ACTION_PAUSE, id, ACTION_PAUSE_REQUEST),
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Cancel",
                serviceActionPendingIntent(ACTION_CANCEL, id, ACTION_CANCEL_REQUEST),
            )
        }
        return builder.build()
    }

    private fun buildCompletionNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Downloads finished")
            .setContentText("Tap to review Downloads")
            .setContentIntent(openDownloadsPendingIntent())
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(false)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()

    private fun openDownloadsPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
            .setAction(ACTION_OPEN_DOWNLOADS)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            OPEN_DOWNLOADS_REQUEST,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun serviceActionPendingIntent(action: String, id: String, requestCode: Int) =
        PendingIntent.getService(
            this,
            requestCode + id.hashCode(),
            Intent(this, DownloadService::class.java)
                .setAction(action)
                .putExtra(EXTRA_JOB_ID, id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun ensureChannel() {
        ensureChannel(this)
    }

    companion object {
        private const val CHANNEL_ID = "mytube_downloads"
        private const val CHANNEL_NAME = "Downloads"
        private const val NOTIFICATION_ID = 0x4D55
        private const val COMPLETION_NOTIFICATION_ID = 0x4D56
        private const val OPEN_DOWNLOADS_REQUEST = 0x4D57
        private const val ACTION_PAUSE_REQUEST = 0x4D58
        private const val ACTION_CANCEL_REQUEST = 0x4D59
        private const val MAX_TITLE_LENGTH = 100

        const val ACTION_START = "com.example.mytube.download.START"
        const val ACTION_UPDATE = "com.example.mytube.download.UPDATE"
        const val ACTION_STOP = "com.example.mytube.download.STOP"
        const val ACTION_PAUSE = "com.example.mytube.download.PAUSE"
        const val ACTION_CANCEL = "com.example.mytube.download.CANCEL"
        const val ACTION_OPEN_DOWNLOADS = "com.example.mytube.download.OPEN"

        const val EXTRA_JOB_ID = "jobId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STATUS_TEXT = "statusText"
        const val EXTRA_ACTIVE_COUNT = "activeCount"
        const val EXTRA_PROGRESS = "progressPercent"
        const val EXTRA_SHOW_COMPLETION = "showCompletion"

        @Volatile
        var isServiceRunning = false
            private set

        fun notifyCompletion(context: Context) {
            ensureChannel(context)
            val intent = Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN_DOWNLOADS)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val pendingIntent = PendingIntent.getActivity(
                context,
                OPEN_DOWNLOADS_REQUEST,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("Downloads finished")
                .setContentText("Tap to review Downloads")
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setOngoing(false)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .build()
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(COMPLETION_NOTIFICATION_ID, notification)
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Download progress and completion"
                    setShowBadge(false)
                },
            )
        }
    }
}
