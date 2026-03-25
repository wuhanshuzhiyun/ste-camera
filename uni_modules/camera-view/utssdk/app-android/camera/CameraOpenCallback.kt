package uts.ste.camera

/**
 * 相机打开回调接口
 * 用于 UTS 层与 Kotlin 层之间的回调桥接
 * 注意：参数只能使用基础类型，不能使用 lambda 或复杂对象
 */
interface CameraOpenCallback {
    /**
     * 相机打开成功
     * @param cameraFacing 当前摄像头：1=前置，0=后置
     */
    fun onSuccess(cameraFacing: Int)

    /**
     * 相机打开失败
     * @param errCode 错误码：1=权限被拒绝，2=相机被占用，3=未知错误
     * @param errMsg 错误信息
     */
    fun onFail(errCode: Int, errMsg: String)
}
