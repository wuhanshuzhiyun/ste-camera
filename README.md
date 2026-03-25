# camera-view

> 基于 UTS 开发的 Android 原生相机插件，适用于 uni-app / uni-app X。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green.svg)]()
[![Version](https://img.shields.io/badge/version-1.0.0-orange.svg)]()

---

## 简介

`camera-view` 是一个基于 UTS（uni-app 原生扩展语言）开发的 Android 原生相机插件。它通过 Android Camera1 API 提供完整的相机控制能力，支持自定义窗口大小与位置、在相机画面上动态叠加视图元素、拍照水印合成、扫码帧捕获以及扫描条动画等功能。

---

## 功能特性

- **自定义窗口布局**：灵活设置相机画面的宽高与位置，实现小窗、半屏、悬浮窗等多种布局
- **视图叠加**：在相机预览画面上叠加任意文本或图片元素，支持按 `uid` 增删改，动态管理
- **拍照水印**：标记 `watermark: true` 的叠加元素会直接合成进拍摄的照片
- **扫码模式**：持续捕获摄像头帧，以 Base64 JPEG 格式返回，可对接任意二维码/条形码识别库
- **扫描条动画**：内置循环扫描条动画，支持自定义图片、宽度百分比与起止位置
- **动态扫描条控制**：通过 `showScanBar` / `hideScanBar` 在相机运行中动态显示或隐藏扫描条
- **前后摄像头切换**：支持前置/后置摄像头实时切换
- **生命周期管理**：提供 `onPause` / `onResume` / `onDestroy` 配套方法，确保资源正确释放

---

## 平台支持

| 平台 | 支持情况 |
|------|----------|
| Android | ✅ 完整支持（最低 Android 5.0 / API 21） |
| iOS | ❌ 暂不支持 |
| 鸿蒙 | ❌ 暂不支持 |
| Web / 小程序 | ❌ 不支持 |

---

## 安装

将 `camera-view` 目录放置于 uni-app 项目的 `uni_modules/` 目录下，HBuilderX 会自动识别并注入相机权限。

```
your-project/
└── uni_modules/
    └── camera-view/        ← 将本仓库放置于此
        ├── utssdk/
        ├── components/
        ├── readme.md
        └── package.json
```

---

## 快速开始

### 1. 显示相机并拍照

```javascript
import { showCamera, takePicture, closeCamera } from '@/uni_modules/camera-view'

// 显示全屏相机
showCamera({ cameraFacing: 'back' })

// 拍照
takePicture((path) => {
  if (path) {
    const filePath = path.startsWith('file://') ? path : 'file://' + path
    console.log('拍照成功：', filePath)
  }
})

// 关闭相机
closeCamera()
```

### 2. 叠加文本水印

```javascript
import { showCamera, addView, takePicture } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

addView({
  uid: 'watermark-text',
  type: 'text',
  text: '武汉数智云科技有限公司',
  watermark: true,
  style: {
    top: 20,
    fontSize: 14,
    fontColor: '#FFFFFF',
    textAlign: 'right'
  }
})
```

### 3. 扫码模式

```javascript
import { showCamera, startScanMode, getScanFrame, stopScanMode } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

setTimeout(() => {
  startScanMode()

  const timer = setInterval(() => {
    const frame = getScanFrame(85)
    if (frame) {
      // 将 frame（Base64 JPEG）传入二维码识别库
    }
  }, 300)
}, 400)
```

---

## API 概览

| 方法 | 说明 |
|------|------|
| `showCamera(options?)` | 显示相机窗口 |
| `closeCamera()` | 关闭相机窗口 |
| `takePicture(callback)` | 拍照，回调返回文件路径 |
| `addView(viewConfig)` | 添加叠加视图元素 |
| `updateView(uid, viewConfig)` | 更新指定 uid 的视图元素 |
| `removeView(uid)` | 移除指定 uid 的视图元素 |
| `updateViews(views)` | 重置所有叠加视图 |
| `clearViews()` | 清空所有叠加视图（保留 SurfaceView 和扫描条） |
| `switchCamera()` | 切换前/后置摄像头 |
| `startScanMode()` | 启动扫码帧捕获模式 |
| `stopScanMode()` | 停止扫码帧捕获模式 |
| `getScanFrame(quality?)` | 获取当前帧（Base64 JPEG） |
| `isScanModeActive()` | 检查扫码模式是否运行中 |
| `showScanBar(options)` | 动态显示扫描条 |
| `hideScanBar()` | 动态隐藏扫描条 |

> 完整参数说明请参阅 [`uni_modules/camera-view/readme.md`](uni_modules/camera-view/readme.md)

---

## 目录结构

```
camera-view/
├── utssdk/
│   ├── interface.uts                   # 类型定义（全部 API 类型）
│   └── app-android/
│       ├── index.uts                   # UTS 桥接层
│       └── camera/
│           ├── CameraView.kt           # 对外统一入口（单例）
│           ├── CameraController.kt     # 相机核心（预览/拍照/帧捕获）
│           ├── CameraViewManager.kt    # UI 视图管理（叠加层/扫描条动画）
│           ├── CameraPermissionHelper.kt  # Android 动态权限管理
│           └── ImageProcessor.kt       # Bitmap 变换/水印合成/文件保存
├── components/
│   ├── scan-photo.vue                  # 扫码识别组件示例
│   ├── all-test.vue                    # 全功能调试面板
│   └── const.js                        # 公共常量
├── readme.md                           # 插件详细文档
├── changelog.md                        # 版本变更记录
└── package.json                        # 插件元信息
```

---

## 版本要求

| 工具 / 框架 | 最低版本 |
|-------------|----------|
| HBuilderX | 4.0.0 |
| uni-app | 3.1.0 |
| uni-app X | 3.1.0 |
| Android SDK | 21（Android 5.0） |

---

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

**版权所有 © 2025 武汉数智云科技有限公司**

在遵守 MIT 协议的前提下，您可以自由使用、修改和分发本项目代码，但需保留原始版权声明。

---

## 关于我们

**武汉数智云科技有限公司**

专注于移动端原生能力扩展与企业级应用开发，致力于为 uni-app 生态提供高质量的原生插件与解决方案。

---

*如有问题或建议，欢迎提交 [Issue](../../issues) 或 [Pull Request](../../pulls)。*
