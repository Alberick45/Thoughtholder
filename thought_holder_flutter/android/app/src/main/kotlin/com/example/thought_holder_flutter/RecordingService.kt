package com.example.thought_holder_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.StatFs
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.Timer
import java.util.TimerTask

class RecordingService : Service() {

    companion object {
        const val CHANNEL_ID = "thoughtholder_recording_channel"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.thoughtholder.action.START_RECORDING"
        const val ACTION_STOP = "com.thoughtholder.action.STOP_RECORDING"
        const val ACTION_PAUSE = "com.thoughtholder.action.PAUSE_RECORDING"
        const val ACTION_RESUME = "com.thoughtholder.action.RESUME_RECORDING"

        const val EXTRA_OUTPUT_PATH = "extra_output_path"

        var isServiceRunning = false
            private set
        var currentOutputPath: String? = null
            private set
        var recordingDurationSeconds = 0
            private set
        var isPaused = false
            private set
        var pauseReason: String? = null
            private set

        var listener: RecordingListener? = null
    }

    interface RecordingListener {
        fun onTick(seconds: Int)
        fun onStatus(status: String, reason: String?)
        fun onFinished(filePath: String)
    }

    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var isRecording = false

    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private var bufferSize = 0

    private var timer: Timer? = null
    private var audioManager: AudioManager? = null
    private var audioFocusChangeListener: AudioManager.OnAudioFocusChangeListener? = null

    private var batteryReceiver: BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        setupAudioFocusListener()
        setupBatteryReceiver()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_STICKY

