package com.messagenius.msg_video_trimmer

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Media3 Transformer trim logic, ported from the original
 * `flutter_native_video_trimmer` with progress reporting added.
 */
@UnstableApi
class VideoManager {
    private var currentVideoPath: String? = null
    private var transformer: Transformer? = null

    fun loadVideo(path: String) {
        if (!File(path).exists()) {
            throw VideoException("Video file not found")
        }
        // Validate the file is readable as media; throws if not.
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
        } finally {
            retriever.release()
        }
        currentVideoPath = path
    }

    /**
     * Trims the loaded video. [onProgress] is invoked on the main thread with
     * values in 0..100.
     */
    suspend fun trimVideo(
        context: Context,
        startTimeMs: Long,
        endTimeMs: Long,
        includeAudio: Boolean,
        onProgress: (Double) -> Unit,
    ): String {
        val videoPath = currentVideoPath ?: throw VideoException("No video loaded")
        if (startTimeMs < 0 || endTimeMs <= startTimeMs) {
            throw VideoException("Invalid time range")
        }

        val outputFile = withContext(Dispatchers.IO) {
            val file = File(context.cacheDir, "video_trimmer_${System.currentTimeMillis()}.mp4")
            if (file.exists()) file.delete()
            file
        }

        return withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { continuation ->
                val mediaItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(File(videoPath)))
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(startTimeMs)
                            .setEndPositionMs(endTimeMs)
                            .build()
                    )
                    .build()

                val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                    .setRemoveAudio(!includeAudio)
                    .build()

                val builtTransformer = Transformer.Builder(context)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, result: ExportResult) {
                            onProgress(100.0)
                            continuation.resume(outputFile.absolutePath)
                        }

                        override fun onError(
                            composition: Composition,
                            result: ExportResult,
                            exception: ExportException,
                        ) {
                            continuation.resumeWithException(
                                VideoException("Failed to trim video", exception)
                            )
                        }
                    })
                    .experimentalSetTrimOptimizationEnabled(true)
                    .build()

                transformer = builtTransformer

                // Kick off the export; without this the listener never fires and
                // the coroutine would hang forever.
                builtTransformer.start(editedMediaItem, outputFile.absolutePath)

                // Poll progress on the main thread until the export resolves.
                val progressHolder = ProgressHolder()
                val ticker = object : Runnable {
                    override fun run() {
                        val active = transformer ?: return
                        val state = active.getProgress(progressHolder)
                        if (state != Transformer.PROGRESS_STATE_NOT_STARTED &&
                            continuation.isActive
                        ) {
                            onProgress(progressHolder.progress.toDouble())
                        }
                        if (continuation.isActive) {
                            mainHandler.postDelayed(this, 200)
                        }
                    }
                }
                onProgress(0.0)
                mainHandler.postDelayed(ticker, 200)

                continuation.invokeOnCancellation {
                    mainHandler.removeCallbacks(ticker)
                    transformer?.cancel()
                }
            }
        }
    }

    fun clearCache(context: Context) {
        context.cacheDir.listFiles()?.forEach { file ->
            if (file.name.startsWith("video_trimmer_") && file.extension == "mp4") {
                file.delete()
            }
        }
    }

    fun release() {
        transformer?.cancel()
        transformer = null
        currentVideoPath = null
    }

    companion object {
        private val mainHandler =
            android.os.Handler(android.os.Looper.getMainLooper())
    }
}

class VideoException : Exception {
    constructor(message: String) : super(message)
    constructor(message: String, cause: Throwable) : super(message, cause)
}
