package uts.ste.camera

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import io.dcloud.uts.console
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 相机视图管理器
 */
@Suppress("DEPRECATION")
object CameraViewManager {
    private var cameraContainer: FrameLayout? = null
    private var isCameraShowing: Boolean = false
    private val watermarkConfigs: MutableList<Map<String, Any?>> = mutableListOf()
    private val preloadedBitmaps: MutableMap<String, Bitmap> = mutableMapOf()
    @Volatile
    private var preloadExecutor: java.util.concurrent.ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // 扫描条相关
    private var scanBarView: ImageView? = null
    private var scanBarAnimator: AnimatorSet? = null

    /**
     * 获取线程池，不存在则创建
     */
    private fun getPreloadExecutor(): java.util.concurrent.ExecutorService {
        return preloadExecutor ?: synchronized(this) {
            preloadExecutor ?: Executors.newSingleThreadExecutor().also { preloadExecutor = it }
        }
    }

    // 样式默认值
    private const val DEFAULT_FONT_SIZE = 14
    private const val DEFAULT_FONT_COLOR = "#FFFFFF"
    private const val DEFAULT_FONT_WEIGHT = "normal"
    private const val DEFAULT_TEXT_ALIGN = "left"
    private const val DEFAULT_IMG_WIDTH = 100
    private const val DEFAULT_IMG_HEIGHT = 100

    fun showCameraView(
        activity: Activity,
        width: Int? = null,
        height: Int? = null,
        top: Int? = null,
        left: Int? = null,
        views: List<Map<String, Any?>>? = null,
        scanBar: Map<String, Any?>? = null
    ) {
        if (isCameraShowing) {
            return
        }

        // 确保线程池可用（如果已被关闭则重新创建）
        if (preloadExecutor == null || preloadExecutor!!.isShutdown || preloadExecutor!!.isTerminated) {
            preloadExecutor = Executors.newSingleThreadExecutor()
        }

        val displayMetrics = activity.resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels

        val finalWidth = width?.let { dipToPx(activity, it) } ?: screenWidth
        val finalHeight = height?.let { dipToPx(activity, it) } ?: screenHeight
        val finalTop = top?.let { dipToPx(activity, it) } ?: 0
        val finalLeft = left?.let { dipToPx(activity, it) } ?: 0

        cameraContainer = createCameraContainer(activity, finalWidth, finalHeight, finalTop, finalLeft)

        val surfaceView = createSurfaceView(activity)
        CameraController.setSurfaceView(surfaceView)
        cameraContainer!!.addView(surfaceView)

        views?.forEach { viewConfig -> addCustomView(activity, viewConfig) }

        // 初始化扫描条
        if (scanBar != null) {
            setupScanBar(activity, scanBar, finalWidth, finalHeight)
        }

        activity.addContentView(cameraContainer!!, cameraContainer!!.layoutParams as FrameLayout.LayoutParams)
        isCameraShowing = true
    }

    private fun createCameraContainer(activity: Activity, width: Int, height: Int, topMargin: Int, leftMargin: Int): FrameLayout {
        return FrameLayout(activity).apply {
            layoutParams = FrameLayout.LayoutParams(width, height).apply {
                gravity = Gravity.TOP or Gravity.START
                this.topMargin = topMargin
                this.leftMargin = leftMargin
            }
            setBackgroundColor(Color.BLACK)
        }
    }

    private fun createSurfaceView(activity: Activity): SurfaceView {
        return SurfaceView(activity).apply {
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        }
    }

    fun updateViews(activity: Activity, views: List<Map<String, Any?>>? = null) {
        if (!isCameraShowing) {
            console.log("相机未显示，无法更新视图")
            return
        }
        clearCustomViews()
        views?.forEach { viewConfig -> addCustomView(activity, viewConfig) }
    }

    fun addView(activity: Activity, viewConfig: Map<String, Any?>) {
        if (!isCameraShowing) {
            console.log("相机未显示，无法添加视图")
            return
        }
        try {
            addCustomView(activity, viewConfig)
        } catch (e: Exception) {
            console.log("添加视图失败：${e.message}")
        }
    }

    fun updateView(activity: Activity, uid: String, viewConfig: Map<String, Any?>) {
        if (!isCameraShowing) {
            console.log("相机未显示，无法更新视图")
            return
        }
        removeViewByUid(uid)
        val mutableConfig = viewConfig.toMutableMap()
        mutableConfig["uid"] = uid
        try {
            addCustomView(activity, mutableConfig)
        } catch (e: Exception) {
            console.log("更新视图失败：${e.message}")
        }
    }

