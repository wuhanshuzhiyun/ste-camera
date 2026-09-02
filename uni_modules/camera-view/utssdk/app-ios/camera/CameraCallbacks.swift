import Foundation

/// 相机打开回调接口（对标 Android CameraOpenCallback.kt）
/// 注意：errCode 使用 NSNumber 类型以兼容 Objective-C 和 UTS 层
@objc public protocol CameraOpenCallback: AnyObject {
    /// 相机打开成功
    /// - Parameter cameraFacing: "front" 或 "back"
    func onSuccess(cameraFacing: String)

    /// 相机打开失败
    /// - Parameters:
    ///   - errCode: 错误码：1=权限被拒绝，2=相机被占用，3=未知错误
    ///   - errMsg: 错误信息
    func onFail(errCode: NSNumber, errMsg: String)
}

/// 拍照回调接口（对标 Android TakePictureCallback.kt）
@objc public protocol TakePictureCallback: AnyObject {
    /// 拍照成功
    /// - Parameter path: 照片文件绝对路径
    func onSuccess(path: String)

    /// 拍照失败
    func onFail()
}
