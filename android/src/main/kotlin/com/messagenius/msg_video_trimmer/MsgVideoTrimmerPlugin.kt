package com.messagenius.msg_video_trimmer

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Implements the Pigeon [VideoTrimmerHostApi] on top of [VideoManager] and
 * streams trim progress over the generated event channel.
 */
@UnstableApi
class MsgVideoTrimmerPlugin : FlutterPlugin, VideoTrimmerHostApi {
    private lateinit var context: Context
    private val videoManager = VideoManager()
    private val progressHandler = TrimProgressHandler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        VideoTrimmerHostApi.setUp(binding.binaryMessenger, this)
        TrimProgressStreamHandler.register(binding.binaryMessenger, progressHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        VideoTrimmerHostApi.setUp(binding.binaryMessenger, null)
        videoManager.release()
        scope.cancel()
    }

    override fun loadVideo(path: String, callback: (Result<Unit>) -> Unit) {
        try {
            videoManager.loadVideo(path)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun trimVideo(request: TrimRequest, callback: (Result<String>) -> Unit) {
        scope.launch {
            try {
                val path = videoManager.trimVideo(
                    context = context,
                    startTimeMs = request.startTimeMs,
                    endTimeMs = request.endTimeMs,
                    includeAudio = request.includeAudio,
                    onProgress = { progress ->
                        mainHandler.post { progressHandler.send(progress) }
                    },
                )
                callback(Result.success(path))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun clearCache(callback: (Result<Unit>) -> Unit) {
        try {
            videoManager.clearCache(context)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }
}

/** Captures the event-channel sink so progress can be pushed during a trim. */
class TrimProgressHandler : TrimProgressStreamHandler() {
    private var sink: PigeonEventSink<Double>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<Double>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        sink = null
    }

    fun send(value: Double) {
        sink?.success(value)
    }
}
