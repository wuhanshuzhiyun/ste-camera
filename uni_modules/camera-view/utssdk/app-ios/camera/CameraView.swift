import UIKit
import AVFoundation
import Foundation

/// 相机页面统一入口（对标 Android CameraView.kt）
/// 所有对外 API 均通过此类调用，内部委托给 CameraController / CameraViewManager
@objc public class CameraView: NSObject {

    // MARK: - 便捷单例（内部使用）
    @objc public static let shared = CameraView()
    private override init() { super.init() }

    /// 权限轮询定时器：showCamera 在权限未定时会启动定时器轮询权限状态。
    /// 如果用户多次点击「打开相机」，会创建多个定时器，导致权限通过后
    /// 多次调用 startCameraUI，产生重复的相机会话 setup，引发竞态条件。
    /// 这里保存定时器引用，每次启动新定时器前先 invalidate 旧的。
    private var permissionTimer: Timer?

    /// 标记是否正在请求权限中。防止用户在权限弹框期间多次点击「打开相机」
    /// 导致多次 requestAccess 调用和多个回调链。
    /// 第一次调用会发起 requestAccess，后续调用直接返回（callback 由第一次接管）。
    private var isRequestingPermission: Bool = false

    // MARK: - 私有辅助：在主线程执行，并检查 ViewController 可用性

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    // MARK: - showCamera（无具名参数版，供 UTS 层调用）

    /// UTS 层专用：参数全部位置传递，避免 UTS 编译器对具名参数的限制
    /// 注意：CGFloat? 不能用 @objc 标记，因此使用 NSNumber? 替代，内部转换为 CGFloat
    @objc public func showCamera(
        _ viewController: UIViewController?,
        _ width: NSNumber?,
        _ height: NSNumber?,
        _ top: NSNumber?,
        _ left: NSNumber?,
        _ cameraFacing: String,
        _ views: [[String: Any]]?,
        _ scanBar: [String: Any]?,
        _ callback: CameraOpenCallback?
    ) {
        showCamera(in: viewController, 
                   width: width.map { CGFloat($0.doubleValue) }, 
                   height: height.map { CGFloat($0.doubleValue) }, 
                   top: top.map { CGFloat($0.doubleValue) }, 
                   left: left.map { CGFloat($0.doubleValue) },
                   cameraFacing: cameraFacing, 
                   views: views, 
                   scanBar: scanBar, 
                   callback: callback)
    }

    // MARK: - showCamera

