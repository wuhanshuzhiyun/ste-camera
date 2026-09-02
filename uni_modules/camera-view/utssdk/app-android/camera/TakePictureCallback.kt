package uts.ste.camera

/**
 * 拍照回调接口
 * 用于 UTS 层与 Kotlin 层之间的回调桥接
 * 注意：参数只能使用基础类型，不能使用 lambda 或复杂对象
 */
interface TakePictureCallback {
    /**
     * 拍照成功
     * @param path 照片文件路径
     */
    fun onSuccess(path: String)

    /**
     * 拍照失败
     */
    fun onFail()
}