    fun removeView(activity: Activity, uid: String) {
        if (!isCameraShowing) {
            console.log("相机未显示，无法移除视图")
            return
        }
        removeViewByUid(uid)
    }

    private fun removeViewByUid(uid: String) {
        cameraContainer?.let { container ->
            val surfaceView = CameraController.getSurfaceView()
            for (i in container.childCount - 1 downTo 0) {
                val child = container.getChildAt(i)
                if (child == surfaceView) continue
                if (child.tag == uid) {
                    container.removeView(child)
                    val removed = watermarkConfigs.filter { (it["uid"] as? String) == uid }
                    watermarkConfigs.removeAll { (it["uid"] as? String) == uid }
                    removed.forEach { config ->
                        val url = config["image"] as? String
                        if (url != null) {
                            // 回收 Bitmap 内存
                            preloadedBitmaps[url]?.let { bitmap ->
                                if (!bitmap.isRecycled) {
                                    bitmap.recycle()
                                }
                            }
                            preloadedBitmaps.remove(url)
                        }
                    }
                    return
                }
            }
            console.log("未找到 uid 为 $uid 的视图")
        }
    }

    fun getWatermarkConfigs(): List<Map<String, Any?>> = watermarkConfigs.toList()

    fun clearViews(activity: Activity) {
        if (!isCameraShowing) {
            console.log("相机未显示，无法清除视图")
            return
        }
        clearCustomViews()
    }

    private fun clearCustomViews() {
        cameraContainer?.let { container ->
            val surfaceView = CameraController.getSurfaceView()
            for (i in container.childCount - 1 downTo 0) {
                val child = container.getChildAt(i)
                // 跳过 SurfaceView 和扫描条 ImageView，避免误删
                if (child == surfaceView || child == scanBarView) continue
                container.removeView(child)
            }
        }
        // 回收所有 Bitmap 内存
        preloadedBitmaps.values.forEach { bitmap ->
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
        watermarkConfigs.clear()
        preloadedBitmaps.clear()
    }

    fun closeCameraView(activity: Activity) {
        if (!isCameraShowing) {
            console.log("相机未显示，无需关闭")
            return
        }
        // 立即置为 false，防止并发重入
        isCameraShowing = false
        try {
            val containerToRemove = cameraContainer
            val barView = scanBarView

            // 动画操作 & View 移除必须在主线程
            activity.runOnUiThread {
                try {
                    // 先停动画（Animator.cancel 要求主线程）
                    scanBarAnimator?.cancel()
                    scanBarAnimator = null
                    barView?.clearAnimation()
                    scanBarView = null

                    containerToRemove?.let { container ->
                        (container.parent as? ViewGroup)?.removeView(container)
                    }
                } catch (e: Exception) {
                    console.log("移除相机容器失败：${e.message}")
                }
            }

            // 回收 Bitmap 内存
            preloadedBitmaps.values.forEach { bitmap ->
                if (!bitmap.isRecycled) {
                    bitmap.recycle()
                }
            }

            cameraContainer = null
            watermarkConfigs.clear()
            preloadedBitmaps.clear()

            // 关闭线程池
            try {
                preloadExecutor?.let { executor ->
                    executor.shutdown()
                    if (!executor.awaitTermination(5, TimeUnit.SECONDS)) {
                        executor.shutdownNow()
                    }
                }
                preloadExecutor = null
            } catch (e: Exception) {
                console.log("关闭线程池失败：${e.message}")
                preloadExecutor?.shutdownNow()
                preloadExecutor = null
            }
        } catch (e: Exception) {
            console.log("关闭相机失败：${e.message}")
        }
    }

    private fun addCustomView(activity: Activity, viewConfig: Map<String, Any?>) {
        val type = viewConfig["type"] as? String ?: return
        val uid = viewConfig["uid"] as? String
        val isWatermark = viewConfig["watermark"] as? Boolean ?: false

        if (isWatermark) {
            if (uid != null) watermarkConfigs.removeAll { (it["uid"] as? String) == uid }
            watermarkConfigs.add(viewConfig)

            if (type == "image") {
                val imageUrl = viewConfig["image"] as? String
                if (!imageUrl.isNullOrEmpty() && !preloadedBitmaps.containsKey(imageUrl)) {
                    preloadWatermarkImage(imageUrl)
                }
            }
        }

        when (type) {
            "text" -> addTextView(activity, viewConfig, uid)
            "image" -> addImageView(activity, viewConfig, uid)
        }
    }

    private fun preloadWatermarkImage(imageUrl: String) {
        getPreloadExecutor().submit {
            try {
                val bitmap = if (imageUrl.startsWith("http")) {
                    val connection = java.net.URL(imageUrl).openConnection() as java.net.HttpURLConnection
                    connection.connectTimeout = 15_000
                    connection.readTimeout = 15_000
                    connection.requestMethod = "GET"
                    // 设置 User-Agent，模拟浏览器请求
                    connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; Mobile) camera-view/1.0")
                    connection.useCaches = false
                    try {
                        connection.connect()
                        val responseCode = connection.responseCode
                        if (responseCode == java.net.HttpURLConnection.HTTP_OK) {
                            BitmapFactory.decodeStream(connection.inputStream)
                        } else {
                            console.log("水印图片下载失败，HTTP状态码：$responseCode，url=$imageUrl")
                            null
                        }
                    } finally {
                        connection.disconnect()
                    }
                } else {
                    // 本地文件路径
                    val file = java.io.File(imageUrl)
                    if (file.exists()) {
                        BitmapFactory.decodeFile(imageUrl)
                    } else {
                        console.log("水印图片文件不存在：$imageUrl")
                        null
                    }
                }
                if (bitmap != null) {
                    preloadedBitmaps[imageUrl] = bitmap
                } else {
                    console.log("水印图片预加载失败：$imageUrl")
                }
            } catch (e: Exception) {
                console.log("水印图片预加载异常：${e.message}，url=$imageUrl")
            }
        }
    }

