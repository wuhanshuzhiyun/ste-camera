import AVFoundation
import UIKit
import Foundation

/// 相机核心控制器（对应 Android CameraController.kt）
/// 基于 AVFoundation，单例模式
@objc public class CameraController: NSObject {

    // MARK: - 单例
    @objc public static let shared = CameraController()
    private override init() { super.init() }

    // MARK: - 相机会话
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - 容器尺寸（用于拍照裁剪）
    private var containerWidth: CGFloat = 0
    private var containerHeight: CGFloat = 0

    // MARK: - 当前摄像头（0=后置，1=前置）
    private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    // MARK: - 回调
    private var cameraOpenCallback: CameraOpenCallback?
    private var takePictureCallback: TakePictureCallback?

    // MARK: - 扫码模式
    private var isScanModeRunning: Bool = false
    private let frameLock = NSLock()
    private var latestFrameData: CVImageBuffer?
    private var latestFrameOrientation: CGImagePropertyOrientation = .up
    private let sessionQueue = DispatchQueue(label: "uts.ste.camera.session", qos: .userInitiated)
    private let frameCaptureQueue = DispatchQueue(label: "uts.ste.camera.frame", qos: .userInteractive)

    // MARK: - 基于 videoDataOutput 的拍照抓帧（photoOutput 黑图时的备选方案）
    private var isCapturingPhotoFrame: Bool = false
    private var photoFrameCaptureCallback: TakePictureCallback?
    /// 抓帧计数器：跳过前几帧，让自动曝光稳定后再抓取，避免图片暗淡
    private var photoFrameSkipCount: Int = 0
    private let photoFrameSkipThreshold: Int = 5

    /// 标记 session 是否正在 setup 中（防止重复 setup 产生竞态条件）
    private var isSettingUpSession: Bool = false

    // MARK: - 启动相机预览

