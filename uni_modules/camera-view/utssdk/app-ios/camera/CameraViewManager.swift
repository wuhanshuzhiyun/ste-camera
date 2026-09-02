import UIKit
import AVFoundation
import Foundation

/// 相机视图管理器（对标 Android CameraViewManager.kt）
@objc public class CameraViewManager: NSObject {

    // MARK: - 单例
    @objc public static let shared = CameraViewManager()
    private override init() { super.init() }

    // MARK: - 相机容器
    private(set) var cameraContainer: UIView?
    private var cameraViewController: CameraViewController?
    private var isCameraShowing: Bool = false

    // MARK: - 水印配置
    private var watermarkConfigs: [[String: Any]] = []
    private var preloadedImages: [String: UIImage] = [:]

    // MARK: - 扫描条
    private var scanBarView: UIImageView?
    private var scanBarAnimator: UIViewPropertyAnimator?
    private var scanBarDisplayLink: CADisplayLink?

    // MARK: - 点击对焦
    private var tapToFocusEnabled: Bool = false
    private var focusRingView: UIView?

    // MARK: - 常量
    private let defaultFontSize: CGFloat = 14
    private let defaultFontColor: UIColor = .white
    private let defaultImgSize: CGFloat = 100

    // MARK: - 显示相机视图

    @objc public func showCameraView(
        in viewController: UIViewController?,
        width: NSNumber?,
        height: NSNumber?,
        top: NSNumber?,
        left: NSNumber?,
        views: [[String: Any]]?,
        scanBar: [String: Any]?
    ) -> Bool {
        guard !isCameraShowing else {
            NSLog("[CameraViewManager] showCameraView: isCameraShowing already true, skip")
            return false
        }

        let screenBounds = UIScreen.main.bounds
        let finalWidth  = width.map { CGFloat($0.doubleValue) } ?? screenBounds.width
        let finalHeight = height.map { CGFloat($0.doubleValue) } ?? screenBounds.height
        let finalTop    = top.map { CGFloat($0.doubleValue) } ?? 0
        let finalLeft   = left.map { CGFloat($0.doubleValue) } ?? 0

        // 解析真正的顶层 VC（rootVC → presentedVC 链），找不到时回退到调用方传入的 VC
        guard let topVC = CameraViewManager.topViewController() ?? viewController else {
            NSLog("[CameraViewManager] showCameraView: topViewController is nil, cannot create camera view")
            return false
        }

        // 以「子 VC」形式挂载：由 UIKit 接管其 view 的生命周期与旋转，
        // 彻底避免把相机容器直接挂到 keyWindow 带来的脆弱性
        let camVC = CameraViewController()

        topVC.addChild(camVC)
        // 关键修复：camVC.view 只覆盖相机实际显示的区域（left/top/width/height），
        // 而不是整个 topVC.view.bounds。这样底部未覆盖的区域（如底部 120px 按钮栏）
        // 不会被相机图层遮挡，WebView 中的按钮可以正常响应点击。
        // 之前 camVC.view.frame = topVC.view.bounds 会导致相机 VC 的 root view
        // 占满整个屏幕（即使 containerView 只有部分高度），拦截所有触摸事件。
        camVC.view.frame = CGRect(x: finalLeft, y: finalTop, width: finalWidth, height: finalHeight)
        topVC.view.addSubview(camVC.view)
        // 强制立即完成 layout，确保 containerView.bounds 已经正确，
        // 避免后续 attachPreviewLayer 时拿到 CGSize.zero 导致预览层不可见。
        camVC.view.setNeedsLayout()
        camVC.view.layoutIfNeeded()
        camVC.didMove(toParent: topVC)

        cameraViewController = camVC
        cameraContainer = camVC.containerView

        // 注意：预览层由 CameraView 在相机会话启动成功后调用 attachPreviewLayer() 插入，
        // 此处 captureSession 尚未建立，不能直接调 makePreviewLayer

        // 添加自定义视图层
        if let vs = views {
            for v in vs { addCustomView(v) }
        }

        // 初始化扫描条
        if let sb = scanBar {
            NSLog("[CameraViewManager] showCameraView: initializing scanBar with options=\(sb)")
            setupScanBar(sb, containerWidth: finalWidth, containerHeight: finalHeight)
        } else {
            NSLog("[CameraViewManager] showCameraView: no scanBar config")
        }

        isCameraShowing = true
        NSLog("[CameraViewManager] showCameraView: success, isCameraShowing=true, container=\(cameraContainer != nil)")
        return true
    }

