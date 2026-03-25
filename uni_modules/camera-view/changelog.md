# Changelog

## v1.0.0（2026-03-25）

首次发布。

### 新增功能

**基础相机**
- `showCamera(options?)` —— 显示相机窗口，支持自定义宽高、位置、初始摄像头
- `closeCamera()` —— 关闭相机并释放所有原生资源
- `takePicture(callback)` —— 拍照，结果按预览窗口比例居中裁剪后保存至缓存目录
- `switchCamera()` —— 运行时切换前置/后置摄像头

**视图叠加层**
- `addView(viewConfig)` —— 在相机画面上叠加单个文本或图片元素
- `updateView(uid, viewConfig)` —— 按 uid 更新指定叠加元素
- `removeView(uid)` —— 按 uid 移除指定叠加元素
- `updateViews(views)` —— 批量重设所有叠加元素
- `clearViews()` —— 清除所有叠加元素

**拍照水印**
- 叠加元素设置 `watermark: true` 后，会在拍照时合成至照片

**扫码模式**
- `startScanMode()` —— 启动帧捕获，持续获取摄像头预览帧
- `stopScanMode()` —— 停止帧捕获，释放帧缓冲资源
- `getScanFrame(quality?)` —— 同步获取最新一帧，返回 JPEG Base64 字符串
- `isScanModeActive()` —— 查询扫码模式是否正在运行

**扫描条动画**
- `showScanBar(options)` —— 动态显示自定义图片扫描条，支持配置宽度百分比和起止位置
- `hideScanBar()` —— 移除扫描条，相机继续运行

**生命周期**
- `onPause()` / `onResume()` / `onDestroy()` —— 配套页面生命周期，管理相机硬件资源

**内置组件**
- `scan-photo.vue` —— 扫码/拍照双 Tab 组件，集成扫描条动画和帧捕获，开箱即用
- `all-test.vue` —— 全功能测试页，覆盖所有 API 的交互演示

### 技术实现

- 基于 Android Camera1 API（`android.hardware.Camera`）
- 前置摄像头自动处理镜像翻转和旋转矫正
- 扫码帧捕获使用 `setPreviewCallback` + `AtomicBoolean` 保证线程安全
- 图片水印异步预加载，使用 `ReentrantLock` 保护帧数据并发访问
- 扫描条动画基于 `AnimatorSet` + `ObjectAnimator`，含淡入淡出效果