    @objc public func startCameraPreview(
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        cameraFacing: String,
        callback: CameraOpenCallback?
    ) {
        NSLog("[CameraController] startCameraPreview called: containerWidth=\(containerWidth), containerHeight=\(containerHeight), cameraFacing=\(cameraFacing)")
        self.containerWidth = containerWidth
        self.containerHeight = containerHeight
        self.cameraOpenCallback = callback
        self.currentCameraPosition = (cameraFacing == "front") ? .front : .back

        // 如果会话已在运行，直接触发成功
        if let session = captureSession, session.isRunning {
            NSLog("[CameraController] session already running, triggering success")
            DispatchQueue.main.async {
                callback?.onSuccess(cameraFacing: cameraFacing)
            }
            return
        }

        // 关键修复：防止重复 setup。如果上一个 setupCaptureSession 还在执行中，
        // 直接丢弃新的 callback，避免两个 setup 竞争同一个摄像头设备。
        // 上一个 setup 完成后会通过自己的 callback 通知前端。
        if isSettingUpSession {
            NSLog("[CameraController] session setup already in progress, skip duplicate startCameraPreview")
            return
        }

        NSLog("[CameraController] starting session setup on sessionQueue")
        isSettingUpSession = true
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession(callback: callback)
        }
    }

    private func setupCaptureSession(callback: CameraOpenCallback?) {
        let session = AVCaptureSession()
        session.beginConfiguration()
        // 关键修复：默认只挂载 photoOutput，不挂载 videoOutput 时使用 .photo preset。
        // .photo preset 是 AVCapturePhotoOutput 的专用高质量 preset，
        // 在单独使用时能确保照片正常输出，避免黑图。
        // 只有在调用 startScanMode 动态添加 videoOutput 时，才降级为 .high。
        session.sessionPreset = .photo

        // 选择摄像头
        guard let device = cameraDevice(for: currentCameraPosition) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.isSettingUpSession = false
                callback?.onFail(errCode: NSNumber(value: 3), errMsg: "找不到可用摄像头")
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                self.videoDeviceInput = input
            } else {
                session.commitConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.isSettingUpSession = false
                    callback?.onFail(errCode: NSNumber(value: 3), errMsg: "无法添加摄像头输入")
                }
                return
            }
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.isSettingUpSession = false
                callback?.onFail(errCode: NSNumber(value: 2), errMsg: "摄像头被占用或打开失败：\(error.localizedDescription)")
            }
            return
        }

        // 添加照片输出
        let photo = AVCapturePhotoOutput()
        // 显式关闭 Live Photo，避免与 photoOutput 冲突
        photo.isLivePhotoCaptureEnabled = false
        if session.canAddOutput(photo) {
            session.addOutput(photo)
            self.photoOutput = photo
            // 注意：不要设置 photoOutput connection 的 videoOrientation，
            // 在某些 iOS 版本/设备上，设置该属性会导致拍出的照片为纯黑色。
            // 方向修正留给 UIImage 处理阶段完成。
            if let connection = photo.connection(with: .video) {
                connection.isEnabled = true
            }
        }

        session.commitConfiguration()
        self.captureSession = session

        // 启动会话
        session.startRunning()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSettingUpSession = false
            // 设置预览层朝向
            self.previewLayer?.connection?.videoOrientation = self.currentVideoOrientation()
            NSLog("[CameraController] setupCaptureSession completed: session.isRunning=\(session.isRunning), previewLayer=\(self.previewLayer != nil)")
            let facingStr = (self.currentCameraPosition == .front) ? "front" : "back"
            callback?.onSuccess(cameraFacing: facingStr)
        }
    }

    // MARK: - PreviewLayer

    @objc public func makePreviewLayer(containerSize: CGSize) -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = CGRect(origin: .zero, size: containerSize)
        layer.connection?.videoOrientation = currentVideoOrientation()
        self.previewLayer = layer
        return layer
    }

    /// 获取当前预览层（用于布局更新时同步 frame）
    @objc public func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }

    // MARK: - 停止预览

    @objc public func releaseCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.videoDeviceInput = nil
            self.photoOutput = nil
            self.videoOutput = nil
            self.previewLayer = nil
            self.isScanModeRunning = false
            self.isSettingUpSession = false
            // 清空帧引用，ARC 会自动释放持有的 buffer
            self.frameLock.lock()
            self.latestFrameData = nil
            self.frameLock.unlock()
        }
    }

    // MARK: - 拍照

    /// 拍照入口：由于 AVCapturePhotoOutput 在某些 iOS 设备/系统上
    /// 会拍出纯黑色照片（即使 preview 正常），这里采用 videoDataOutput
    /// 抓帧作为拍照实现。因为 preview layer 能正常显示，说明 video 帧
    /// 数据一定是正常的，这是更可靠的拍照方式。
    @objc public func takePicture(callback: TakePictureCallback) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { callback.onFail() }
                return
            }
            guard let session = self.captureSession, session.isRunning else {
                DispatchQueue.main.async { callback.onFail() }
                return
            }

            // 如果正在抓帧，忽略重复调用
            guard !self.isCapturingPhotoFrame else { return }
            self.isCapturingPhotoFrame = true
            self.photoFrameCaptureCallback = callback
            // 重置跳帧计数器，让自动曝光稳定后再抓取
            self.photoFrameSkipCount = 0

            // 动态添加 videoOutput 用于抓帧
            if self.videoOutput == nil {
                let videoOut = AVCaptureVideoDataOutput()
                videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOut.alwaysDiscardsLateVideoFrames = true
                videoOut.setSampleBufferDelegate(self, queue: self.frameCaptureQueue)
                session.beginConfiguration()
                // 当 session 当前是 .photo preset 时，无法直接添加 videoOutput，
                // 需要降级为 .high。这是 video 与 photo 共存需要的 preset。
                if session.sessionPreset == .photo {
                    session.sessionPreset = .high
                }
                if session.canAddOutput(videoOut) {
                    session.addOutput(videoOut)
                    self.videoOutput = videoOut
                }
                session.commitConfiguration()
            }

            // 超时保护：2 秒内没抓到帧则回调失败并清理
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, self.isCapturingPhotoFrame else { return }
                self.isCapturingPhotoFrame = false
                self.photoFrameCaptureCallback?.onFail()
                self.photoFrameCaptureCallback = nil
                self.removeVideoOutputForPhotoCapture()
            }
        }
    }

    /// 拍照完成后移除临时添加的 videoOutput，恢复 photoOutput 单独工作状态
    private func removeVideoOutputForPhotoCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            if let videoOut = self.videoOutput, !self.isScanModeRunning {
                session.beginConfiguration()
                session.removeOutput(videoOut)
                // 恢复 .photo preset 以获得最佳照片质量
                if session.sessionPreset == .high {
                    session.sessionPreset = .photo
                }
                session.commitConfiguration()
                videoOut.setSampleBufferDelegate(nil, queue: nil)
                self.videoOutput = nil
            }
            self.frameLock.lock()
            self.latestFrameData = nil
            self.frameLock.unlock()
        }
    }

    /// 处理抓帧拍照：将 sampleBuffer 转换为 UIImage 并保存
    private func processPhotoFrame(_ sampleBuffer: CMSampleBuffer) {
        frameLock.lock()
        guard isCapturingPhotoFrame else {
            frameLock.unlock()
            return
        }
        isCapturingPhotoFrame = false
        let cb = photoFrameCaptureCallback
        photoFrameCaptureCallback = nil
        frameLock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            DispatchQueue.main.async { cb?.onFail() }
            removeVideoOutputForPhotoCapture()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let cb = cb else {
                self?.removeVideoOutputForPhotoCapture()
                return
            }

            // 关键修复：videoDataOutput 抓取的视频帧是横向的（landscape），
            // 竖屏拍照时需要根据当前 videoOrientation 旋转图像。
            // CIImage 的方向需要根据摄像头位置和设备方向设置：
            // - 后置摄像头竖屏：视频帧是横向的，需要顺时针旋转 90°（.right）
            // - 前置摄像头竖屏：需要逆时针旋转 90°（.left），再镜像翻转
            let orientation: CGImagePropertyOrientation
            if self.currentCameraPosition == .front {
                orientation = .left  // 前置摄像头
            } else {
                orientation = .right // 后置摄像头竖屏
            }

            let ciImage = CIImage(cvImageBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
            let orientedCIImage = ciImage.oriented(orientation)
            let context = CIContext()
            guard let cgImage = context.createCGImage(orientedCIImage, from: orientedCIImage.extent) else {
                cb.onFail()
                self.removeVideoOutputForPhotoCapture()
                return
            }

            var image = UIImage(cgImage: cgImage)

            // 方向修正（统一为 .up）
            image = self.fixImageOrientation(image)

            // 前置摄像头镜像翻转
            if self.currentCameraPosition == .front {
                image = self.flipImageHorizontal(image)
            }

            // 按容器比例裁剪
            if self.containerWidth > 0 && self.containerHeight > 0 {
                let targetRatio = self.containerWidth / self.containerHeight
                image = self.cropImageToRatio(image, targetRatio: targetRatio)
            }

            // 叠加水印
            let watermarks = CameraViewManager.shared.getWatermarkConfigs()
            if !watermarks.isEmpty {
                image = ImageProcessor.shared.drawWatermarks(on: image, watermarks: watermarks)
            }

            // 保存到缓存目录（用于保存相册等功能）
            guard let path = ImageProcessor.shared.saveImageToCache(image) else {
                cb.onFail()
                self.removeVideoOutputForPhotoCapture()
                return
            }

            // 关键修复：同时返回 base64 dataURL，用于 <image> 组件预览。
            // uni-app x 的 <image> 组件在 iOS 上无法渲染 file:// 绝对路径，
            // 但 uni.previewImage 能显示（内部做了路径转换）。
            // 用 dataURL 作为 src，<image> 一定能渲染。
            // 格式：dataURL|||filePath（用 ||| 分隔，JS 层解析）
            // 压缩质量 0.95，保证图片质量不暗淡
            if let jpegData = image.jpegData(compressionQuality: 0.95) {
                let base64 = jpegData.base64EncodedString()
                let dataUrl = "data:image/jpeg;base64," + base64
                let combined = dataUrl + "|||" + path
                NSLog("[CameraController] processPhotoFrame: dataUrl length=\(dataUrl.count), path=\(path)")
                cb.onSuccess(path: combined)
            } else {
                cb.onSuccess(path: path)
            }
            self.removeVideoOutputForPhotoCapture()
        }
    }

    // MARK: - 切换摄像头

    @objc public func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            let newPosition: AVCaptureDevice.Position = (self.currentCameraPosition == .back) ? .front : .back

            guard let newDevice = self.cameraDevice(for: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            session.beginConfiguration()
            if let old = self.videoDeviceInput {
                session.removeInput(old)
            }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.videoDeviceInput = newInput
                self.currentCameraPosition = newPosition
            }
            session.commitConfiguration()

            DispatchQueue.main.async {
                self.previewLayer?.connection?.videoOrientation = self.currentVideoOrientation()
            }
        }
    }

    // MARK: - 点击对焦

    @objc public func focusAt(point: CGPoint, in view: UIView) {
        guard let device = videoDeviceInput?.device else { return }
        guard let layer = previewLayer else { return }

        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            // 对焦失败不影响相机正常使用
        }
    }

    // MARK: - 恢复预览

    @objc public func resumePreview() {
        sessionQueue.async { [weak self] in
            if self?.captureSession?.isRunning == false {
                self?.captureSession?.startRunning()
            }
        }
    }

    // MARK: - 状态查询

    @objc public func isCameraAvailable() -> Bool {
        return captureSession?.isRunning == true
    }

    /// 将 UIImage 的方向修正为正立（.up）
    /// 注意：需要放在主类中，供 photoOutput delegate 和 videoDataOutput 拍照共同使用
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    @objc public func getCurrentCameraFacing() -> String {
        return (currentCameraPosition == .front) ? "front" : "back"
    }

    // MARK: - 扫码模式

    @objc public func startScanMode() -> Bool {
        if isScanModeRunning { return true }
        guard isCameraAvailable(), let session = captureSession else { return false }

        // 动态添加 videoOutput：扫码模式需要时再挂载，避免与 photoOutput 冲突导致拍照黑图
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.videoOutput == nil {
                let videoOut = AVCaptureVideoDataOutput()
                videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOut.alwaysDiscardsLateVideoFrames = true
                videoOut.setSampleBufferDelegate(self, queue: self.frameCaptureQueue)
                session.beginConfiguration()
                if session.canAddOutput(videoOut) {
                    session.addOutput(videoOut)
                    self.videoOutput = videoOut
                }
                session.commitConfiguration()
            }
        }

        isScanModeRunning = true
        return true
    }

    @objc public func stopScanMode() -> Bool {
        // 幂等处理：已经停止时直接返回 true，避免重复调用被当作错误
        if !isScanModeRunning {
            // 兜底清理：确保 videoOutput 被移除（防止状态不一致）
            sessionQueue.async { [weak self] in
                guard let self = self, let session = self.captureSession else { return }
                if let videoOut = self.videoOutput {
                    session.beginConfiguration()
                    session.removeOutput(videoOut)
                    session.commitConfiguration()
                    videoOut.setSampleBufferDelegate(nil, queue: nil)
                    self.videoOutput = nil
                }
            }
            return true
        }
        isScanModeRunning = false

        // 停止扫码时移除 videoOutput，释放资源并避免影响拍照
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            if let videoOut = self.videoOutput {
                session.beginConfiguration()
                session.removeOutput(videoOut)
                session.commitConfiguration()
                videoOut.setSampleBufferDelegate(nil, queue: nil)
                self.videoOutput = nil
            }
            // 清空当前帧引用，ARC 会自动释放持有的 buffer
            self.frameLock.lock()
            self.latestFrameData = nil
            self.frameLock.unlock()
        }
        return true
    }

    @objc public func isScanModeActive() -> Bool {
        return isScanModeRunning
    }

    /// 获取最新帧（同步），返回 JPEG Base64 字符串
    @objc public func getScanFrame(quality: Int) -> String? {
        guard isScanModeRunning else { return nil }

        // 取出当前帧的 retained 引用（captureOutput 中已 retain）
        // 注意：取出后只读使用，不要在这里 release，否则下一帧再读取会野指针。
        // 释放时机由 captureOutput 替换新帧时配对 release。
        var pixelBuffer: CVImageBuffer?
        frameLock.lock()
        pixelBuffer = latestFrameData
        frameLock.unlock()

        guard let buffer = pixelBuffer else { return nil }

        // 将 CVImageBuffer 转为 UIImage
        let ciImage = CIImage(cvImageBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        var uiImage = UIImage(cgImage: cgImage)

        // 方向修正：根据当前设备方向旋转
        let orientation = currentDeviceOrientation()
        uiImage = rotateImage(uiImage, orientation: orientation)

        // 前置摄像头镜像翻转
        if currentCameraPosition == .front {
            uiImage = flipImageHorizontal(uiImage)
        }

        // 按容器比例裁剪
        if containerWidth > 0 && containerHeight > 0 {
            let targetRatio = containerWidth / containerHeight
            uiImage = cropImageToRatio(uiImage, targetRatio: targetRatio)
        }

        // 编码为 JPEG Base64
        let jpegQuality = CGFloat(max(1, min(100, quality))) / 100.0
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else { return nil }
        return jpegData.base64EncodedString()
    }

    // MARK: - 私有工具方法

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if #available(iOS 10.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: position
            )
            return discoverySession.devices.first
        } else {
            return AVCaptureDevice.devices(for: .video).first { $0.position == position }
        }
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:   return .landscapeRight
        case .landscapeRight:  return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private func currentDeviceOrientation() -> UIImage.Orientation {
        if currentCameraPosition == .front {
            switch UIDevice.current.orientation {
            case .landscapeLeft:  return .up
            case .landscapeRight: return .down
            default:              return .leftMirrored
            }
        } else {
            switch UIDevice.current.orientation {
            case .landscapeLeft:  return .up
            case .landscapeRight: return .down
            case .portraitUpsideDown: return .left
            default:              return .right
            }
        }
    }

    func rotateImage(_ image: UIImage, orientation: UIImage.Orientation) -> UIImage {
        if orientation == .up { return image }
        guard let cgImage = image.cgImage else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: orientation)
    }

    func flipImageHorizontal(_ image: UIImage) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        context.translateBy(x: image.size.width, y: 0)
        context.scaleBy(x: -1, y: 1)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let flipped = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return flipped
    }

    func cropImageToRatio(_ image: UIImage, targetRatio: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let imageRatio = w / h

        let cropW: CGFloat
        let cropH: CGFloat
        if imageRatio > targetRatio {
            cropH = h
            cropW = h * targetRatio
        } else {
            cropW = w
            cropH = w / targetRatio
        }

        let x = (w - cropW) / 2
        let y = (h - cropH) / 2
        let cropRect = CGRect(x: x, y: y, width: cropW, height: cropH)

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {

    // 使用 AVCapturePhotoCaptureDelegate 协议方法，不要加 @objc，
    // Swift 协议方法由 Swift 编译器正确派发。
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // 本回调由 AVFoundation 在内部队列触发（非主线程）。
        // 下方的图片处理流程涉及大量 UIKit 操作：
        //   - flipImageHorizontal / fixImageOrientation 使用 UIGraphicsBeginImageContextWithOptions
        //   - ImageProcessor.drawWatermarks 内部访问 UIScreen.main（必须主线程）
        //   - getWatermarkConfigs() 跨线程读取 watermarkConfigs 非原子属性
        // 因此整个图片处理流程必须 dispatch 到主线程执行，否则会引发
        // "Modifying properties of a view's layer off the main thread is not allowed" 崩溃。
        let cb = takePictureCallback
        self.takePictureCallback = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let cb = cb else { return }

            if error != nil {
                NSLog("[CameraController] photoOutput error: \(error!.localizedDescription)")
                cb.onFail()
                return
            }

            // 调试日志：检查两种数据源
            let fileData = photo.fileDataRepresentation()
            let cgImageRef = photo.cgImageRepresentation()
            NSLog("[CameraController] photoOutput: fileData=\(fileData?.count ?? 0) bytes, cgImageRef=\(cgImageRef != nil)")

            // 关键调试：先直接保存原始 fileData，不做任何图像处理，
            // 用于判断黑图问题是来自 AVFoundation 采集还是后续图像处理。
            // 如果原始 fileData 保存后是正常的，说明后续处理有问题；
            // 如果原始 fileData 也是黑色的，说明 AVFoundation 采集有问题。
            if let rawData = fileData {
                let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                if let dir = cachesDir {
                    let rawFileName = "camera_raw_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                    let rawURL = dir.appendingPathComponent(rawFileName)
                    do {
                        try rawData.write(to: rawURL)
                        NSLog("[CameraController] photoOutput: saved raw fileData to \(rawURL.path)")
                        // 临时：直接返回原始数据路径，跳过所有图像处理
                        // 用于排查黑图根因
                        cb.onSuccess(path: rawURL.path)
                        return
                    } catch {
                        NSLog("[CameraController] photoOutput: save raw failed \(error.localizedDescription)")
                    }
                }
            }

            // 关键修复：优先使用 cgImageRepresentation() 获取图像
            // fileDataRepresentation() 在某些 iOS 版本/设备上可能返回黑色 JPEG
            var image: UIImage?

            // 方式1：从 cgImageRepresentation 获取
            if let cgImage = cgImageRef {
                image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                NSLog("[CameraController] photoOutput: created UIImage from cgImageRepresentation, size=\(image!.size)")
            }

            // 方式2：如果 cgImageRepresentation 失败，回退到 fileDataRepresentation
            if image == nil, let data = fileData {
                image = UIImage(data: data)
                NSLog("[CameraController] photoOutput: created UIImage from fileDataRepresentation, size=\(image!.size)")
            }

            guard var finalImage = image else {
                NSLog("[CameraController] photoOutput: failed to create UIImage from both sources")
                cb.onFail()
                return
            }

            // 前置摄像头：镜像翻转
            if self.currentCameraPosition == .front {
                finalImage = self.flipImageHorizontal(finalImage)
            }

            // 旋转修正（使照片正立）
            finalImage = self.fixImageOrientation(finalImage)

            // 按容器比例裁剪
            if self.containerWidth > 0 && self.containerHeight > 0 {
                let targetRatio = self.containerWidth / self.containerHeight
                finalImage = self.cropImageToRatio(finalImage, targetRatio: targetRatio)
            }

            // 叠加水印（drawWatermarks 内部访问 UIScreen.main，必须主线程）
            let watermarks = CameraViewManager.shared.getWatermarkConfigs()
            if !watermarks.isEmpty {
                finalImage = ImageProcessor.shared.drawWatermarks(on: finalImage, watermarks: watermarks)
            }

            // 保存到缓存目录
            guard let path = ImageProcessor.shared.saveImageToCache(finalImage) else {
                cb.onFail()
                return
            }

            NSLog("[CameraController] photoOutput: saved image to \(path)")
            cb.onSuccess(path: path)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate（扫码帧捕获）

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 如果正在拍照抓帧，优先处理拍照
        if isCapturingPhotoFrame {
            // 跳过前几帧，让自动曝光稳定后再抓取，避免图片暗淡
            frameLock.lock()
            if photoFrameSkipCount < photoFrameSkipThreshold {
                photoFrameSkipCount += 1
                frameLock.unlock()
                return
            }
            frameLock.unlock()
            processPhotoFrame(sampleBuffer)
            return
        }

        guard isScanModeRunning else { return }
        // 注意：在 Swift / ARC 环境下，CVImageBuffer 由 ARC 自动管理引用计数，
        // 不能手动调用 CVBufferRetain / CVBufferRelease（会编译报错 unavailable）。
        // 直接赋值给 latestFrameData，ARC 会自动 +1 retain；
        // 旧值被覆盖时 ARC 会自动 release。
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        latestFrameData = pixelBuffer
        frameLock.unlock()
    }
}