    fun getPreloadedBitmap(imageUrl: String): Bitmap? = preloadedBitmaps[imageUrl]

    private fun addTextView(activity: Activity, viewConfig: Map<String, Any?>, uid: String?) {
        val textView = TextView(activity).apply {
            text = viewConfig["text"] as? String ?: ""
            val style = viewConfig["style"] as? Map<*, *>
            applyTextStyle(activity, style)
            if (uid != null) tag = uid
        }
        cameraContainer?.addView(textView)
    }

    private fun TextView.applyTextStyle(activity: Activity, style: Map<*, *>?) {
        val fontSize = (style?.get("fontSize") as? Number)?.toInt() ?: DEFAULT_FONT_SIZE
        textSize = dipToPx(activity, fontSize).toFloat() / resources.displayMetrics.density

        val fontColor = style?.get("fontColor") as? String ?: DEFAULT_FONT_COLOR
        try {
            setTextColor(Color.parseColor(fontColor))
        } catch (e: Exception) {
            setTextColor(Color.WHITE)
        }

        val fontStyle = style?.get("fontStyle") as? String
        if (fontStyle == "italic") paint.textSkewX = -0.2f

        val fontWeight = style?.get("fontWeight") as? String ?: DEFAULT_FONT_WEIGHT
        paint.isFakeBoldText = fontWeight == "bold" || (fontWeight.toIntOrNull() ?: 0) >= 700

        // 应用位置
        val textAlign = style?.get("textAlign") as? String ?: DEFAULT_TEXT_ALIGN
        val textOffset = (style?.get("textOffset") as? Number)?.toInt() ?: 0
        val topMargin = style?.get("top") as? Number ?: 0

        layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.START
            this.topMargin = dipToPx(activity, topMargin.toInt())
        }

