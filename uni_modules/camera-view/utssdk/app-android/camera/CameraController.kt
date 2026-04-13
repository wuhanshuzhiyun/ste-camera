package uts.ste.camera

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.hardware.Camera
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import io.dcloud.uts.UTSAndroid
import io.dcloud.uts.console
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock

/**
 * 相机核心控制器
 */
@Suppress("DEPRECATION")
object CameraController {
    private var camera: Camera? = null
    private var surfaceView: SurfaceView? = null
    // 保存容器尺寸，用于拍照时裁剪到与预览一致
    private var containerWidth: Int = 0
    private var containerHeight: Int = 0
    // 当前摄像头ID（0=后置，其他=前置）
    private var currentCameraId: Int = 0

    // SurfaceHolder.Callback 缓存，避免重复添加
    private var surfaceCallback: SurfaceHolder.Callback? = null
    // 相机打开回调（用于跨边界通知 UTS 层）
    private var cameraOpenCallback: CameraOpenCallback? = null

    fun startCameraPreview(activity: Activity, containerWidth: Int, containerHeight: Int, cameraFacing: String = "back", callback: CameraOpenCallback? = null) {
        this.containerWidth = containerWidth
        this.containerHeight = containerHeight
        this.currentCameraId = if (cameraFacing == "front") 1 else 0
        this.cameraOpenCallback = callback

        try {
            // 如果相机已经打开，立即触发成功回调
            if (camera != null) {
                callback?.onSuccess(currentCameraId)
                return
            }

            val holder = surfaceView?.holder
            if (holder != null) {
                // 移除所有旧回调，避免重复
                holder.removeCallback(surfaceCallback)
                surfaceCallback = createSurfaceCallback(activity, containerWidth, containerHeight)
                holder.addCallback(surfaceCallback)

                // 如果 Surface 已经创建，立即初始化相机（避免等待 surfaceCreated 回调）
                if (holder.surface?.isValid == true) {
                    initializeCamera(activity, holder)
                }
            } else {
                // SurfaceView 或 holder 为空，触发失败回调
                callback?.onFail(3, "SurfaceView 未准备好")
            }
        } catch (e: Exception) {
            console.log("打开相机失败：${e.message}")
            // 触发失败回调
            callback?.onFail(3, "打开相机失败：${e.message}")
        }
    }

