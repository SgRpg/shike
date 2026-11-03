package com.shike.local.shike

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Save with a stable media URI; no system toast and no broad photo-read access. */
class ShikeAlbumBridge(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "shike/album")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    private val permissions = activity.getSharedPreferences("shike.album.permissions", Context.MODE_PRIVATE)
    init { channel.setMethodCallHandler { call, result ->
        when (call.method) {
            "save" -> {
                if (Build.VERSION.SDK_INT <= 28 && activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    if (pending != null) result.error("BUSY", "请先完成权限操作", null)
                    else if (permissions.getBoolean("requested", false) && !activity.shouldShowRequestPermissionRationale(Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
                        result.error("PERMISSION", "请在系统设置中允许保存图片", mapOf("settingsRequired" to true))
                    } else {
                        permissions.edit().putBoolean("requested", true).apply()
                        pending = call to result
                        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 6410)
                    }
                } else save(call, result)
            }
            "canSave" -> result.success(Build.VERSION.SDK_INT >= 29 || activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED)
            "openSettings" -> {
                activity.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                result.success(null)
            }
            "view" -> try {
                val uri = Uri.parse(call.argument<String>("uri") ?: error("图片位置为空"))
                activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "image/png")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    clipData = android.content.ClipData.newRawUri("拾刻", uri)
                })
                result.success(null)
            } catch (e: Exception) { result.error("VIEW", "可以前往相册查看", null) }
            else -> result.notImplemented()
        }
    } }
    fun permissionResult(code: Int) {
        if (code != 6410) return
        val item = pending ?: return
        pending = null
        if (activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) save(item.first, item.second)
        else item.second.error("PERMISSION", "相册保存权限未开启", mapOf("settingsRequired" to !activity.shouldShowRequestPermissionRationale(Manifest.permission.WRITE_EXTERNAL_STORAGE)))
    }
    private fun save(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            var inserted: Uri? = null
            try {
                val file = File(call.argument<String>("path") ?: error("图片为空")).canonicalFile
                require(file.path.startsWith(activity.cacheDir.canonicalPath + File.separator)) { "图片位置无效" }
                require(file.isFile && file.length() > 0) { "图片还没有准备好" }
                val name = File(call.argument<String>("name") ?: "拾刻.png").name
                val resolver = activity.contentResolver
                if (Build.VERSION.SDK_INT >= 29) {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                        put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/拾刻")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("无法创建相册图片")
                    inserted = uri
                    resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: error("无法保存图片")
                    val changed = resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
                    check(changed > 0) { "图片尚未写入相册" }
                    main.post { result.success(uri.toString()) }
                } else {
                    @Suppress("DEPRECATION")
                    val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "拾刻")
                    check(folder.exists() || folder.mkdirs())
                    val dest = File(folder, name)
                    try { file.copyTo(dest, overwrite = false) }
                    catch (e: Exception) { dest.delete(); throw e }
                    MediaScannerConnection.scanFile(activity, arrayOf(dest.path), arrayOf("image/png")) { _, uri ->
                        main.post {
                            if (uri != null) result.success(uri.toString())
                            else { dest.delete(); result.error("SAVE", "暂时无法登记相册图片", null) }
                        }
                    }
                }
            } catch (e: Exception) {
                inserted?.let { activity.contentResolver.delete(it, null, null) }
                main.post { result.error("SAVE", e.message ?: "暂时无法保存图片", null) }
            }
        }
    }
    fun dispose() {
        channel.setMethodCallHandler(null)
        pending?.second?.error("CANCELLED", "操作已结束", null)
        pending = null
        worker.shutdown()
    }
}
