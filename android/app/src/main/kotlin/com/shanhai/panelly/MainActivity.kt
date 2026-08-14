package com.shanhai.panelly

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.shanhai.panelly/incoming_archives"
        private const val MAX_INCOMING_BYTES = 4L * 1024L * 1024L * 1024L
    }

    private val pendingEvents = ArrayDeque<Map<String, String>>()
    private val copyExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var incomingChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeIncomingArchiveEvent" -> {
                        val event = synchronized(pendingEvents) {
                            if (pendingEvents.isEmpty()) null else pendingEvents.removeFirst()
                        }
                        result.success(event)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onDestroy() {
        incomingChannel?.setMethodCallHandler(null)
        incomingChannel = null
        copyExecutor.shutdown()
        super.onDestroy()
    }

    private fun handleIncomingIntent(incomingIntent: Intent?) {
        if (incomingIntent == null) return
        val uris = extractUris(incomingIntent)
        if (uris.isEmpty()) return

        for (uri in uris) {
            copyExecutor.execute {
                try {
                    enqueueEvent("archive", copyToCache(uri).absolutePath)
                } catch (_: IncomingArchiveTooLargeException) {
                    enqueueEvent("error", "压缩包超过 4 GB，无法接收")
                } catch (_: IOException) {
                    enqueueEvent("error", "无法读取 QQ 发送的压缩包，请确认文件仍然存在且空间充足")
                } catch (_: SecurityException) {
                    enqueueEvent("error", "QQ 没有授予压缩包读取权限，请重新选择其他应用打开")
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun extractUris(incomingIntent: Intent): List<Uri> {
        val uris = linkedSetOf<Uri>()
        when (incomingIntent.action) {
            Intent.ACTION_VIEW -> incomingIntent.data?.let(uris::add)
            Intent.ACTION_SEND -> {
                incomingIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                incomingIntent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.let(uris::addAll)
            }
        }
        val clipData = incomingIntent.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        }

        if (uris.isNotEmpty()) {
            incomingIntent.action = Intent.ACTION_MAIN
            incomingIntent.data = null
            incomingIntent.removeExtra(Intent.EXTRA_STREAM)
            incomingIntent.clipData = null
        }
        return uris.toList()
    }

    private fun copyToCache(uri: Uri): File {
        val descriptor = queryDescriptor(uri)
        if (descriptor.size != null && descriptor.size > MAX_INCOMING_BYTES) {
            throw IncomingArchiveTooLargeException()
        }

        val directory = File(
            cacheDir,
            "incoming_archives/${UUID.randomUUID()}",
        ).apply { mkdirs() }
        val safeName = sanitizeFileName(descriptor.displayName)
        // Keep the original basename because ArchiveOrganizer uses it as the title.
        // A per-file directory still prevents simultaneous same-name imports colliding.
        val output = File(directory, safeName)

        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IOException("Content provider returned no stream")
            input.use { source ->
                FileOutputStream(output).use { destination ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var copied = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > MAX_INCOMING_BYTES) {
                            throw IncomingArchiveTooLargeException()
                        }
                        destination.write(buffer, 0, count)
                    }
                }
            }
            return output
        } catch (error: Exception) {
            output.delete()
            throw error
        }
    }

    private fun queryDescriptor(uri: Uri): IncomingDescriptor {
        var displayName: String? = null
        var size: Long? = null
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )
            if (cursor?.moveToFirst() == true) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    displayName = cursor.getString(nameIndex)
                }
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        } catch (_: RuntimeException) {
            // Some content providers expose a stream but do not support metadata queries.
        } finally {
            cursor?.close()
        }
        return IncomingDescriptor(displayName ?: "QQ漫画.zip", size)
    }

    private fun sanitizeFileName(displayName: String): String {
        val leafName = File(displayName).name
        val cleaned = leafName
            .replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
            .trim()
            .ifEmpty { "QQ漫画.zip" }
        return if (cleaned.endsWith(".zip", ignoreCase = true) ||
            cleaned.endsWith(".cbz", ignoreCase = true)
        ) {
            cleaned
        } else {
            "$cleaned.zip"
        }
    }

    private fun enqueueEvent(type: String, value: String) {
        synchronized(pendingEvents) {
            pendingEvents.addLast(mapOf("type" to type, "value" to value))
        }
        mainHandler.post {
            incomingChannel?.invokeMethod("incomingArchiveEvent", null)
        }
    }

    private data class IncomingDescriptor(val displayName: String, val size: Long?)

    private class IncomingArchiveTooLargeException : IOException()
}