    private fun createSurfaceCallback(activity: Activity, containerWidth: Int, containerHeight: Int): SurfaceHolder.Callback {
        return object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                if (camera != null) return
                initializeCamera(activity, holder)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                adjustSurfaceViewSize(containerWidth, containerHeight)
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                releaseCamera()
            }
        }
    }

    private fun initializeCamera(activity: Activity, holder: SurfaceHolder) {
        try {
            camera = Camera.open(currentCameraId).also { cam ->
                configureCamera(cam, activity)
                cam.setDisplayOrientation(getCameraDisplayOrientation(activity))
                cam.setPreviewDisplay(holder)
                cam.startPreview()
            }
            // 触发成功回调
            cameraOpenCallback?.onSuccess(currentCameraId)
        } catch (e: Exception) {
            console.log("打开相机失败：${e.message}")
            handleCameraOpenError(e)
            // 触发失败回调
            cameraOpenCallback?.onFail(2, "相机被占用或打开失败：${e.message}")
        }
    }

    private fun configureCamera(camera: Camera, activity: Activity) {
        val parameters = camera.parameters
        val supportedPreviewSizes = parameters.supportedPreviewSizes
        // containerWidth/Height 可能在 surfaceCreated 路径下还未赋值（为 0），兜底到 1920×1080
        val rawW = if (this.containerWidth > 0) this.containerWidth else 1920
        val rawH = if (this.containerHeight > 0) this.containerHeight else 1080
        // 相机传感器预览尺寸总是横向列出（宽 > 高），竖屏时需取 longSide/shortSide 再匹配，避免预览质量退化
        val longSide = maxOf(rawW, rawH)
        val shortSide = minOf(rawW, rawH)
        val optimalSize = getOptimalPreviewSize(supportedPreviewSizes, longSide, shortSide)

        if (optimalSize != null) {
            parameters.setPreviewSize(optimalSize.width, optimalSize.height)
        } else {
            val defaultSize = supportedPreviewSizes[0]
            parameters.setPreviewSize(defaultSize.width, defaultSize.height)
        }
        try {
            camera.parameters = parameters
        } catch (e: Exception) {
            console.log("设置参数失败，使用默认参数：${e.message}")
        }
    }

    private fun handleCameraOpenError(exception: Exception) {
        console.log("打开相机失败：${exception.message}")
        if (exception.message?.contains("Fail to connect to camera service") == true) {
            console.log("相机服务连接失败，可能是相机被占用或权限不足")
        }
    }

    private fun adjustSurfaceViewSize(containerWidth: Int, containerHeight: Int) {
        if (containerWidth <= 0 || containerHeight <= 0) return
        val currentCamera = camera ?: return
        val params = currentCamera.parameters
        val previewSize = params.previewSize ?: run {
            console.log("预览尺寸为空，无法调整")
            return
        }

        var previewWidth = previewSize.width
        var previewHeight = previewSize.height

        val activity = UTSAndroid.getUniActivity() ?: return
        val rotation = getCameraDisplayOrientation(activity)
        if (rotation == 90 || rotation == 270) {
            val temp = previewWidth
            previewWidth = previewHeight
            previewHeight = temp
        }

        val previewRatio = previewWidth.toDouble() / previewHeight
        val containerRatio = containerWidth.toDouble() / containerHeight

        val (newWidth, newHeight) = calculateSurfaceDimensions(previewRatio, containerRatio, containerWidth, containerHeight)

        surfaceView?.layoutParams = FrameLayout.LayoutParams(newWidth, newHeight).apply {
            gravity = android.view.Gravity.CENTER
        }
        surfaceView?.requestLayout()
    }

    private fun calculateSurfaceDimensions(
        previewRatio: Double,
        containerRatio: Double,
        containerWidth: Int,
        containerHeight: Int
    ): Pair<Int, Int> {
        return if (previewRatio > containerRatio) {
            val newHeight = containerHeight
            val newWidth = (containerHeight * previewRatio).toInt()
            newWidth to newHeight
        } else {
            val newWidth = containerWidth
            val newHeight = (containerWidth / previewRatio).toInt()
            newWidth to newHeight
        }
    }

    private fun getCameraDisplayOrientation(activity: Activity): Int {
        val info = Camera.CameraInfo()
        Camera.getCameraInfo(currentCameraId, info)

        val rotation = activity.windowManager.defaultDisplay.rotation
        val degrees = when (rotation) {
            android.view.Surface.ROTATION_0 -> 0
            android.view.Surface.ROTATION_90 -> 90
            android.view.Surface.ROTATION_180 -> 180
            android.view.Surface.ROTATION_270 -> 270
            else -> 0
        }

        return if (info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
            ((info.orientation + degrees) % 360).let { (360 - it) % 360 }
        } else {
            (info.orientation - degrees + 360) % 360
        }
    }

    private fun getOptimalPreviewSize(sizes: List<Camera.Size>, width: Int, height: Int): Camera.Size? {
        if (sizes.isEmpty()) return null

        val targetRatio = width.toDouble() / height
        var optimalSize: Camera.Size? = null
        var minDiff = Double.MAX_VALUE

        // 首先尝试找到满足最小尺寸要求的尺寸
        for (size in sizes) {
            if (size.width >= width && size.height >= height) {
                val ratio = size.width.toDouble() / size.height
                val diff = Math.abs(ratio - targetRatio)
                if (diff < minDiff) {
                    minDiff = diff
                    optimalSize = size
                }
            }
        }

        // 如果没有找到满足最小尺寸要求的尺寸，选比例最接近且像素最大的（避免低端机退化到最小分辨率）
        if (optimalSize == null) {
            console.log("未找到满足最小尺寸要求的预览尺寸，选比例最近的最大尺寸兜底")
            optimalSize = sizes.maxWithOrNull { a, b ->
                val ratioDiffA = Math.abs(a.width.toDouble() / a.height - targetRatio)
                val ratioDiffB = Math.abs(b.width.toDouble() / b.height - targetRatio)
                // 优先比例差小的；比例差相同时选像素多的
                when {
                    ratioDiffA < ratioDiffB -> 1
                    ratioDiffA > ratioDiffB -> -1
                    else -> (a.width * a.height).compareTo(b.width * b.height)
                }
            }
        }

        return optimalSize
    }

    /**
     * 点击对焦
     * 将屏幕坐标转换为相机的 (-1000, -1000) ~ (1000, 1000) 坐标系后设置对焦区域
     *
     * @param touchX        触摸点 X（相对于相机容器，px）
     * @param touchY        触摸点 Y（相对于相机容器，px）
     * @param containerW    相机容器宽度（px）
     * @param containerH    相机容器高度（px）
     */
    fun focusAt(touchX: Float, touchY: Float, containerW: Int, containerH: Int) {
        val currentCamera = camera ?: return
        if (containerW <= 0 || containerH <= 0) return
        try {
            val params = currentCamera.parameters

            // 检查是否支持对焦区域
            if (params.maxNumFocusAreas <= 0) {
                // 不支持区域对焦，降级为自动对焦
                if (params.supportedFocusModes?.contains(Camera.Parameters.FOCUS_MODE_AUTO) == true) {
                    params.focusMode = Camera.Parameters.FOCUS_MODE_AUTO
                    currentCamera.parameters = params
                    currentCamera.autoFocus(null)
                }
                return
            }

            // 将容器坐标映射到相机坐标系 (-1000 ~ 1000)
            val focusX = ((touchX / containerW) * 2000 - 1000).toInt().coerceIn(-1000, 1000)
            val focusY = ((touchY / containerH) * 2000 - 1000).toInt().coerceIn(-1000, 1000)

            // 对焦框大小（相机坐标系中的半径）
            val halfSize = 100
            val focusRect = Rect(
                (focusX - halfSize).coerceAtLeast(-1000),
                (focusY - halfSize).coerceAtLeast(-1000),
                (focusX + halfSize).coerceAtMost(1000),
                (focusY + halfSize).coerceAtMost(1000)
            )

            val focusArea = Camera.Area(focusRect, 1000)

            params.focusAreas = listOf(focusArea)

            // 同步设置测光区域（如果支持）
            if (params.maxNumMeteringAreas > 0) {
                params.meteringAreas = listOf(focusArea)
            }

            if (params.supportedFocusModes?.contains(Camera.Parameters.FOCUS_MODE_AUTO) == true) {
                params.focusMode = Camera.Parameters.FOCUS_MODE_AUTO
            }

            currentCamera.parameters = params
            currentCamera.autoFocus(null)
        } catch (e: Exception) {
            console.log("点击对焦失败：${e.message}")
        }
    }

    @Synchronized
    fun releaseCamera() {
        camera?.apply {
            // stopPreview 在拍照进行中调用会抛 RuntimeException，必须 try-catch
            try { stopPreview() } catch (e: Exception) { console.log("stopPreview 失败：${e.message}") }
            setPreviewCallback(null)
            release()
        }
        camera = null
        // 清零帧数据，防止切换摄像头窗口期用旧帧+新尺寸参数构造 YuvImage
        if (isScanModeRunning.get()) {
            frameLock.lock()
            try {
                latestFrameData = null
                latestFrameWidth = 0
                latestFrameHeight = 0
                latestFrameOrientation = 0
            } finally {
                frameLock.unlock()
            }
        }
    }

    fun takePicture(callback: TakePictureCallback) {
        val currentCamera = camera
        if (currentCamera == null) {
            console.log("相机未启动，无法拍照")
            callback.onFail()
            return
        }
        try {
            currentCamera.takePicture(
                Camera.ShutterCallback { },
                null,
                null,
                Camera.PictureCallback { data, _ ->
                    processCapturedImage(currentCamera, data) { path ->
                        if (path != null) callback.onSuccess(path) else callback.onFail()
                    }
                }
            )
        } catch (e: Exception) {
            console.log("拍照失败：${e.message}")
            callback.onFail()
        }
    }

    private fun processCapturedImage(camera: Camera, imageData: ByteArray, callback: (String?) -> Unit) {
        try {
            val activity = UTSAndroid.getUniActivity()
            var bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)

            if (activity != null) {
                val isFrontCamera = currentCameraId == 1

                // 前置摄像头：先镜像，再应用旋转
                if (isFrontCamera) {
                    val flippedBitmap = ImageProcessor.flipBitmapHorizontal(bitmap)
                    // 如果镜像后创建了新 Bitmap，回收旧的
                    if (flippedBitmap != bitmap && !bitmap.isRecycled) {
                        bitmap.recycle()
                    }
                    bitmap = flippedBitmap

                    // 前置摄像头自拍时，旋转角度需要取反
                    val info = Camera.CameraInfo()
                    Camera.getCameraInfo(currentCameraId, info)
                    val rotation = activity.windowManager.defaultDisplay.rotation
                    val degrees = when (rotation) {
                        android.view.Surface.ROTATION_0 -> 0
                        android.view.Surface.ROTATION_90 -> 90
                        android.view.Surface.ROTATION_180 -> 180
                        android.view.Surface.ROTATION_270 -> 270
                        else -> 0
                    }
                    // 前置摄像头使用不同的旋转公式
                    val frontRotation = ((info.orientation + degrees) % 360).let { (360 - it) % 360 }
                    if (frontRotation != 0) {
                        val rotatedBitmap = ImageProcessor.rotateBitmap(bitmap, frontRotation.toFloat())
                        // 如果旋转后创建了新 Bitmap，回收旧的
                        if (rotatedBitmap != bitmap && !bitmap.isRecycled) {
                            bitmap.recycle()
                        }
                        bitmap = rotatedBitmap
                    }
                } else {
                    // 后置摄像头：直接应用旋转
                    val rotation = getCameraDisplayOrientation(activity)
                    if (rotation != 0) {
                        val rotatedBitmap = ImageProcessor.rotateBitmap(bitmap, rotation.toFloat())
                        // 如果旋转后创建了新 Bitmap，回收旧的
                        if (rotatedBitmap != bitmap && !bitmap.isRecycled) {
                            bitmap.recycle()
                        }
                        bitmap = rotatedBitmap
                    }
                }

                // 按照相机容器尺寸的比例裁剪照片，确保与预览窗口完全一致
                if (containerWidth > 0 && containerHeight > 0) {
                    val targetRatio = containerWidth.toFloat() / containerHeight.toFloat()
                    val photoWidth = bitmap.width.toFloat()
                    val photoHeight = bitmap.height.toFloat()
                    val photoRatio = photoWidth / photoHeight

                    // 如果照片比例与容器比例不一致，进行居中裁剪
                    if (Math.abs(photoRatio - targetRatio) > 0.01f) {
                        val croppedBitmap = cropBitmapToRatio(bitmap, targetRatio)
                        // 裁剪后创建了新 Bitmap，回收旧的
                        if (croppedBitmap != bitmap && !bitmap.isRecycled) {
                            bitmap.recycle()
                        }
                        bitmap = croppedBitmap
                    }
                }

                val watermarks = CameraViewManager.getWatermarkConfigs()
                if (watermarks.isNotEmpty()) {
                    // 将容器宽度从 px 转换为 dp 传入，确保水印位置在非全屏容器下也正确
                    val containerWidthDp = if (containerWidth > 0) {
                        (containerWidth / activity.resources.displayMetrics.density).toInt()
                    } else 0
                    val watermarkedBitmap = ImageProcessor.drawWatermarks(activity, bitmap, watermarks, containerWidthDp)
                    // drawWatermarks 创建了新 Bitmap，回收旧的
                    if (watermarkedBitmap != bitmap && !bitmap.isRecycled) {
                        bitmap.recycle()
                    }
                    bitmap = watermarkedBitmap
                }
            }

            val imagePath = ImageProcessor.saveBitmapToFile(activity, bitmap)
            // 保存图片后回收 bitmap
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
            camera.startPreview()
            callback(imagePath)
        } catch (e: Throwable) {
            console.log("处理拍照图片失败：${e.message}")
            callback(null)
            try { camera.startPreview() } catch (e2: Throwable) {
                console.log("拍照失败后恢复预览失败：${e2.message}")
            }
        }
    }

    /**
     * 按照目标比例裁剪图片（居中裁剪）
     */
    private fun cropBitmapToRatio(bitmap: Bitmap, targetRatio: Float): Bitmap {
        val photoWidth = bitmap.width.toFloat()
        val photoHeight = bitmap.height.toFloat()
        val photoRatio = photoWidth / photoHeight

        val (cropWidth, cropHeight) = if (photoRatio > targetRatio) {
            // 照片更宽，裁剪宽度
            val newWidth = (photoHeight * targetRatio).toInt()
            newWidth to photoHeight.toInt()
        } else {
            // 照片更高，裁剪高度
            val newHeight = (photoWidth / targetRatio).toInt()
            photoWidth.toInt() to newHeight
        }

        val x = ((photoWidth - cropWidth) / 2).toInt()
        val y = ((photoHeight - cropHeight) / 2).toInt()

        return Bitmap.createBitmap(bitmap, x.coerceAtLeast(0), y.coerceAtLeast(0),
            cropWidth.coerceAtMost(bitmap.width), cropHeight.coerceAtMost(bitmap.height))
    }

    fun resumePreview() {
        camera?.startPreview()
    }

    fun setSurfaceView(surfaceView: SurfaceView) {
        this.surfaceView = surfaceView
    }

    fun getSurfaceView(): SurfaceView? = surfaceView

    fun isCameraAvailable(): Boolean = camera != null

    fun getCurrentCameraFacing(): String = if (currentCameraId == 1) "front" else "back"

    fun switchCamera(activity: Activity, containerWidth: Int, containerHeight: Int) {
        this.containerWidth = containerWidth
        this.containerHeight = containerHeight

        // 切换摄像头ID
        currentCameraId = if (currentCameraId == 0) 1 else 0

        // 释放当前相机
        releaseCamera()

        try {
            camera = Camera.open(currentCameraId)
            camera?.let { cam ->
                configureCamera(cam, activity)
                cam.setDisplayOrientation(getCameraDisplayOrientation(activity))
                cam.setPreviewDisplay(surfaceView?.holder)
                cam.startPreview()
                // 如果扫码模式正在运行，需要重新设置预览回调
                if (isScanModeRunning.get()) {
                    // 切换摄像头后刷新缓存的预览尺寸和帧方向
                    val previewSize = cam.parameters.previewSize
                    cachedPreviewWidth = previewSize?.width ?: 0
                    cachedPreviewHeight = previewSize?.height ?: 0
                    val act = UTSAndroid.getUniActivity()
                    cachedFrameOrientation = if (act != null) getCameraDisplayOrientation(act) else 0
                    setupPreviewCallback()
                }
            }

        } catch (e: Exception) {
            console.log("切换摄像头失败：${e.message}")
            // 切换失败时尝试切回原摄像头
            try {
                currentCameraId = if (currentCameraId == 0) 1 else 0
                camera = Camera.open(currentCameraId)
                camera?.let { cam ->
                    configureCamera(cam, activity)
                    cam.setDisplayOrientation(getCameraDisplayOrientation(activity))
                    cam.setPreviewDisplay(surfaceView?.holder)
                    cam.startPreview()
                    // 如果扫码模式正在运行，需要重新设置预览回调
                    if (isScanModeRunning.get()) {
                        val previewSize = cam.parameters.previewSize
                        cachedPreviewWidth = previewSize?.width ?: 0
                        cachedPreviewHeight = previewSize?.height ?: 0
                        val act = UTSAndroid.getUniActivity()
                        cachedFrameOrientation = if (act != null) getCameraDisplayOrientation(act) else 0
                        setupPreviewCallback()
                    }
                }
            } catch (e2: Exception) {
                console.log("恢复原摄像头也失败：${e2.message}")
                // 两次都失败：相机为 null，扫码模式状态必须重置，否则 isScanModeRunning==true
                // 但 camera==null，会导致 getScanFrame 绕过检查返回空帧，扫码静默失效
                if (isScanModeRunning.get()) {
                    isScanModeRunning.set(false)
                    frameLock.lock()
                    try {
                        latestFrameData = null
                        latestFrameWidth = 0
                        latestFrameHeight = 0
                    } finally {
                        frameLock.unlock()
                    }
                }
            }
        }
    }

    // ============ 扫码模式相关 ============
    // 使用AtomicBoolean保证线程安全
    private val isScanModeRunning = AtomicBoolean(false)
    // 锁保护帧数据访问
    private val frameLock = ReentrantLock()
    // 最新的预览帧数据（YUV格式）
    @Volatile
    private var latestFrameData: ByteArray? = null
    // 最新的预览帧参数（用于后续处理）
    @Volatile
    private var latestFrameWidth: Int = 0
    @Volatile
    private var latestFrameHeight: Int = 0
    @Volatile
    private var latestFrameOrientation: Int = 0
    // 缓存的预览尺寸，避免在 onPreviewFrame 里每帧调用 camera.parameters
    @Volatile
    private var cachedPreviewWidth: Int = 0
    @Volatile
    private var cachedPreviewHeight: Int = 0
    // 缓存的帧方向，在 startScanMode / switchCamera 时更新，避免每帧触发 JNI + Binder IPC
    @Volatile
    private var cachedFrameOrientation: Int = 0

    /**
     * 启动扫码模式
     * 初始化预览回调，持续获取摄像头帧数据
     */
    fun startScanMode(): Boolean {
        if (isScanModeRunning.get()) {
            console.log("扫码模式已在运行中")
            return true
        }

        val currentCamera = camera
        if (currentCamera == null) {
            console.log("相机未启动，无法启动扫码模式")
            return false
        }

        try {
            // 缓存一次预览尺寸，避免在 onPreviewFrame 里每帧调用 camera.parameters（BUG3 修复）
            val previewSize = currentCamera.parameters.previewSize
            cachedPreviewWidth = previewSize?.width ?: 0
            cachedPreviewHeight = previewSize?.height ?: 0
            // 缓存一次帧方向（getCameraDisplayOrientation 含 JNI + Binder IPC，不应每帧调用）
            val activity = UTSAndroid.getUniActivity()
            cachedFrameOrientation = if (activity != null) getCameraDisplayOrientation(activity) else 0

            isScanModeRunning.set(true)
            setupPreviewCallback()
            return true
        } catch (e: Exception) {
            isScanModeRunning.set(false)
            console.log("启动扫码模式失败：${e.message}")
            return false
        }
    }

    /**
     * 设置预览回调，持续获取帧数据
     */
    private fun setupPreviewCallback() {
        val currentCamera = camera ?: return
        try {
            currentCamera.setPreviewCallback(object : Camera.PreviewCallback {
                override fun onPreviewFrame(data: ByteArray?, camera: Camera) {
                    if (data == null || !isScanModeRunning.get()) return
                    // 直接使用缓存的预览尺寸和帧方向，避免每帧调用 camera.parameters / JNI / Binder IPC
                    frameLock.lock()
                    try {
                        latestFrameData = data
                        latestFrameWidth = cachedPreviewWidth
                        latestFrameHeight = cachedPreviewHeight
                        latestFrameOrientation = cachedFrameOrientation
                    } finally {
                        frameLock.unlock()
                    }
                }
            })
        } catch (e: Exception) {
            console.log("设置预览回调失败：${e.message}")
        }
    }

    /**
     * 停止扫码模式
     */
    fun stopScanMode(): Boolean {
        if (!isScanModeRunning.get()) {
            console.log("扫码模式未在运行")
            return true
        }

        try {
            // 清除预览回调
            camera?.setPreviewCallback(null)

            // 清除缓存的帧数据
            frameLock.lock()
            try {
                latestFrameData = null
                latestFrameWidth = 0
                latestFrameHeight = 0
                latestFrameOrientation = 0
            } finally {
                frameLock.unlock()
            }

            isScanModeRunning.set(false)
            return true
        } catch (e: Exception) {
            console.log("停止扫码模式失败：${e.message}")
            return false
        }
    }

    /**
     * 获取当前帧用于扫码（核心API）
     * 快速返回最新的一帧数据，转换为JPEG格式的Base64字符串
     * 该方法为同步调用，会快速返回，适合频繁调用
     *
     * @param quality JPEG压缩质量 (1-100)，建议80-90以平衡质量和性能
     * @return Base64编码的JPEG图片数据，如果获取失败返回null
     */
    fun getScanFrame(quality: Int = 85): String? {
        if (!isScanModeRunning.get()) {
            console.log("扫码模式未启动，请先调用startScanMode()")
            return null
        }

        val data: ByteArray?
        val width: Int
        val height: Int
        val orientation: Int

        // 快速获取最新帧数据的快照（持锁时间最短）
        frameLock.lock()
        try {
            data = latestFrameData
            width = latestFrameWidth
            height = latestFrameHeight
            orientation = latestFrameOrientation
        } finally {
            frameLock.unlock()
        }

        if (data == null || width <= 0 || height <= 0) {
            return null
        }

        // 直接在调用线程同步执行转换，不依赖主线程
        // 避免：1) 主线程被图片处理任务阻塞导致 UI 卡顿/ANR
        //       2) CountDownLatch.await 超时导致低端机扫码帧丢失
        return convertScanFrame(data, width, height, orientation, quality)
    }

    private fun convertScanFrame(
        data: ByteArray,
        width: Int,
        height: Int,
        orientation: Int,
        quality: Int
    ): String? {
        return try {
            val yuvImage = android.graphics.YuvImage(
                data,
                android.graphics.ImageFormat.NV21,
                width,
                height,
                null
            )
            val outputStream = java.io.ByteArrayOutputStream()
            val compressed = yuvImage.compressToJpeg(
                android.graphics.Rect(0, 0, width, height),
                quality.coerceIn(1, 100),
                outputStream
            )
            if (!compressed) return null

            val jpegData = outputStream.toByteArray()
            var bitmap = BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size)

            if (orientation != 0) {
                val rotated = ImageProcessor.rotateBitmap(bitmap, orientation.toFloat())
                if (rotated != bitmap && !bitmap.isRecycled) bitmap.recycle()
                bitmap = rotated
            }
            if (currentCameraId == 1) {
                val flipped = ImageProcessor.flipBitmapHorizontal(bitmap)
                if (flipped != bitmap && !bitmap.isRecycled) bitmap.recycle()
                bitmap = flipped
            }

            val finalStream = java.io.ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, finalStream)
            val base64 = android.util.Base64.encodeToString(finalStream.toByteArray(), android.util.Base64.NO_WRAP)
            bitmap.recycle()
            base64
        } catch (e: Throwable) {
            console.log("转换扫码帧失败：${e.message}")
            null
        }
    }

    /**
     * 检查扫码模式是否正在运行
     */
    fun isScanModeActive(): Boolean = isScanModeRunning.get()
}