    // MARK: - 关闭相机视图

    @objc public func closeCameraView() {
        guard isCameraShowing else { return }
        isCameraShowing = false
        performCloseCameraView()
    }

    /// 强制关闭相机视图：无论 isCameraShowing 状态如何都执行清理
    /// 用于 showCamera 前的兜底清理，避免上一次打开失败导致视图残留
    @objc public func forceCloseCameraView() {
        isCameraShowing = false
        // 关键修复：必须同步执行清理，不能异步。
        // 因为 showCamera 中调用 forceCloseCameraView 后会紧接着调用 showCameraView
        // 创建新的相机视图。如果异步清理，新创建的 cameraViewController/cameraContainer
        // 会被异步闭包错误地设为 nil，导致相机不显示。
        if Thread.isMainThread {
            performCloseCameraViewSync()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.performCloseCameraViewSync()
            }
        }
    }

    private func performCloseCameraViewSync() {
        stopScanBarAnimation()
        removeFocusRing()

        // 按子 VC 规范卸载，避免残留引用导致崩溃
        if let camVC = cameraViewController {
            camVC.willMove(toParent: nil)
            camVC.view.removeFromSuperview()
            camVC.removeFromParent()
            cameraViewController = nil
        }
        cameraContainer?.removeFromSuperview()
        cameraContainer = nil
        // 清理数据
        watermarkConfigs.removeAll()
        preloadedImages.removeAll()
        tapToFocusEnabled = false
    }

    private func performCloseCameraView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.performCloseCameraViewSync()
        }
    }

    // MARK: - 视图管理

    @objc public func updateViews(_ views: [[String: Any]]?) {
        guard isCameraShowing else { return }
        clearCustomViews()
        views?.forEach { addCustomView($0) }
    }

    @objc public func addView(_ viewConfig: [String: Any]) {
        guard isCameraShowing else { return }
        addCustomView(viewConfig)
    }

    @objc public func updateView(uid: String, viewConfig: [String: Any]) {
        guard isCameraShowing else { return }
        removeViewByUid(uid)
        var config = viewConfig
        config["uid"] = uid
        addCustomView(config)
    }

    @objc public func removeView(uid: String) {
        guard isCameraShowing else { return }
        removeViewByUid(uid)
    }

    @objc public func clearViews() {
        guard isCameraShowing else { return }
        clearCustomViews()
    }

    private func clearCustomViews() {
        guard let container = cameraContainer else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            container.subviews.forEach { subview in
                if subview != self.scanBarView && subview.tag != -999 {
                    subview.removeFromSuperview()
                }
            }
        }
        watermarkConfigs.removeAll()
        preloadedImages.removeAll()
    }

    private func removeViewByUid(_ uid: String) {
        guard let container = cameraContainer else { return }
        DispatchQueue.main.async {
            container.subviews.forEach { subview in
                if subview.accessibilityIdentifier == uid {
                    subview.removeFromSuperview()
                }
            }
        }
        // 先查到图片 URL，再从 watermarkConfigs 删除，顺序不能反
        if let urlToRemove = watermarkConfigs.first(where: { ($0["uid"] as? String) == uid })?["image"] as? String {
            preloadedImages.removeValue(forKey: urlToRemove)
        }
        watermarkConfigs.removeAll { ($0["uid"] as? String) == uid }
    }

    // MARK: - 水印配置

    @objc public func getWatermarkConfigs() -> [[String: Any]] {
        return watermarkConfigs
    }

    @objc public func getPreloadedImage(for url: String) -> UIImage? {
        return preloadedImages[url]
    }

    // MARK: - 添加自定义视图

    private func addCustomView(_ config: [String: Any]) {
        let type = config["type"] as? String ?? ""
        let uid = config["uid"] as? String
        let isWatermark = config["watermark"] as? Bool ?? false

        if isWatermark {
            if let uid = uid {
                watermarkConfigs.removeAll { ($0["uid"] as? String) == uid }
            }
            watermarkConfigs.append(config)

            if type == "image", let imageUrl = config["image"] as? String, !imageUrl.isEmpty {
                if preloadedImages[imageUrl] == nil {
                    preloadWatermarkImage(imageUrl)
                }
            }
        }

        switch type {
        case "text":  addTextView(config, uid: uid)
        case "image": addImageView(config, uid: uid)
        default: break
        }
    }

    private func preloadWatermarkImage(_ urlString: String) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let image = self?.loadImage(from: urlString) else { return }
            DispatchQueue.main.async {
                self?.preloadedImages[urlString] = image
            }
        }
    }

    // MARK: - 文本视图

    private func addTextView(_ config: [String: Any], uid: String?) {
        guard let container = cameraContainer else { return }
        let style = config["style"] as? [String: Any]
        let text = config["text"] as? String ?? ""

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            self.applyTextStyle(to: label, style: style, container: container)

            if let uid = uid {
                label.accessibilityIdentifier = uid
            }

            let rotation = self.rotationDegrees(from: style)
            label.transform = CGAffineTransform(rotationAngle: rotation * .pi / 180)

            // 布局
            label.sizeToFit()
            let frame = self.calculateTextFrame(label: label, style: style, container: container)
            label.frame = frame

            container.addSubview(label)
        }
    }

    private func applyTextStyle(to label: UILabel, style: [String: Any]?, container: UIView) {
        // 修复：UTS 层传过来的数值类型是 NSNumber / Double / Int，不是 CGFloat
        let fontSize = CGFloat(toDouble(style?["fontSize"], defaultValue: Double(defaultFontSize)))
        let fontColor = parseColor(style?["fontColor"] as? String) ?? defaultFontColor
        let fontWeight = style?["fontWeight"] as? String ?? "normal"
        let fontStyle = style?["fontStyle"] as? String ?? "normal"
        let isBold = fontWeight == "bold" || (Int(fontWeight) ?? 0) >= 700
        let isItalic = fontStyle == "italic"

        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold   { traits.insert(.traitBold) }
        if isItalic { traits.insert(.traitItalic) }

        if traits.isEmpty {
            label.font = UIFont.systemFont(ofSize: fontSize)
        } else if let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits) {
            label.font = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            label.font = UIFont.systemFont(ofSize: fontSize)
        }

        label.textColor = fontColor

        let textAlign = style?["textAlign"] as? String ?? "left"
        switch textAlign {
        case "center": label.textAlignment = .center
        case "right":  label.textAlignment = .right
        default:       label.textAlignment = .left
        }
    }

    private func calculateTextFrame(label: UILabel, style: [String: Any]?, container: UIView) -> CGRect {
        // 修复：UTS 层传过来的数值类型是 NSNumber / Double / Int，不是 CGFloat
        let topDp    = CGFloat(toDouble(style?["top"],        defaultValue: 0))
        let textOffset = CGFloat(toDouble(style?["textOffset"], defaultValue: 0))
        let textAlign  = style?["textAlign"] as? String ?? "left"
        let rotation   = rotationDegrees(from: style)
        let w = container.bounds.width
        let h = container.bounds.height
        let labelW = min(label.intrinsicContentSize.width + 8, w)
        let labelH = label.intrinsicContentSize.height + 4

        switch Int(rotation) {
        case 0:
            let x: CGFloat
            switch textAlign {
            case "center": x = (w - labelW) / 2 + textOffset
            case "right":  x = w - labelW - textOffset
            default:       x = textOffset
            }
            return CGRect(x: x, y: topDp, width: labelW, height: labelH)

        case 90: // top=距右侧
            let y: CGFloat
            switch textAlign {
            case "center": y = (h - labelH) / 2 + textOffset
            case "right":  y = h - labelH - textOffset
            default:       y = textOffset
            }
            return CGRect(x: w - topDp - labelW, y: y, width: labelW, height: labelH)

        case 180: // top=距底部
            let x: CGFloat
            switch textAlign {
            case "center": x = (w - labelW) / 2 - textOffset
            case "right":  x = textOffset
            default:       x = w - labelW - textOffset
            }
            return CGRect(x: x, y: h - topDp - labelH, width: labelW, height: labelH)

        case 270: // top=距左侧
            let y: CGFloat
            switch textAlign {
            case "center": y = (h - labelH) / 2 - textOffset
            case "right":  y = textOffset
            default:       y = h - labelH - textOffset
            }
            return CGRect(x: topDp, y: y, width: labelW, height: labelH)

        default:
            return CGRect(x: textOffset, y: topDp, width: labelW, height: labelH)
        }
    }

    // MARK: - 图片视图

    private func addImageView(_ config: [String: Any], uid: String?) {
        guard let container = cameraContainer else { return }
        let style  = config["style"] as? [String: Any]
        // 修复：UTS 层传过来的数值类型是 NSNumber / Double / Int，不是 CGFloat
        let topDp  = CGFloat(toDouble(style?["top"],  defaultValue: 0))
        let leftDp = CGFloat(toDouble(style?["left"], defaultValue: 0))
        let rawW: CGFloat? = {
            let v = toDoubleOptional(style?["width"])
            return v != nil ? CGFloat(v!) : nil
        }()
        let rawH: CGFloat? = {
            let v = toDoubleOptional(style?["height"])
            return v != nil ? CGFloat(v!) : nil
        }()
        let rotation = rotationDegrees(from: style)

        let initW = rawW ?? rawH ?? defaultImgSize
        let initH = rawH ?? rawW ?? defaultImgSize

        let imageView = UIImageView(frame: calcImageFrame(
            top: topDp, left: leftDp, width: initW, height: initH,
            rotation: rotation, containerSize: container.bounds.size
        ))
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.transform = CGAffineTransform(rotationAngle: rotation * .pi / 180)

        if let uid = uid {
            imageView.accessibilityIdentifier = uid
        }

        if let urlStr = config["image"] as? String, !urlStr.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak imageView] in
                guard let self = self, let iv = imageView else { return }
                guard let image = self.loadImage(from: urlStr) else { return }
                DispatchQueue.main.async { [weak iv] in
                    guard let iv = iv else { return }
                    iv.image = image
                    // 若宽高未全部指定，按比例调整
                    if rawW == nil || rawH == nil {
                        let bmpW = image.size.width
                        let bmpH = image.size.height
                        guard bmpW > 0, bmpH > 0 else { return }
                        var finalW = initW
                        var finalH = initH
                        if rawW == nil && rawH == nil {
                            finalW = bmpW; finalH = bmpH
                        } else if rawW == nil {
                            let hPx = rawH!
                            finalH = hPx
                            finalW = hPx * bmpW / bmpH
                        } else {
                            let wPx = rawW!
                            finalW = wPx
                            finalH = wPx * bmpH / bmpW
                        }
                        iv.frame = self.calcImageFrame(
                            top: topDp, left: leftDp, width: finalW, height: finalH,
                            rotation: rotation, containerSize: container.bounds.size
                        )
                    }
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            container.addSubview(imageView)
            container.bringSubviewToFront(imageView)
            self?.cameraContainer?.bringSubviewToFront(imageView)
        }
    }

    private func calcImageFrame(top: CGFloat, left: CGFloat, width: CGFloat, height: CGFloat, rotation: CGFloat, containerSize: CGSize) -> CGRect {
        let cw = containerSize.width
        let ch = containerSize.height
        switch Int(rotation) {
        case 90:  // top=距右侧, left=距顶部
            return CGRect(x: cw - top - width, y: left, width: width, height: height)
        case 180: // top=距底部, left=距右侧
            return CGRect(x: cw - left - width, y: ch - top - height, width: width, height: height)
        case 270: // top=距左侧, left=距底部
            return CGRect(x: top, y: ch - left - height, width: width, height: height)
        default:  // rotation=0
            return CGRect(x: left, y: top, width: width, height: height)
        }
    }

    // MARK: - 工具

    private func rotationDegrees(from style: [String: Any]?) -> CGFloat {
        // 修复：UTS 层传过来的数值类型可能是 NSNumber / Double / Int
        return CGFloat(toDouble(style?["rotation"], defaultValue: 0))
    }

    private func parseColor(_ hexStr: String?) -> UIColor? {
        guard var hex = hexStr else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 6 { hex = "FF" + hex }
        guard hex.count == 8 else { return nil }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let a = CGFloat((value >> 24) & 0xFF) / 255
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >>  8) & 0xFF) / 255
        let b = CGFloat( value        & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    func loadImage(from urlString: String) -> UIImage? {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            // 修复：URL 包含中文时需要先 percent-encode
            let encodedUrlString: String
            if urlString.contains("%") {
                encodedUrlString = urlString
            } else if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                encodedUrlString = encoded
            } else {
                encodedUrlString = urlString
            }
            guard let url = URL(string: encodedUrlString),
                  let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        } else {
            return UIImage(contentsOfFile: urlString)
        }
    }

    // MARK: - 公共工具

    /// 稳健获取当前 keyWindow（兼容 iOS 13+ 多 Scene 架构）
    private static func keyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            // 关键修复：权限弹框刚dismiss时，scene可能还处于 .foregroundInactive
            // 状态（尚未完全切换回 .foregroundActive）。如果只接受 .foregroundActive，
            // keyWindow() 会返回 nil，导致 topViewController() 返回 nil，
            // showCameraView 创建失败，相机不显示。
            // 修复：优先查找 .foregroundActive 的 scene，找不到则退而求其次
            // 接受 .foregroundInactive 的 scene（权限弹框dismiss后的过渡态）。
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }

            // 优先：foregroundActive 的 scene
            let activeScene = scenes.first { $0.activationState == .foregroundActive }
            // 兜底：foregroundInactive 的 scene（弹框dismiss过渡态）
            let fallbackScene = scenes.first { $0.activationState == .foregroundInactive }
            let targetScene = activeScene ?? fallbackScene

            // 优先返回 isKeyWindow 的窗口，没有则返回第一个窗口
            if let scene = targetScene {
                if let keyWin = scene.windows.first(where: { $0.isKeyWindow }) {
                    return keyWin
                }
                return scene.windows.first
            }
            // 最后兜底：遍历所有 scene 的所有 window
            return scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.keyWindow
        }
    }

    /// 解析真正的顶层 VC：从 keyWindow 的 rootViewController 沿 presentedViewController
    /// 链走到最上层（跳过 UIAlertController 等临时弹窗，挂到其底层内容 VC）。
    /// 子 VC 挂载到该 VC 后，生命周期与旋转由 UIKit 正确接管。
    private static func topViewController() -> UIViewController? {
        guard let window = keyWindow() else { return nil }
        var vc = window.rootViewController
        while let next = vc?.presentedViewController {
            if next is UIAlertController { break }
            vc = next
        }
        return vc
    }

    @objc public func isCameraVisible() -> Bool { isCameraShowing }

    @objc public func getCameraContainer() -> UIView? { cameraContainer }

    /// 将相机预览层插入容器底层（在 AVCaptureSession 启动成功后调用）
    /// - Parameter successCallback: 预览层成功插入后回调（用于通知 AttachingCallback 继续回调前端）
    /// - Returns: true 表示成功插入预览层；false 表示需要重试（内部会自动延迟重试）
    @objc public func attachPreviewLayer(successCallback: (() -> Void)? = nil) -> Bool {
        NSLog("[CameraViewManager] attachPreviewLayer called")
        guard let container = cameraContainer else {
            NSLog("[CameraViewManager] attachPreviewLayer failed: cameraContainer is nil")
            // container 为 nil 说明相机已被关闭，不再重试
            return false
        }
        // 强制立即完成布局，确保 container.bounds 已经正确
        if let vc = cameraViewController {
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
        }
        let size = container.bounds.size
        NSLog("[CameraViewManager] attachPreviewLayer: container bounds = \(size)")
        guard size.width > 0, size.height > 0 else {
            NSLog("[CameraViewManager] attachPreviewLayer failed: container size is zero \(size)")
            // 关键修复：首次授权后容器可能还未完成布局（bounds 为 zero）。
            // 延迟重试，等布局完成后再次尝试 attach。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                NSLog("[CameraViewManager] attachPreviewLayer retry after 0.1s")
                _ = self.attachPreviewLayer(successCallback: successCallback)
            }
            return false
        }
        guard let previewLayer = CameraController.shared.makePreviewLayer(containerSize: size) else {
            NSLog("[CameraViewManager] attachPreviewLayer failed: captureSession is nil")
            // captureSession 可能还没建立完成，延迟重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                NSLog("[CameraViewManager] attachPreviewLayer retry after 0.1s (session nil)")
                _ = self.attachPreviewLayer(successCallback: successCallback)
            }
            return false
        }
        NSLog("[CameraViewManager] attachPreviewLayer: previewLayer created, frame = \(previewLayer.frame)")
        // 必须在主线程操作 CALayer
        let attach = {
            container.layer.insertSublayer(previewLayer, at: 0)
            NSLog("[CameraViewManager] attachPreviewLayer: previewLayer inserted to container")
            successCallback?()
        }
        if Thread.isMainThread {
            attach()
        } else {
            DispatchQueue.main.async(execute: attach)
        }
        return true
    }

    // MARK: - 点击对焦

    @objc public func enableTapToFocus() {
        guard let container = cameraContainer else { return }
        tapToFocusEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.name = "cameraFocusTap"
        container.addGestureRecognizer(tap)
    }

    @objc public func disableTapToFocus() {
        tapToFocusEnabled = false
        guard let container = cameraContainer else { return }
        container.gestureRecognizers?
            .filter { ($0 as? UITapGestureRecognizer)?.name == "cameraFocusTap" }
            .forEach { container.removeGestureRecognizer($0) }
        removeFocusRing()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard tapToFocusEnabled, let container = cameraContainer else { return }
        let point = recognizer.location(in: container)
        CameraController.shared.focusAt(point: point, in: container)
        showFocusRing(at: point, in: container)
    }

    private func showFocusRing(at center: CGPoint, in container: UIView) {
        removeFocusRing()
        let size: CGFloat = 72
        let ring = UIView(frame: CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size, height: size
        ))
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.borderWidth = 2
        ring.layer.cornerRadius = 8
        ring.alpha = 0
        ring.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        container.addSubview(ring)
        focusRingView = ring

        UIView.animate(withDuration: 0.15, animations: {
            ring.alpha = 1
            ring.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.6, options: [], animations: {
                ring.alpha = 0
            }) { [weak self] _ in
                self?.removeFocusRing()
            }
        }
    }

    private func removeFocusRing() {
        focusRingView?.removeFromSuperview()
        focusRingView = nil
    }

    // MARK: - 扫描条

    @objc public func showScanBar(_ options: [String: Any]) {
        guard let container = cameraContainer else { return }
        hideScanBar()
        setupScanBar(options, containerWidth: container.bounds.width, containerHeight: container.bounds.height)
    }

    @objc public func hideScanBar() {
        stopScanBarAnimation()
        DispatchQueue.main.async { [weak self] in
            self?.scanBarView?.removeFromSuperview()
            self?.scanBarView = nil
        }
    }

    private func setupScanBar(_ options: [String: Any], containerWidth: CGFloat, containerHeight: CGFloat) {
        NSLog("[CameraViewManager] setupScanBar called: options=\(options), containerWidth=\(containerWidth), containerHeight=\(containerHeight)")
        guard let imageUrl = options["image"] as? String, !imageUrl.isEmpty else {
            NSLog("[CameraViewManager] setupScanBar failed: image is empty or not a string")
            return
        }

        // 修复：UTS 层传过来的数值类型可能为 NSNumber / Double / Int，统一转换
        let widthPercent = CGFloat(toDouble(options["widthPercent"], defaultValue: 80))
        let startYDp = CGFloat(toDouble(options["startY"], defaultValue: 30))
        let endYDp   = CGFloat(toDouble(options["endY"],   defaultValue: Double(containerHeight) - 30))

        NSLog("[CameraViewManager] setupScanBar: widthPercent=\(widthPercent), startY=\(startYDp), endY=\(endYDp)")

        let barWidth  = containerWidth * widthPercent / 100
        let barHeight = max(barWidth * 0.04, 4)

        let iv = UIImageView(frame: CGRect(
            x: (containerWidth - barWidth) / 2,
            y: startYDp,
            width: barWidth,
            height: barHeight
        ))
        iv.contentMode = .scaleToFill
        iv.alpha = 0

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let container = self.cameraContainer else {
                NSLog("[CameraViewManager] setupScanBar failed: cameraContainer is nil")
                return
            }
            container.addSubview(iv)
            // 确保扫描条在最上层（预览层是 container.layer 的子图层，在底部）
            container.bringSubviewToFront(iv)
            self.scanBarView = iv
            NSLog("[CameraViewManager] setupScanBar: scanBarView added to container, frame=\(iv.frame)")
        }

        // 异步加载图片（用 URLSession 避免同步阻塞）
        // 修复：URL 包含中文时需要先 percent-encode，否则 URL(string:) 会返回 nil
        let encodedUrlString: String
        if imageUrl.contains("%") {
            // 已经编码过，直接使用
            encodedUrlString = imageUrl
        } else if let encoded = imageUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            // 对中文等非 ASCII 字符进行编码
            encodedUrlString = encoded
        } else {
            encodedUrlString = imageUrl
        }
        NSLog("[CameraViewManager] setupScanBar: original url=\(imageUrl), encoded url=\(encodedUrlString)")
        guard let url = URL(string: encodedUrlString) else {
            NSLog("[CameraViewManager] setupScanBar: invalid url=\(encodedUrlString)")
            return
        }
        NSLog("[CameraViewManager] setupScanBar: loading image from url=\(imageUrl)")
        let task = URLSession.shared.dataTask(with: url) { [weak self, weak iv] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, let barView = iv else { return }
                if let error = error {
                    NSLog("[CameraViewManager] setupScanBar: image load error=\(error.localizedDescription)")
                    return
                }
                guard let data = data, let img = UIImage(data: data) else {
                    NSLog("[CameraViewManager] setupScanBar: image data invalid")
                    return
                }
                barView.image = img
                // 按比例调整高度
                if img.size.width > 0 {
                    let realH = barWidth * img.size.height / img.size.width
                    barView.frame.size.height = max(realH, 2)
                }
                NSLog("[CameraViewManager] setupScanBar: image loaded, size=\(img.size), starting animation")
                self.startScanBarAnimation(view: barView, startY: startYDp, endY: endYDp)
            }
        }
        task.resume()
    }

    /// 容错数值转换：支持 NSNumber / Double / Int / Float
    private func toDouble(_ value: Any?, defaultValue: Double) -> Double {
        guard let v = value else { return defaultValue }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let f = v as? Float { return Double(f) }
        return defaultValue
    }

    /// 可选数值转换：返回 nil 表示值不存在或无法转换
    private func toDoubleOptional(_ value: Any?) -> Double? {
        guard let v = value else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let f = v as? Float { return Double(f) }
        return nil
    }

    private func startScanBarAnimation(view: UIImageView, startY: CGFloat, endY: CGFloat) {
        guard endY > startY else { return }
        stopScanBarAnimation()

        let travel = endY - startY
        let duration: TimeInterval = 2.0

        func loop() {
            view.frame.origin.y = startY
            view.alpha = 0

            UIView.animateKeyframes(withDuration: duration, delay: 0, options: [], animations: {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                    view.alpha = 1
                }
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                    view.frame.origin.y = startY + travel
                }
                UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                    view.alpha = 0
                }
            }, completion: { [weak self] finished in
                guard finished, let self = self, self.scanBarView != nil else { return }
                loop()
            })
        }

        loop()
    }

    private func stopScanBarAnimation() {
        scanBarView?.layer.removeAllAnimations()
    }
}