    /// 显示相机页面
    /// - Parameters:
    ///   - viewController: 当前 ViewController（iOS 需要）
    ///   - width:          相机容器宽度（pt），nil 表示全屏宽
    ///   - height:         相机容器高度（pt），nil 表示全屏高
    ///   - top:            距屏幕顶部偏移（pt），nil 表示 0
    ///   - left:           距屏幕左侧偏移（pt），nil 表示 0
    ///   - cameraFacing:   "front" / "back"，默认 "back"
    ///   - views:          叠加视图配置数组
    ///   - scanBar:        扫描条配置
    ///   - callback:       相机打开回调
    public func showCamera(
        in viewController: UIViewController?,
        width: CGFloat?,
        height: CGFloat?,
        top: CGFloat?,
        left: CGFloat?,
        cameraFacing: String,
        views: [[String: Any]]?,
        scanBar: [String: Any]?,
        callback: CameraOpenCallback?
    ) {
        // 关键修复：UTS 层可能在后台线程调用此方法，
        // 而 AVCaptureDevice.requestAccess 的回调需要切回主线程，
        // UI 创建和 session 启动也必须在主线程执行。
        if !Thread.isMainThread {
            NSLog("[CameraView] showCamera called on background thread, switching to main")
            DispatchQueue.main.async { [weak self] in
                self?.showCamera(
                    in: viewController, width: width, height: height,
                    top: top, left: left, cameraFacing: cameraFacing,
                    views: views, scanBar: scanBar, callback: callback
                )
            }
            return
        }
        NSLog("[CameraView] showCamera called on main thread")

        // 相机已在显示中，直接回调成功
        if CameraViewManager.shared.isCameraVisible() {
            callback?.onSuccess(cameraFacing: cameraFacing)
            return
        }

        // 兜底清理：如果之前打开失败导致 session 或视图残留，先彻底释放
        // 注意：只在权限尚未通过、相机视图尚未创建时才清理。
        // 如果 cameraVisible 但用户再次调用（例如前端状态不同步），
        // 上面的 isCameraVisible 检查已经 return 了，不会走到这里。
        CameraController.shared.releaseCamera()
        CameraViewManager.shared.forceCloseCameraView()

        // 权限检查在 Swift 层处理
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            // 已授权，直接创建相机
            self.startCameraUI(viewController, width: width, height: height,
                               top: top, left: left, cameraFacing: cameraFacing,
                               views: views, scanBar: scanBar, callback: callback)
        } else if status == .notDetermined {
            // 首次请求权限：弹框后等用户授权，再创建相机
            NSLog("[CameraView] requesting camera permission (notDetermined)")

            // 关键修复：如果已经在请求权限中，直接返回。
            // 第一次调用的 requestAccess 回调会负责创建相机 UI。
            // 后续重复调用不做任何处理，避免多个 requestAccess 竞争。
            if isRequestingPermission {
                NSLog("[CameraView] permission request already in progress, skip")
                return
            }
            isRequestingPermission = true

            // 关键修复：直接使用 requestAccess 的回调，而不是 Timer 轮询。
            // Timer.scheduledTimer 在系统权限弹框期间可能不触发（run loop
            // 被系统弹框阻塞），导致授权后相机迟迟不启动，用户需要再次点击。
            // requestAccess 的回调在用户点击授权/拒绝后由系统触发，更可靠。
            // 回调在后台线程触发，必须切回主线程才能创建 UI 和启动 session。
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                // 切回主线程
                DispatchQueue.main.async {
                    self.isRequestingPermission = false

                    if granted {
                        NSLog("[CameraView] permission granted via requestAccess callback")
                        // 首次授权后 iOS 系统需要短暂时间初始化相机硬件
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.startCameraUI(viewController, width: width, height: height,
                                               top: top, left: left, cameraFacing: cameraFacing,
                                               views: views, scanBar: scanBar, callback: callback)
                        }
                    } else {
                        NSLog("[CameraView] permission denied via requestAccess callback")
                        callback?.onFail(errCode: NSNumber(value: 1), errMsg: "权限被拒绝")
                    }
                }
            }
        } else {
            // .denied 或 .restricted
            callback?.onFail(errCode: NSNumber(value: 1), errMsg: "权限被拒绝")
        }
    }

    /// 创建相机 UI 并启动预览（权限已通过后调用）
    private func startCameraUI(
        _ viewController: UIViewController?,
        width: CGFloat?,
        height: CGFloat?,
        top: CGFloat?,
        left: CGFloat?,
        cameraFacing: String,
        views: [[String: Any]]?,
        scanBar: [String: Any]?,
        callback: CameraOpenCallback?
    ) {
        startCameraUI(viewController, width: width, height: height,
                      top: top, left: left, cameraFacing: cameraFacing,
                      views: views, scanBar: scanBar, callback: callback,
                      retryCount: 0)
    }

    /// startCameraUI 的内部实现，支持重试
    /// 权限弹框刚 dismiss 时，keyWindow/topViewController 可能暂时为 nil，
    /// 此时 showCameraView 会返回 false。通过重试机制等待 window 就绪后再创建。
    private func startCameraUI(
        _ viewController: UIViewController?,
        width: CGFloat?,
        height: CGFloat?,
        top: CGFloat?,
        left: CGFloat?,
        cameraFacing: String,
        views: [[String: Any]]?,
        scanBar: [String: Any]?,
        callback: CameraOpenCallback?,
        retryCount: Int
    ) {
        onMain { [weak self] in
            guard let self = self else { return }

            // 如果相机已显示（其他调用路径已创建），直接回调成功
            if CameraViewManager.shared.isCameraVisible() {
                NSLog("[CameraView] startCameraUI: camera already visible, triggering success")
                callback?.onSuccess(cameraFacing: cameraFacing)
                return
            }

            let screenBounds = UIScreen.main.bounds
            let finalWidth  = width  ?? screenBounds.width
            let finalHeight = height ?? screenBounds.height

            // 显示相机容器（创建 UIView 并插入 Window）
            let viewCreated = CameraViewManager.shared.showCameraView(
                in: viewController,
                width: NSNumber(value: finalWidth),
                height: NSNumber(value: finalHeight),
                top: top.map { NSNumber(value: $0) },
                left: left.map { NSNumber(value: $0) },
                views: views,
                scanBar: scanBar
            )
            guard viewCreated else {
                // showCameraView 返回 false 有两种情况：
                // 1. isCameraShowing 已为 true（重复调用）→ 上面的 isCameraVisible 检查已处理
                // 2. topViewController 为 nil（window 尚未就绪）→ 重试
                if retryCount < 10 {
                    NSLog("[CameraView] startCameraUI: showCameraView returned false (retry \(retryCount + 1)/10), retrying in 0.3s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.startCameraUI(viewController, width: width, height: height,
                                            top: top, left: left, cameraFacing: cameraFacing,
                                            views: views, scanBar: scanBar, callback: callback,
                                            retryCount: retryCount + 1)
                    }
                } else {
                    NSLog("[CameraView] startCameraUI: showCameraView failed after 10 retries, giving up")
                    callback?.onFail(errCode: NSNumber(value: 4), errMsg: "无法创建相机视图（窗口未就绪）")
                }
                return
            }

            // 包装回调：在原始 callback 之前先 attachPreviewLayer
            final class AttachingCallback: NSObject, CameraOpenCallback {
                let inner: CameraOpenCallback?
                init(_ inner: CameraOpenCallback?) { self.inner = inner }
                func onSuccess(cameraFacing: String) {
                    // 此时 session 已经 running，必须先成功插入预览层，
                    // 再回调前端成功。如果 preview layer 没加上，前端会以为
                    // 相机已打开但实际看不到画面。
                    let innerCb = self.inner
                    if CameraViewManager.shared.attachPreviewLayer(successCallback: {
                        // 预览层成功插入后，回调前端 success
                        innerCb?.onSuccess(cameraFacing: cameraFacing)
                    }) {
                        // attachPreviewLayer 立即成功，successCallback 已在内部同步调用
                    } else {
                        // attachPreviewLayer 返回 false，内部会自动延迟重试，
                        // 重试成功后会调用 successCallback。此处不做任何清理。
                        NSLog("[CameraView] attachPreviewLayer returned false, will retry internally")
                    }
                }
                func onFail(errCode: NSNumber, errMsg: String) {
                    // 相机会话启动失败：关闭已创建的 UI 视图，重置 isCameraShowing
                    CameraController.shared.releaseCamera()
                    CameraViewManager.shared.closeCameraView()
                    inner?.onFail(errCode: errCode, errMsg: errMsg)
                }
            }
            let wrappedCallback = AttachingCallback(callback)

            // 启动相机预览
            CameraController.shared.startCameraPreview(
                containerWidth: finalWidth,
                containerHeight: finalHeight,
                cameraFacing: cameraFacing,
                callback: wrappedCallback
            )
        }
    }

    // MARK: - closeCamera

    @objc public func closeCamera() {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        // 清理权限请求状态
        isRequestingPermission = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        CameraController.shared.releaseCamera()
        onMain {
            CameraViewManager.shared.closeCameraView()
        }
    }

    // MARK: - takePicture

    @objc public func takePicture(callback: TakePictureCallback) {
        // UTS 层调用本方法时默认在子线程执行，
        // 而 isCameraAvailable 判断、callback.onFail 回调（触发 JSContext）、
        // 以及 AVFoundation 的 capturePhoto 调用都建议在主线程进行，
        // 否则极易在拍照失败或权限异常时引发 JSContext 跨线程访问崩溃。
        // 因此这里统一 dispatch 到主线程执行，保证线程安全。
        onMain {
            let visible = CameraViewManager.shared.isCameraVisible()
            let available = CameraController.shared.isCameraAvailable()
            NSLog("[CameraView] takePicture: isCameraVisible=\(visible), isCameraAvailable=\(available)")
            guard visible else {
                NSLog("[CameraView] takePicture failed: camera view is not visible")
                callback.onFail()
                return
            }
            guard available else {
                NSLog("[CameraView] takePicture failed: camera session is not available")
                callback.onFail()
                return
            }
            CameraController.shared.takePicture(callback: callback)
        }
    }

    /// UTS 层专用（位置参数）
    @objc public func takePicture(_ callback: TakePictureCallback) {
        takePicture(callback: callback)
    }

    /// 工厂方法：从两个闭包构造 TakePictureCallback（供 UTS 层调用）
    @objc public func createTakePictureCallback(
        onSuccess: ((String) -> Void)?,
        onFail: (() -> Void)?
    ) -> TakePictureCallback {
        return TakePictureCallbackImpl(onSuccess: onSuccess, onFail: onFail)
    }

    /// UTS 层专用（位置参数）
    @objc public func createTakePictureCallback(
        _ onSuccess: ((String) -> Void)?,
        _ onFail: (() -> Void)?
    ) -> TakePictureCallback {
        return createTakePictureCallback(onSuccess: onSuccess, onFail: onFail)
    }

    // MARK: - 工厂方法：CameraOpenCallback

    /// UTS 层调用时，number 类型编译为 NSNumber，因此这里使用 NSNumber 类型
    /// 注意：不使用 @objc 标记，因为 Swift 闭包类型在 Objective-C 中无法表示
    /// UTS 层直接通过 Swift 调用，不需要 Objective-C 桥接
    public func createCameraOpenCallback(
        onSuccess: ((String) -> Void)?,
        onFail: ((NSNumber, String) -> Void)?
    ) -> CameraOpenCallback? {
        guard onSuccess != nil || onFail != nil else { return nil }
        return CameraOpenCallbackImpl(onSuccess: onSuccess, onFail: onFail)
    }

    /// UTS 层专用（位置参数）
    public func createCameraOpenCallback(
        _ onSuccess: ((String) -> Void)?,
        _ onFail: ((NSNumber, String) -> Void)?
    ) -> CameraOpenCallback? {
        return createCameraOpenCallback(onSuccess: onSuccess, onFail: onFail)
    }

    // MARK: - switchCamera

    @objc public func switchCamera() {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        CameraController.shared.switchCamera()
    }

    // MARK: - 点击对焦

    @objc public func enableTapToFocus() {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.enableTapToFocus()
        }
    }

    @objc public func disableTapToFocus() {
        onMain {
            CameraViewManager.shared.disableTapToFocus()
        }
    }

    // MARK: - 视图管理

    @objc public func updateViews(_ views: [[String: Any]]?) {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.updateViews(views)
        }
    }

    @objc public func addView(_ viewConfig: [String: Any]) {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.addView(viewConfig)
        }
    }

    @objc public func updateView(uid: String, viewConfig: [String: Any]) {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.updateView(uid: uid, viewConfig: viewConfig)
        }
    }

    /// UTS 层专用（无具名参数）
    @objc public func updateView(_ uid: String, _ viewConfig: [String: Any]) {
        updateView(uid: uid, viewConfig: viewConfig)
    }

    @objc public func removeView(uid: String) {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.removeView(uid: uid)
        }
    }

    /// UTS 层专用（无具名参数）
    @objc public func removeView(_ uid: String) {
        removeView(uid: uid)
    }

    @objc public func clearViews() {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.clearViews()
        }
    }

    // MARK: - 扫描条

    @objc public func showScanBar(_ options: [String: Any]) {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        onMain {
            CameraViewManager.shared.showScanBar(options)
        }
    }

    @objc public func hideScanBar() {
        onMain {
            CameraViewManager.shared.hideScanBar()
        }
    }

    // MARK: - 扫码模式

    @objc public func startScanMode() -> Bool {
        guard CameraViewManager.shared.isCameraVisible() else { return false }
        guard CameraController.shared.isCameraAvailable() else { return false }
        return CameraController.shared.startScanMode()
    }

    @objc public func stopScanMode() -> Bool {
        return CameraController.shared.stopScanMode()
    }

    @objc public func isScanModeActive() -> Bool {
        return CameraController.shared.isScanModeActive()
    }

    @objc public func getScanFrame(quality: Int) -> String? {
        return CameraController.shared.getScanFrame(quality: quality)
    }

    /// UTS 层专用（位置参数）
    @objc public func getScanFrame(_ quality: Int) -> String? {
        return getScanFrame(quality: quality)
    }

    // MARK: - 权限检查

    /// 同步检查相机权限是否已授权（true = 已授权，false = 已拒绝/受限）
    /// 若为 notDetermined 返回 false，需调用 requestPermission 异步申请
    @objc public func isPermissionGranted() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// 异步申请相机权限，completion 在主线程回调
    /// - Parameter completion: true = 用户授权，false = 拒绝
    @objc public func requestPermission(completion: @escaping (Bool) -> Void) {
        // 诊断：确认 Info.plist 是否包含相机权限描述。
        // 若为 nil，则下方 requestAccess 触发时 iOS 会直接 SIGKILL（无弹框）。
        // 这是判断「manifest.plistcmds / 插件 infoPlist 是否真正注入」的最快证据。
        let cameraDesc = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        print("[CameraView] Info.plist NSCameraUsageDescription = \(cameraDesc ?? "nil => 缺失! 权限弹框不会出现且 App 会被系统杀掉")")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        default:
            // 关键修复：requestAccess 的回调在后台线程触发，
            // 如果不切回主线程，后续 showCamera 调用会在后台线程执行，
            // 导致 UI 创建和 session 启动时机不对，首次授权后相机无法正常显示。
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    // 首次授权后，iOS 系统需要短暂时间初始化相机硬件服务。
                    // 如果立即启动 captureSession，可能因硬件未就绪而失败。
                    // 延迟 0.3 秒等待系统就绪后再回调。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        completion(granted)
                    }
                }
            }
        }
    }

    /// UTS 层专用（位置参数）
    @objc public func requestPermission(_ completion: @escaping (Bool) -> Void) {
        requestPermission(completion: completion)
    }

    // MARK: - 生命周期

    @objc public func onPause() {
        if CameraController.shared.isScanModeActive() {
            _ = CameraController.shared.stopScanMode()
        }
        CameraController.shared.releaseCamera()
    }

    @objc public func onResume(in viewController: UIViewController?) {
        guard CameraViewManager.shared.isCameraVisible() else { return }
        guard let container = CameraViewManager.shared.getCameraContainer() else { return }
        let size = container.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let facing = CameraController.shared.getCurrentCameraFacing()
        CameraController.shared.startCameraPreview(
            containerWidth: size.width,
            containerHeight: size.height,
            cameraFacing: facing,
            callback: nil
        )
    }

    @objc public func onDestroy() {
        // 清理权限请求状态和定时器
        isRequestingPermission = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        if CameraController.shared.isScanModeActive() {
            _ = CameraController.shared.stopScanMode()
        }
        CameraController.shared.releaseCamera()
    }
}

// MARK: - 回调实现类（内部，仅供工厂方法使用）

private class TakePictureCallbackImpl: NSObject, TakePictureCallback {
    private let successBlock: ((String) -> Void)?
    private let failBlock: (() -> Void)?

    init(onSuccess: ((String) -> Void)?, onFail: (() -> Void)?) {
        self.successBlock = onSuccess
        self.failBlock    = onFail
    }

    func onSuccess(path: String) { successBlock?(path) }
    func onFail() { failBlock?() }
}

private class CameraOpenCallbackImpl: NSObject, CameraOpenCallback {
    private let successBlock: ((String) -> Void)?
    private let failBlock: ((NSNumber, String) -> Void)?

    init(onSuccess: ((String) -> Void)?, onFail: ((NSNumber, String) -> Void)?) {
        self.successBlock = onSuccess
        self.failBlock    = onFail
    }

    func onSuccess(cameraFacing: String) { successBlock?(cameraFacing) }
    func onFail(errCode: NSNumber, errMsg: String) { failBlock?(errCode, errMsg) }
}
