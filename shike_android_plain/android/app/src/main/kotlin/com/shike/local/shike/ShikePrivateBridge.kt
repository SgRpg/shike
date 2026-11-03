package com.shike.local.shike

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.round

/** Android facilities; does not require Google Play services. */
class ShikePrivateBridge(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "shike/private")
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newCachedThreadPool()
    private val nearby = ShikeNearbyTransfer(activity) { path -> main.post { channel.invokeMethod("receivedBackup", path) } }
    private var pendingPermission: Pair<String, MethodChannel.Result>? = null
    private var scanResult: MethodChannel.Result? = null
    private var locationResult: MethodChannel.Result? = null
    private var locationListener: LocationListener? = null
    private var locationTimeout: Runnable? = null
    init { channel.setMethodCallHandler(::handle) }

    private fun error(result: MethodChannel.Result, message: String) = main.post { result.error("SHIKE", message, null) }
    private fun success(result: MethodChannel.Result, value: Any?) = main.post { result.success(value) }
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        workers.execute { try { success(result, work()) } catch (e: Exception) { error(result, e.message ?: "暂时无法完成") } }
    }
    private fun permission(name: String, method: String, result: MethodChannel.Result) {
        if (activity.checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED) {
            if (method == "locate") locate(result) else scan(result)
        } else if (pendingPermission == null) {
            pendingPermission = method to result
            activity.requestPermissions(arrayOf(name), 6401)
        } else error(result, "请先完成当前权限操作")
    }
    fun permissionResult(code: Int) {
        if (code != 6401) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        val name = if (pending.first == "locate") Manifest.permission.ACCESS_COARSE_LOCATION else Manifest.permission.CAMERA
        if (activity.checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED) {
            if (pending.first == "locate") locate(pending.second) else scan(pending.second)
        } else error(pending.second, if (pending.first == "locate") "定位未开启，可以手选城市" else "请允许相机权限以扫描配对码")
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "locate" -> permission(Manifest.permission.ACCESS_COARSE_LOCATION, "locate", result)
            "scanQR" -> permission(Manifest.permission.CAMERA, "scanQR", result)
            "weather" -> background(result) {
                val lat = round((call.argument<Number>("latitude") ?: error("缺少城市坐标")).toDouble() * 10) / 10
                val lng = round((call.argument<Number>("longitude") ?: error("缺少城市坐标")).toDouble() * 10) / 10
                val response = request("https://api.open-meteo.com/v1/forecast", mapOf("latitude" to "$lat", "longitude" to "$lng", "current" to "temperature_2m,weather_code", "timezone" to "auto"))
                toValue(response.getJSONObject("current"))
            }
            "searchCity" -> background(result) { toValue(request("https://geocoding-api.open-meteo.com/v1/search", mapOf("name" to (call.argument<String>("name") ?: ""), "count" to "8", "language" to "zh", "format" to "json"))) }
            "qrImage" -> background(result) {
                val text = call.argument<String>("text") ?: error("配对码为空")
                val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 900, 900, mapOf(EncodeHintType.MARGIN to 3, EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.CHARACTER_SET to "UTF-8"))
                val bitmap = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
                val pixels = IntArray(matrix.width * matrix.height) { i -> if (matrix[i % matrix.width, i / matrix.width]) 0xFF25272A.toInt() else 0xFFFFFDF9.toInt() }
                bitmap.setPixels(pixels, 0, matrix.width, 0, 0, matrix.width, matrix.height)
                ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out); bitmap.recycle(); out.toByteArray() }
            }
            "receive" -> background(result) { nearby.start() }
            "send" -> background(result) {
                nearby.send(call.argument<String>("pairing") ?: error("配对信息为空"), call.argument<ByteArray>("bytes") ?: error("备份为空")); null
            }
            "stopNearby" -> { nearby.stop(); result.success(null) }
            "permissionStatus" -> {
                fun granted(name: String) = activity.checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED
                val notifications = (activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).areNotificationsEnabled()
                result.success(mapOf("相机" to granted(Manifest.permission.CAMERA), "麦克风" to granted(Manifest.permission.RECORD_AUDIO), "定位" to granted(Manifest.permission.ACCESS_COARSE_LOCATION), "通知" to notifications))
            }
            "openSettings" -> {
                activity.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${activity.packageName}")))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
    private fun request(base: String, args: Map<String,String>): JSONObject {
        val query = args.entries.joinToString("&") { "${URLEncoder.encode(it.key, "UTF-8")}=${URLEncoder.encode(it.value, "UTF-8")}" }
        val conn = URL("$base?$query").openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 3000; conn.readTimeout = 3000
            if (conn.responseCode != 200) throw IllegalStateException("天气暂时无法获取")
            return JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
        } finally { conn.disconnect() }
    }
    private fun toValue(v: Any?): Any? = when (v) {
        null, JSONObject.NULL -> null
        is JSONObject -> v.keys().asSequence().associateWith { toValue(v.get(it)) }
        is JSONArray -> (0 until v.length()).map { toValue(v.get(it)) }
        else -> v
    }
    private fun locate(result: MethodChannel.Result) {
        if (locationResult != null) { error(result, "正在获取城市"); return }
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        locationResult = result
        try {
            val providers = listOf(LocationManager.NETWORK_PROVIDER).filter { manager.isProviderEnabled(it) }
            val cached = providers.mapNotNull { manager.getLastKnownLocation(it) }.filter { System.currentTimeMillis() - it.time in 0..900000 }.minByOrNull { it.accuracy }
            if (cached != null) { finishLocation(cached); return }
            if (providers.isEmpty()) { finishLocation(null); return }
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) { finishLocation(location) }
                @Deprecated("Compatibility") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
            }
            locationListener = listener
            for (provider in providers) manager.requestLocationUpdates(provider, 1000L, 1000f, listener, Looper.getMainLooper())
            locationTimeout = Runnable { finishLocation(null) }.also { main.postDelayed(it, 20000) }
        } catch (_: Exception) { finishLocation(null) }
    }
    private fun finishLocation(location: Location?) {
        val result = locationResult ?: return
        locationResult = null
        locationListener?.let { (activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(it) }
        locationListener = null
        locationTimeout?.let { main.removeCallbacks(it) }; locationTimeout = null
        if (location == null) { error(result, "暂时无法定位，请手选城市"); return }
        val lat = round(location.latitude * 10) / 10; val lng = round(location.longitude * 10) / 10
        // Coordinates are rounded before any external geocoder request.
        workers.execute {
            val task = workers.submit<String> {
                try {
                    @Suppress("DEPRECATION")
                    val place = Geocoder(activity, Locale.SIMPLIFIED_CHINESE).getFromLocation(lat,lng,1)?.firstOrNull()
                    place?.locality ?: place?.subAdminArea ?: place?.adminArea ?: ""
                } catch (_: Exception) { "" }
            }
            val city = try { task.get(3, java.util.concurrent.TimeUnit.SECONDS) } catch (_: Exception) { task.cancel(true); "" }
            success(result, mapOf("city" to city, "latitude" to lat, "longitude" to lng))
        }
    }
    private fun scan(result: MethodChannel.Result) {
        if (scanResult != null) { error(result, "扫描器已经打开"); return }
        scanResult = result
        activity.startActivityForResult(Intent(activity, ShikeScannerActivity::class.java), 6402)
    }
    fun activityResult(code: Int, result: Int, data: Intent?) {
        if (code != 6402) return
        scanResult?.success(if (result == Activity.RESULT_OK) data?.getStringExtra("text") else null)
        scanResult = null
    }
    fun dispose() {
        nearby.close()
        locationResult?.let { finishLocation(null) }
        pendingPermission?.second?.error("CANCELLED", "操作已结束", null); pendingPermission = null
        scanResult?.success(null); scanResult = null
        channel.setMethodCallHandler(null)
        workers.shutdownNow()
    }
}
