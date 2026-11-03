package com.shike.local.shike

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var bridge: ShikePrivateBridge? = null
    private var album: ShikeAlbumBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = ShikePrivateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        album = ShikeAlbumBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.permissionResult(requestCode)
        album?.permissionResult(requestCode)
    }
    @Deprecated("Activity result retained for Flutter native bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        bridge?.activityResult(requestCode, resultCode, data)
    }
    override fun onDestroy() { album?.dispose(); bridge?.dispose(); super.onDestroy() }
}
