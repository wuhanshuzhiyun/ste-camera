package uts.ste.camera

import android.app.Activity
import android.view.ViewTreeObserver
import io.dcloud.uts.UTSAndroid
import io.dcloud.uts.console

/**
 * 相机页面统一入口
 */
@Suppress("DEPRECATION")
object CameraView {

    private inline fun withActivity(action: (Activity) -> Unit) {
        val activity = UTSAndroid.getUniActivity()
        if (activity == null || activity.isFinishing) {
            console.log("Activity is not available")
            return
        }
        // 检查 Activity 是否已销毁
        if (activity.isDestroyed) {
            console.log("Activity is destroyed")
            return
        }
        action(activity)
    }

    fun showCamera(
        width: Int? = null,
        height: Int? = null,
        top: Int? = null,
        left: Int? = null,
        cameraFacing: String = "back",
        views: List<Map<String, Any?>>? = null,
        scanBar: Map<String, Any?>? = null,
        callback: CameraOpenCallback? = null
    ) {
        if (CameraViewManager.isCameraShowing()) {
            // 相机已显示，立即触发成功回调
            callback?.onSuccess(if (cameraFacing == "front") 1 else 0)
            return
        }

        withActivity { activity ->
            activity.runOnUiThread {
                try {
                    CameraViewManager.showCameraView(activity, width, height, top, left, views, scanBar)

                    val displayMetrics = activity.resources.displayMetrics
                    val containerWidth = width?.let { CameraViewManager.dipToPx(activity, it) } ?: displayMetrics.widthPixels
                    val containerHeight = height?.let { CameraViewManager.dipToPx(activity, it) } ?: displayMetrics.heightPixels

                    CameraController.startCameraPreview(activity, containerWidth, containerHeight, cameraFacing, callback)
                } catch (e: Exception) {
                    console.log("显示相机页面失败：${e.message}")
                    // 触发失败回调
                    callback?.onFail(3, "显示相机页面失败：${e.message}")
                }
            }
        }
    }

