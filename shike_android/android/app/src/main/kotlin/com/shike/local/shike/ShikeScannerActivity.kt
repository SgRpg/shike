package com.shike.local.shike

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors

class ShikeScannerActivity : ComponentActivity() {
    private val analyzer = Executors.newSingleThreadExecutor()
    private var provider: ProcessCameraProvider? = null
    @Volatile private var completed = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val frame = FrameLayout(this)
        val preview = PreviewView(this)
        frame.addView(preview,FrameLayout.LayoutParams(-1,-1))
        val note = TextView(this).apply { text = "扫描另一部手机的拾刻配对码"; setTextColor(-1); textSize = 16f; gravity = Gravity.CENTER }
        frame.addView(note,FrameLayout.LayoutParams(-1,dp(64),Gravity.TOP).apply { topMargin = dp(48) })
        val cancel = Button(this).apply { text = "取消"; setOnClickListener { finish() } }
        frame.addView(cancel,FrameLayout.LayoutParams(dp(100),dp(52),Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(40) })
        setContentView(frame)
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val camera = future.get(); provider = camera
                val view = Preview.Builder().build().also { it.surfaceProvider = preview.surfaceProvider }
                val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                analysis.setAnalyzer(analyzer,::analyze)
                camera.bindToLifecycle(this,CameraSelector.DEFAULT_BACK_CAMERA,view,analysis)
            } catch (_: Exception) { note.text = "无法打开相机，请返回后重试" }
        },ContextCompat.getMainExecutor(this))
    }
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    private fun analyze(image: ImageProxy) {
        try {
            if (completed) return
            val plane = image.planes.first()
            val buffer = plane.buffer
            val data = ByteArray(image.width * image.height)
            for (y in 0 until image.height) for (x in 0 until image.width) data[y*image.width+x] = buffer.get(y*plane.rowStride+x*plane.pixelStride)
            var source: LuminanceSource = PlanarYUVLuminanceSource(data,image.width,image.height,0,0,image.width,image.height,false)
            val decoder = MultiFormatReader().apply { setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),DecodeHintType.TRY_HARDER to true)) }
            repeat(4) {
                val result = try { decoder.decodeWithState(BinaryBitmap(HybridBinarizer(source))) } catch (_: ReaderException) { null }
                if (result != null) {
                    completed = true
                    runOnUiThread { setResult(Activity.RESULT_OK,Intent().putExtra("text",result.text)); finish() }
                    return
                }
                source = source.rotateCounterClockwise()
            }
        } catch (_: Exception) { /* Try the next frame. */ }
        finally { image.close() }
    }
    override fun onDestroy() { provider?.unbindAll(); analyzer.shutdownNow(); super.onDestroy() }
}