        when (action) {
            ACTION_START -> {
                val path = intent.getStringExtra(EXTRA_OUTPUT_PATH)
                if (path != null && !isServiceRunning) {
                    startRecording(path)
                }
            }
            ACTION_STOP -> {
                stopRecording()
            }
            ACTION_PAUSE -> {
                pauseRecording("manual")
            }
            ACTION_RESUME -> {
                resumeRecording()
            }
        }

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Active Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active ThoughtHolder recording status"
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String, isCallPaused: Boolean = false): Notification {
        val appIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("thoughtholder://capture")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val appPendingIntent = PendingIntent.getActivity(
            this, 0, appIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, RecordingService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (isCallPaused) {
            "Paused: your phone call"
        } else {
            "ThoughtHolder is recording"
        }

        val content = if (isCallPaused) {
            "Recording paused — will resume automatically"
        } else {
            text
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(appPendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        return builder.build()
    }

    private fun startRecording(outputPath: String) {
        currentOutputPath = outputPath
        isServiceRunning = true
        isRecording = true
        isPaused = false
        pauseReason = null
        recordingDurationSeconds = 0

        // Start Foreground Service with Microphone type on Android 14+ / 29+
        val initialNotification = buildNotification("00:00")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    initialNotification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, initialNotification)
            }
        } catch (e: Exception) {
            startForeground(NOTIFICATION_ID, initialNotification)
        }

        bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        if (bufferSize <= 0) bufferSize = 2048

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize * 2
            )
            audioRecord?.startRecording()
        } catch (e: Exception) {
            stopRecording()
            return
        }

        // Timer for seconds and notification update
        timer = Timer()
        timer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                if (isRecording && !isPaused) {
                    recordingDurationSeconds++
                    val mins = recordingDurationSeconds / 60
                    val secs = recordingDurationSeconds % 60
                    val timeStr = String.format("%02d:%02d", mins, secs)

                    // Update notification
                    val notification = buildNotification(timeStr)
                    val manager = getSystemService(NotificationManager::class.java)
                    manager.notify(NOTIFICATION_ID, notification)

                    listener?.onTick(recordingDurationSeconds)

                    // Safety storage check every 5 seconds
                    if (recordingDurationSeconds % 5 == 0) {
                        checkLowStorageAndBattery()
                    }
                }
            }
        }, 1000, 1000)

        // Background worker thread writing chunked WAV
        recordingThread = Thread {
            writeAudioDataToFile(outputPath)
        }
        recordingThread?.start()

        listener?.onStatus("recording", null)
    }

    private fun writeAudioDataToFile(outputPath: String) {
        val file = File(outputPath)
        file.parentFile?.mkdirs()
        if (file.exists()) file.delete()

        var totalAudioLen: Long = 0
        val data = ByteArray(bufferSize)

        try {
            val fos = FileOutputStream(file)
            // Write placeholder 44-byte WAV header
            writeWavHeader(fos, 0, 0, sampleRate, 1, 16)

            var lastHeaderUpdateTime = System.currentTimeMillis()

            while (isRecording) {
                if (isPaused) {
                    Thread.sleep(100)
                    continue
                }

                val read = audioRecord?.read(data, 0, bufferSize) ?: -1
                if (read > 0) {
                    fos.write(data, 0, read)
                    totalAudioLen += read

                    // UPDATE 4 (Requirement F): Update WAV header on disk in chunks every 5 seconds
                    val now = System.currentTimeMillis()
                    if (now - lastHeaderUpdateTime >= 5000) {
                        fos.flush()
                        updateWavHeaderSize(file, totalAudioLen)
                        lastHeaderUpdateTime = now
                    }
                }
            }

            fos.flush()
            fos.close()

            // Final WAV header update
            updateWavHeaderSize(file, totalAudioLen)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun writeWavHeader(
        out: FileOutputStream,
        totalAudioLen: Long,
        totalDataLen: Long,
        sampleRate: Int,
        channels: Int,
        byteRate: Int
    ) {
        val bitsPerSample = 16
        val actualByteRate = sampleRate * channels * (bitsPerSample / 8)
        val header = ByteArray(44)

        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()

        val chunkSize = totalDataLen + 36
        header[4] = (chunkSize and 0xff).toByte()
        header[5] = ((chunkSize shr 8) and 0xff).toByte()
        header[6] = ((chunkSize shr 16) and 0xff).toByte()
        header[7] = ((chunkSize shr 24) and 0xff).toByte()

        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()

        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()

        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0

        header[20] = 1 // PCM
        header[21] = 0

        header[22] = channels.toByte()
        header[23] = 0

        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()

        header[28] = (actualByteRate and 0xff).toByte()
        header[29] = ((actualByteRate shr 8) and 0xff).toByte()
        header[30] = ((actualByteRate shr 16) and 0xff).toByte()
        header[31] = ((actualByteRate shr 24) and 0xff).toByte()

        header[32] = (channels * bitsPerSample / 8).toByte()
        header[33] = 0

        header[34] = bitsPerSample.toByte()
        header[35] = 0

        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()

        header[40] = (totalAudioLen and 0xff).toByte()
        header[41] = ((totalAudioLen shr 8) and 0xff).toByte()
        header[42] = ((totalAudioLen shr 16) and 0xff).toByte()
        header[43] = ((totalAudioLen shr 24) and 0xff).toByte()

        out.write(header, 0, 44)
    }

    private fun updateWavHeaderSize(file: File, totalAudioLen: Long) {
        try {
            val raf = RandomAccessFile(file, "rw")
            val totalDataLen = totalAudioLen + 36

            raf.seek(4)
            raf.write((totalDataLen and 0xff).toInt())
            raf.write(((totalDataLen shr 8) and 0xff).toInt())
            raf.write(((totalDataLen shr 16) and 0xff).toInt())
            raf.write(((totalDataLen shr 24) and 0xff).toInt())

            raf.seek(40)
            raf.write((totalAudioLen and 0xff).toInt())
            raf.write(((totalAudioLen shr 8) and 0xff).toInt())
            raf.write(((totalAudioLen shr 16) and 0xff).toInt())
            raf.write(((totalAudioLen shr 24) and 0xff).toInt())

            raf.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun pauseRecording(reason: String) {
        if (!isPaused) {
            isPaused = true
            pauseReason = reason
            val notification = buildNotification("", isCallPaused = true)
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, notification)
            listener?.onStatus("paused", reason)
        }
    }

    fun resumeRecording() {
        if (isPaused) {
            isPaused = false
            pauseReason = null
            val mins = recordingDurationSeconds / 60
            val secs = recordingDurationSeconds % 60
            val timeStr = String.format("%02d:%02d", mins, secs)
            val notification = buildNotification(timeStr)
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, notification)
            listener?.onStatus("recording", null)
        }
    }

    private fun stopRecording() {
        if (!isServiceRunning) return

        isRecording = false
        isServiceRunning = false
        isPaused = false

        timer?.cancel()
        timer = null

        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null

        recordingThread?.join(1000)
        recordingThread = null

        val path = currentOutputPath ?: ""
        currentOutputPath = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        listener?.onFinished(path)
    }

    private fun setupAudioFocusListener() {
        audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                    pauseRecording("your phone call")
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    resumeRecording()
                }
            }
        }
        audioManager?.requestAudioFocus(
            audioFocusChangeListener,
            AudioManager.STREAM_VOICE_CALL,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
        )
    }

    private fun setupBatteryReceiver() {
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                    val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                    if (level >= 0 && scale > 0) {
                        val pct = (level * 100) / scale
                        if (pct < 3 && isServiceRunning) {
                            stopRecording()
                            listener?.onStatus("stopped", "Low battery (<3%)")
                        }
                    }
                }
            }
        }
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    }

    private fun checkLowStorageAndBattery() {
        val path = currentOutputPath ?: return
        try {
            val stat = StatFs(File(path).parentFile?.absolutePath ?: return)
            val availableBytes = stat.availableBlocksLong * stat.blockSizeLong
            if (availableBytes < 50 * 1024 * 1024) { // Under 50 MB
                stopRecording()
                listener?.onStatus("stopped", "Low storage (<50MB)")
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        if (batteryReceiver != null) {
            try { unregisterReceiver(batteryReceiver) } catch (_: Exception) {}
        }
        if (audioFocusChangeListener != null) {
            audioManager?.abandonAudioFocus(audioFocusChangeListener)
        }
        stopRecording()
        super.onDestroy()
    }
}