    fun updateViews(views: List<Map<String, Any?>>? = null) {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法更新视图")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.updateViews(activity, views) }
        }
    }

    fun addView(viewConfig: Map<String, Any?>) {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法添加视图")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.addView(activity, viewConfig) }
        }
    }

    fun updateView(uid: String, viewConfig: Map<String, Any?>) {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法更新视图")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.updateView(activity, uid, viewConfig) }
        }
    }

    fun removeView(uid: String) {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法移除视图")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.removeView(activity, uid) }
        }
    }

    fun clearViews() {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法清除视图")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.clearViews(activity) }
        }
    }

    /**
     * 动态显示扫描条（相机保持运行，仅创建/重建扫描条并启动动画）
     * @param scanBar 扫描条配置 Map（image / widthPercent / startY / endY）
     */
    fun showScanBar(scanBar: Map<String, Any?>) {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法显示扫描条")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.showScanBar(activity, scanBar) }
        }
    }

    /**
     * 动态隐藏扫描条（停止动画并移除视图，相机保持运行）
     */
    fun hideScanBar() {
        withActivity { activity ->
            activity.runOnUiThread { CameraViewManager.hideScanBar() }
        }
    }

    fun closeCamera() {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无需关闭")
            return
        }
        try {
            // releaseCamera 和 closeCameraView 均需在主线程执行，
            // 避免与 surfaceDestroyed 回调（主线程）并发操作同一 camera 实例导致崩溃
            withActivity { activity ->
                activity.runOnUiThread {
                    CameraController.releaseCamera()
                    CameraViewManager.closeCameraView(activity)
                }
            }
        } catch (e: Exception) {
            console.log("关闭相机失败：${e.message}")
        }
    }

    fun takePicture(callback: TakePictureCallback) {
        if (!CameraController.isCameraAvailable()) {
            console.log("相机未启动，无法拍照")
            callback.onFail()
            return
        }
        CameraController.takePicture(callback)
    }

    /**
     * 创建拍照回调
     * 供 UTS 层调用，将 lambda 转换为 TakePictureCallback
     *
     * @param onSuccess 成功回调，接收图片路径
     * @param onFail    失败回调
     * @return TakePictureCallback 实例
     */
    fun createTakePictureCallback(
        onSuccess: ((String) -> Unit)?,
        onFail: (() -> Unit)?
    ): TakePictureCallback {
        return object : TakePictureCallback {
            override fun onSuccess(path: String) { onSuccess?.invoke(path) }
            override fun onFail() { onFail?.invoke() }
        }
    }

    /**
     * 开启点击对焦功能
     * 用户点击相机画面后，相机将对焦到点击位置，并显示对焦框
     */
    fun enableTapToFocus() {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法开启点击对焦")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread {
                CameraViewManager.enableTapToFocus(activity)
            }
        }
    }

    /**
     * 关闭点击对焦功能
     */
    fun disableTapToFocus() {
        withActivity { activity ->
            activity.runOnUiThread {
                CameraViewManager.disableTapToFocus()
            }
        }
    }

    fun switchCamera() {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法切换摄像头")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread {
                try {
                    val container = CameraViewManager.getCameraContainer()
                    if (container != null) {
                        CameraController.switchCamera(activity, container.width, container.height)
                    }
                } catch (e: Exception) {
                    console.log("切换摄像头失败：${e.message}")
                }
            }
        }
    }

    // 记录 onPause 前的扫码模式状态，onResume 时自动恢复
    private var wasScanModeActive = false

    /**
     * 生命周期回调：onPause
     * 暂停时停止预览和扫码
     */
    fun onPause() {
        try {
            // 记录扫码模式状态，以便 onResume 时恢复
            wasScanModeActive = CameraController.isScanModeActive()
            // 停止扫码模式
            if (wasScanModeActive) {
                CameraController.stopScanMode()
            }
            // 停止预览
            CameraController.releaseCamera()
            console.log("相机已暂停")
        } catch (e: Exception) {
            console.log("暂停相机失败：${e.message}")
        }
    }

    /**
     * 生命周期回调：onResume
     * 恢复时重新启动预览，并恢复暂停前的扫码模式
     */
    fun onResume() {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无需恢复")
            return
        }
        withActivity { activity ->
            activity.runOnUiThread {
                try {
                    val container = CameraViewManager.getCameraContainer() ?: return@runOnUiThread
                    // 提前捕获扫码状态，避免 lambda 闭包里读到被修改后的值
                    val pendingScan = wasScanModeActive
                    wasScanModeActive = false

                    if (container.width > 0 && container.height > 0) {
                        // 容器已完成 layout，直接恢复
                        resumeCameraPreview(activity, container.width, container.height, pendingScan)
                    } else {
                        // 低端机 onResume 可能早于 layout pass，等待 layout 完成后再恢复
                        // 不处理此分支则相机永不恢复
                        container.viewTreeObserver.addOnGlobalLayoutListener(
                            object : ViewTreeObserver.OnGlobalLayoutListener {
                                override fun onGlobalLayout() {
                                    container.viewTreeObserver.removeOnGlobalLayoutListener(this)
                                    // 必须回到主线程，因为 onGlobalLayout 本身就在主线程，但防御性加一层
                                    activity.runOnUiThread {
                                        if (container.width > 0 && container.height > 0) {
                                            resumeCameraPreview(activity, container.width, container.height, pendingScan)
                                        }
                                    }
                                }
                            }
                        )
                    }
                } catch (e: Exception) {
                    console.log("恢复相机失败：${e.message}")
                }
            }
        }
    }

    /**
     * 真正执行相机恢复逻辑（容器尺寸已确认 > 0）
     */
    private fun resumeCameraPreview(activity: Activity, containerW: Int, containerH: Int, pendingScan: Boolean) {
        try {
            val facing = CameraController.getCurrentCameraFacing()
            CameraController.startCameraPreview(
                activity,
                containerW,
                containerH,
                facing,
                // 相机 open 成功后再恢复扫码，避免 camera==null 时调用 startScanMode 失败
                object : CameraOpenCallback {
                    override fun onSuccess(cameraFacing: Int) {
                        if (pendingScan) CameraController.startScanMode()
                    }
                    override fun onFail(errCode: Int, errMsg: String) {
                        console.log("onResume 相机恢复失败($errCode)：$errMsg")
                    }
                }
            )
            console.log("相机已恢复")
        } catch (e: Exception) {
            console.log("恢复相机失败：${e.message}")
        }
    }

    /**
     * 生命周期回调：onDestroy
     * 完全销毁相机资源
     */
    fun onDestroy() {
        try {
            // 停止扫码模式
            if (CameraController.isScanModeActive()) {
                CameraController.stopScanMode()
            }
            // 释放相机
            CameraController.releaseCamera()
            console.log("相机资源已释放")
        } catch (e: Exception) {
            console.log("销毁相机失败：${e.message}")
        }
    }

    // ============ 扫码模式API ============

    /**
     * 启动扫码模式
     * 初始化预览回调，准备接收摄像头帧数据
     * 必须在相机显示后调用
     *
     * @return 是否启动成功
     */
    fun startScanMode(): Boolean {
        if (!CameraViewManager.isCameraShowing()) {
            console.log("相机未显示，无法启动扫码模式")
            return false
        }
        if (!CameraController.isCameraAvailable()) {
            console.log("相机未启动，无法启动扫码模式")
            return false
        }
        return CameraController.startScanMode()
    }

    /**
     * 停止扫码模式
     * 释放扫码相关资源
     *
     * @return 是否停止成功
     */
    fun stopScanMode(): Boolean {
        return CameraController.stopScanMode()
    }

    /**
     * 获取当前帧用于扫码（核心API）
     * 快速返回最新的一帧数据，转换为JPEG格式的Base64字符串
     * 该方法为同步调用，会快速返回，适合频繁调用（如每秒多次调用）
     *
     * @param quality JPEG压缩质量 (1-100)，建议80-90以平衡质量和性能，默认85
     * @return Base64编码的JPEG图片数据，如果获取失败返回null
     */
    fun getScanFrame(quality: Int = 85): String? {
        return CameraController.getScanFrame(quality)
    }

    /**
     * 检查扫码模式是否正在运行
     *
     * @return true表示扫码模式正在运行
     */
    fun isScanModeActive(): Boolean {
        return CameraController.isScanModeActive()
    }

    /**
     * 创建相机打开回调
     * 供 UTS 层调用，将 lambda 转换为 CameraOpenCallback
     *
     * @param onSuccess 成功回调，接收 cameraFacing: "front" | "back"
     * @param onFail 失败回调，接收 errCode: number, errMsg: string
     * @return CameraOpenCallback 实例
     */
    fun createCameraOpenCallback(
        onSuccess: ((String) -> Unit)?,
        onFail: ((Int, String) -> Unit)?
    ): CameraOpenCallback? {
        if (onSuccess == null && onFail == null) return null
        return object : CameraOpenCallback {
            override fun onSuccess(cameraFacing: Int) {
                val facing = if (cameraFacing == 1) "front" else "back"
                onSuccess?.invoke(facing)
            }
            override fun onFail(errCode: Int, errMsg: String) {
                onFail?.invoke(errCode, errMsg)
            }
        }
    }
}
