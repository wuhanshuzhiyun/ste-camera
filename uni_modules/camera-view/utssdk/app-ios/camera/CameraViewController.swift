import UIKit

/// 相机承载 VC：作为「子 VC」挂到 App 顶层 VC 上。
/// 自身只负责一个容器视图（containerView）的布局与生命周期接管，
/// 预览层与叠加层继续由 CameraViewManager 挂在 containerView 上，
/// 因此原有叠加/扫描条/对焦逻辑完全不变。
///
/// 采用子 VC 而非直接把 UIView 挂到 keyWindow，可让 UIKit 正确接管
/// view 的生命周期与旋转，彻底消除 window 嫁接带来的崩溃类。
///
/// 关键修复：本 VC 的 root view 使用 PassThroughView，
/// 只有 containerView 区域会拦截触摸事件，其他区域事件穿透到下层 WebView，
/// 从而解决「打开区域相机后其他元素无法交互」的问题。
public final class CameraViewController: UIViewController {

    // 相机容器（黑底、裁剪）。预览层与叠加层都加在它上面。
    public let containerView = UIView()

    public override func loadView() {
        // 使用 PassThroughView 作为 root view：
        // 非 containerView 区域的触摸事件会穿透到下层（hitTest 返回 nil），
        // 这样即使 camVC.view 的 frame 覆盖了整个屏幕，
        // 底部按钮区域仍可正常响应点击和滑动。
        let root = PassThroughView()
        root.backgroundColor = .clear
        // 注意：不能关闭 root 的 isUserInteractionEnabled，
        // 否则 containerView 内的子视图也无法响应事件。
        // 穿透逻辑由 PassThroughView.hitTest 实现。

        containerView.backgroundColor = .black
        containerView.clipsToBounds = true
        root.addSubview(containerView)

        self.view = root
        layoutContainer()
    }

    /// 布局 containerView：直接填满 view.bounds
    /// （view 的 frame 已由 CameraViewManager 设置为相机实际显示的区域）
    private func layoutContainer() {
        let b = view.bounds
        guard b.width > 0, b.height > 0 else { return }
        containerView.frame = b
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layoutContainer()
        
        // 关键修复：容器布局变化时，同步更新预览层的 frame
        // 否则预览层可能因为 frame 不匹配而显示为黑屏
        if let previewLayer = CameraController.shared.getPreviewLayer() {
            previewLayer.frame = containerView.bounds
        }
    }

    public override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.layoutContainer()
        }, completion: nil)
    }
}

/// 事件穿透 View：仅当触摸点落在 containerView 内时才拦截事件，
/// 否则 hitTest 返回 nil，让事件穿透到下层视图（如 WebView）。
/// 这样即使该 view 的 frame 覆盖了整个屏幕，非相机区域也能正常交互。
final class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 先让 UIKit 按默认逻辑找出命中点（会遍历所有 subviews）
        let result = super.hitTest(point, with: event)
        // 如果命中点是 nil（没点到任何子视图）或命中点是 self（点到空白区域），
        // 则返回 nil 让事件穿透到下层。
        // 否则返回命中的子视图（如 containerView 及其子视图）。
        if result == nil || result === self {
            return nil
        }
        return result
    }
}