        cameraContainer?.post {
            val containerWidth = cameraContainer?.width ?: 0
            if (containerWidth > 0) {
                val params = layoutParams as FrameLayout.LayoutParams
                val offsetPx = dipToPx(activity, textOffset)
                when (textAlign) {
                    "center" -> { params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; params.leftMargin = offsetPx }
                    "right" -> { params.gravity = Gravity.TOP or Gravity.END; params.rightMargin = -offsetPx }
                    else -> { params.gravity = Gravity.TOP or Gravity.START; params.leftMargin = offsetPx }
                }
                layoutParams = params
            }
        }
    }

    private fun addImageView(activity: Activity, viewConfig: Map<String, Any?>, uid: String?) {
        val style = viewConfig["style"] as? Map<*, *>
        val rawWidth = (style?.get("width") as? Number)?.toInt()
        val rawHeight = (style?.get("height") as? Number)?.toInt()
        val topMargin = style?.get("top") as? Number ?: 0
        val leftMargin = style?.get("left") as? Number ?: 0

        val imageView = ImageView(activity).apply {
            // 宽高都传时拉伸；否则先用占位尺寸，图片加载后再根据实际情况更新
            val initW = rawWidth?.let { dipToPx(activity, it) } ?: (rawHeight?.let { dipToPx(activity, it) } ?: dipToPx(activity, DEFAULT_IMG_WIDTH))
            val initH = rawHeight?.let { dipToPx(activity, it) } ?: (rawWidth?.let { dipToPx(activity, it) } ?: dipToPx(activity, DEFAULT_IMG_HEIGHT))
            // 统一使用 FIT_XY：宽高都传时整体拉伸，缺一边时图片加载后会重新设置 layoutParams
            scaleType = ImageView.ScaleType.FIT_XY

            layoutParams = FrameLayout.LayoutParams(initW, initH).apply {
                gravity = Gravity.TOP or Gravity.START
                this.topMargin = dipToPx(activity, topMargin.toInt())
                this.leftMargin = dipToPx(activity, leftMargin.toInt())
            }

            if (uid != null) tag = uid

            val imageUrl = viewConfig["image"] as? String
            if (!imageUrl.isNullOrEmpty()) {
                val runnable = ImageLoadRunnable(imageUrl) { bitmap ->
                    bitmap ?: return@ImageLoadRunnable
                    this.setImageBitmap(bitmap)

                    // 根据传入的宽高决定最终尺寸：
                    //   - 都未传：使用图片实际像素宽高（转 dp 后转 px）
                    //   - 都传了：保持已设置的拉伸尺寸，无需修改
                    //   - 只传宽：高 = 宽 × (图片高/图片宽)
                    //   - 只传高：宽 = 高 × (图片宽/图片高)
                    if (rawWidth != null && rawHeight != null) return@ImageLoadRunnable

                    val bmpW = bitmap.width
                    val bmpH = bitmap.height
                    if (bmpW <= 0 || bmpH <= 0) return@ImageLoadRunnable

                    val finalW: Int
                    val finalH: Int
                    when {
                        rawWidth == null && rawHeight == null -> {
                            // 使用图片实际宽高（px，不做 dp→px 转换，直接用像素值会过大；按密度转为逻辑尺寸再转回 px）
                            finalW = bmpW
                            finalH = bmpH
                        }
                        rawWidth != null -> {
                            // 只传了宽，高按比例
                            val wPx = dipToPx(activity, rawWidth)
                            finalW = wPx
                            finalH = (wPx.toFloat() * bmpH / bmpW).toInt().coerceAtLeast(1)
                        }
                        else -> {
                            // 只传了高，宽按比例
                            val hPx = dipToPx(activity, rawHeight!!)
                            finalH = hPx
                            finalW = (hPx.toFloat() * bmpW / bmpH).toInt().coerceAtLeast(1)
                        }
                    }

                    val params = layoutParams as FrameLayout.LayoutParams
                    params.width = finalW
                    params.height = finalH
                    layoutParams = params
                }
                getPreloadExecutor().submit(runnable)
            }
        }
        cameraContainer?.addView(imageView)
    }

    /**
     * 使用 Handler 异步加载图片（替代废弃的 AsyncTask）
     */
    private class ImageLoadRunnable(
        private val imageUrl: String,
        private val onComplete: (Bitmap?) -> Unit
    ) : Runnable {
        override fun run() {
            val bitmap = try {
                if (imageUrl.startsWith("http")) {
                    val connection = java.net.URL(imageUrl).openConnection() as java.net.HttpURLConnection
                    connection.connectTimeout = 10_000
                    connection.readTimeout = 10_000
                    connection.requestMethod = "GET"
                    connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; Mobile) camera-view/1.0")
                    try {
                        connection.connect()
                        val responseCode = connection.responseCode
                        if (responseCode == java.net.HttpURLConnection.HTTP_OK) {
                            BitmapFactory.decodeStream(connection.inputStream)
                        } else {
                            console.log("图片加载失败，HTTP状态码：$responseCode")
                            null
                        }
                    } finally {
                        connection.disconnect()
                    }
                } else {
                    BitmapFactory.decodeFile(imageUrl)
                }
            } catch (e: Exception) {
                console.log("加载图片失败：${e.message}")
                null
            }

            // 在主线程回调
            mainHandler.post { onComplete(bitmap) }
        }
    }

    fun dipToPx(context: Activity, dip: Int): Int {
        return (dip * context.resources.displayMetrics.density + 0.5f).toInt()
    }

    fun isCameraShowing(): Boolean = isCameraShowing

    fun getCameraContainer(): FrameLayout? = cameraContainer

    // ============ 扫描条相关 ============

    /**
     * 初始化并显示扫描条，启动从 startY 到 endY 的无限循环动画（淡入淡出）
     *
     * @param activity          当前 Activity
     * @param scanBar           扫描条配置 Map（show / image / widthPercent / startY / endY）
     * @param containerWidthPx  相机容器宽度（px）
     * @param containerHeightPx 相机容器高度（px）
     *
     * startY / endY 均为距容器顶部的距离（dp），扫描条在两者之间来回运动
     */
    private fun setupScanBar(
        activity: Activity,
        scanBar: Map<String, Any?>,
        containerWidthPx: Int,
        containerHeightPx: Int
    ) {
        val imageUrl = scanBar["image"] as? String
        if (imageUrl.isNullOrEmpty()) {
            console.log("扫描条 image 未设置，跳过创建")
            return
        }

        val widthPercent = (scanBar["widthPercent"] as? Number)?.toFloat() ?: 80f
        val startYDp = (scanBar["startY"] as? Number)?.toInt() ?: 30
        val endYDp   = (scanBar["endY"]   as? Number)?.toInt() ?: (containerHeightPx / activity.resources.displayMetrics.density - 30).toInt()

        val density = activity.resources.displayMetrics.density

        // 扫描条宽度（px）= 容器宽度 × 百分比
        val barWidthPx = (containerWidthPx * widthPercent / 100f).toInt().coerceAtLeast(1)
        // 初始高度占位（加载完图片后按实际宽高比更新）
        val barHeightPx = (barWidthPx * 0.04f).toInt().coerceAtLeast(4)

        // dp → px
        val startYPx = (startYDp * density + 0.5f).toInt()
        val endYPx   = (endYDp   * density + 0.5f).toInt()

        // 创建 ImageView，水平居中，初始位于 startY
        val imageView = ImageView(activity).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            alpha = 0f   // 初始透明，由动画负责淡入
            layoutParams = FrameLayout.LayoutParams(barWidthPx, barHeightPx).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = startYPx
            }
        }

        // 异步加载图片
        getPreloadExecutor().submit {
            val bitmap = loadBitmapFromUrl(imageUrl)
            mainHandler.post {
                if (bitmap != null) {
                    imageView.setImageBitmap(bitmap)
                    // 按图片实际宽高比更新条高
                    val realHeight = if (bitmap.width > 0) {
                        (barWidthPx.toFloat() * bitmap.height / bitmap.width).toInt().coerceAtLeast(2)
                    } else barHeightPx
                    val params = imageView.layoutParams as FrameLayout.LayoutParams
                    params.height = realHeight
                    imageView.layoutParams = params

                    startScanBarAnimation(imageView, startYPx.toFloat(), endYPx.toFloat())
                } else {
                    console.log("扫描条图片加载失败：$imageUrl")
                    startScanBarAnimation(imageView, startYPx.toFloat(), endYPx.toFloat())
                }
            }
        }

        cameraContainer?.addView(imageView)
        scanBarView = imageView
    }

    /**
     * 启动扫描条动画：从 startYPx 平移到 endYPx，同时淡入淡出，无限循环。
     *
     * 透明度曲线（单程时长 = duration）：
     *   0% ~ 20%  : alpha 0 → 1  （淡入）
     *   20% ~ 80% : alpha 1       （完全不透明）
     *   80% ~ 100%: alpha 1 → 0  （淡出）
     *
     * 每次动画结束后重置到起点（alpha=0），再开始下一轮，形成平滑的消失/重现效果。
     *
     * @param view      扫描条 ImageView
     * @param startYPx  起点距容器顶部距离（px，绝对值）
     * @param endYPx    终点距容器顶部距离（px，绝对值）
     */
    private fun startScanBarAnimation(view: ImageView, startYPx: Float, endYPx: Float) {
        if (endYPx <= startYPx) {
            console.log("扫描条动画范围无效：startYPx=$startYPx endYPx=$endYPx，跳过动画")
            return
        }

        scanBarAnimator?.cancel()

        // View 使用 translationY 做位移（相对于自身 layoutParams.topMargin 所在位置）
        // layoutParams.topMargin 已设置为 startYPx，所以 translationY 从 0 到 (endYPx - startYPx)
        val travelY = endYPx - startYPx
        val duration = 2000L   // 单程时长 2 秒

        fun buildOneShot(): AnimatorSet {
            val translate = ObjectAnimator.ofFloat(view, "translationY", 0f, travelY).apply {
                this.duration = duration
                interpolator = LinearInterpolator()
            }

            // 分段透明度：0→1（前20%）→1（中间60%）→0（后20%）
            val fadeIn  = ObjectAnimator.ofFloat(view, "alpha", 0f, 1f).apply {
                this.duration = (duration * 0.2).toLong()
                startDelay = 0L
            }
            val hold = ObjectAnimator.ofFloat(view, "alpha", 1f, 1f).apply {
                this.duration = (duration * 0.6).toLong()
                startDelay = (duration * 0.2).toLong()
            }
            val fadeOut = ObjectAnimator.ofFloat(view, "alpha", 1f, 0f).apply {
                this.duration = (duration * 0.2).toLong()
                startDelay = (duration * 0.8).toLong()
            }

            return AnimatorSet().apply {
                playTogether(translate, fadeIn, hold, fadeOut)
            }
        }

        // 利用 AnimatorListenerAdapter 在每轮结束后重置并重新启动，实现无限循环
        fun scheduleLoop() {
            val set = buildOneShot()
            set.addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    // 被主动取消时不继续循环
                    if (scanBarAnimator == null) return
                    // 重置位置和透明度
                    view.translationY = 0f
                    view.alpha = 0f
                    // 开启下一轮
                    scheduleLoop()
                }
            })
            scanBarAnimator = set
            set.start()
        }

        // 初始状态
        view.translationY = 0f
        view.alpha = 0f
        scheduleLoop()
    }

    /**
     * 停止扫描条动画
     */
    private fun stopScanBarAnimation() {
        scanBarAnimator?.cancel()
        scanBarAnimator = null
        scanBarView?.clearAnimation()
    }

    /**
     * 动态显示扫描条（相机保持运行，仅创建/重建扫描条并启动动画）。
     * 若已存在扫描条则先销毁再重建，保证配置总是最新的。
     *
     * @param activity  当前 Activity
     * @param scanBar   扫描条配置 Map（image / widthPercent / startY / endY）
     */
    fun showScanBar(activity: Activity, scanBar: Map<String, Any?>) {
        // 先隐藏旧的（如果存在）
        hideScanBar()
        val container = cameraContainer ?: return
        setupScanBar(activity, scanBar, container.width, container.height)
    }

    /**
     * 动态隐藏扫描条（停止动画并从视图树移除，相机保持运行）。
     */
    fun hideScanBar() {
        stopScanBarAnimation()
        scanBarView?.let { v ->
            (v.parent as? android.view.ViewGroup)?.removeView(v)
        }
        scanBarView = null
    }

    /**
     * 从 URL 或本地路径同步加载 Bitmap（在子线程调用）
     */
    private fun loadBitmapFromUrl(imageUrl: String): Bitmap? {
        return try {
            if (imageUrl.startsWith("http")) {
                val connection = java.net.URL(imageUrl).openConnection() as java.net.HttpURLConnection
                connection.connectTimeout = 15_000
                connection.readTimeout = 15_000
                connection.requestMethod = "GET"
                connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; Mobile) camera-view/1.0")
                connection.useCaches = false
                try {
                    connection.connect()
                    if (connection.responseCode == java.net.HttpURLConnection.HTTP_OK) {
                        BitmapFactory.decodeStream(connection.inputStream)
                    } else {
                        console.log("扫描条图片下载失败，状态码：${connection.responseCode}")
                        null
                    }
                } finally {
                    connection.disconnect()
                }
            } else {
                val file = java.io.File(imageUrl)
                if (file.exists()) BitmapFactory.decodeFile(imageUrl)
                else { console.log("扫描条图片文件不存在：$imageUrl"); null }
            }
        } catch (e: Exception) {
            console.log("扫描条图片加载异常：${e.message}")
            null
        }
    }
}
