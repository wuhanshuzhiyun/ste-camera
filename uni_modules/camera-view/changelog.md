# Changelog

## v1.1.0（2026-08-31）

### 新增特性

**跨平台支持**
- **新增 iOS 完整支持**：基于 AVFoundation 原生架构实现相机预览、子控制器挂载、拍照、水印合成、扫码帧捕获与扫描条动画，支持 iOS 12.0+。

**核心 API 增强**
- **点击对焦（Tap to Focus）**：
  - 新增 `enableTapToFocus()` —— 开启点击对焦功能，点击画面任意位置触发精准聚焦，展示白色扩散框动画。
  - 新增 `disableTapToFocus()` —— 关闭点击对焦功能。
- **视图多方向旋转（rotation）**：
  - `ViewStyle` 新增 `rotation?: "top" | "right" | "bottom" | "left"` 属性，支持 0° / 90° / 180° / 270° 四方向视图排版与坐标系自适应。
- **状态与异常回调**：
  - `showCamera` 增加 `success`、`fail` 与 `complete` 回调。
  - 增加细分错误码机制：`1`（权限被拒绝）、`2`（相机被占用/打开失败）、`3`（未知异常）。

**体验与工程优化**
- **拍照直传与网络优化**：优化 `takePicture` 本地文件路径返回格式，提供与 `uni.uploadFile` 原生直传的无缝集成方案。
- **iOS 权限保障**：内置 `app-ios/Info.plist`，防止因缺少 `NSCameraUsageDescription` 引起闪退。
- **UI 挂载稳定性**：iOS 端重构为 `CameraViewController` 子控制器挂载模型，彻底解决旋转与多层弹窗冲突问题。

---

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
