# camera-view

> 基于 UTS 开发的 Android / iOS 原生相机插件，适用于 uni-app / uni-app X。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)]()
[![Version](https://img.shields.io/badge/version-1.1.0-orange.svg)]()

---

## 简介

`camera-view` 是一个基于 UTS（uni-app 原生扩展语言）开发的高性能跨平台原生相机插件。底层在 **Android**（基于 Camera1 API）与 **iOS**（基于 AVFoundation 框架）均采用原生实现，提供完整的相机生命周期控制能力：

- 灵活的自定义窗口大小与挂载位置（支持全屏、半屏、悬浮小窗）；
- 毫秒级原生视图叠加与 4 方向旋转（0° / 90° / 180° / 270°）；
- 高清照片拍摄与硬件级水印实时合成；
- 原生点击对焦与聚焦框动效；
- 高频扫码帧捕获（Base64 JPEG）与动态扫描条动画；
- 完善的权限管理、状态反馈与异常错误码机制。

---

## 功能特性

- **跨平台双端原生**：Android（API 21+）与 iOS（iOS 12.0+）深度适配，原生渲染流畅无卡顿
- **自定义窗口布局**：灵活设置相机画面的宽高与位置，实现小窗、半屏、画中画等多种布局
- **视图叠加与旋转**：在相机画面上叠加文本或图片，支持按 `uid` 增删改及 `top` / `right` / `bottom` / `left` 4 方向旋转
- **拍照水印合成**：标记 `watermark: true` 的叠加元素自动以高保真效果合成至输出照片
- **原生点击对焦**：支持点击相机画面任意位置触发精准对焦，并展示白色对焦框扩散动画
- **扫码帧捕获**：高频捕获摄像头预览帧，同步输出 Base64 JPEG 格式，可无缝对接 jsQR、ZXing 等识别库
- **动态扫描条**：内置循环移动的扫描条动画，支持自定义图片、宽度比例与起止高度，支持运行时动态显隐
- **前后摄像头切换**：支持前置与后置摄像头运行时无缝切换
- **状态与错误回调**：`showCamera` 提供 `success`、`fail` 与 `complete` 回调，包含详细错误码（权限拒绝、设备占用等）
- **生命周期安全**：提供配套的 `onPause` / `onResume` / `closeCamera` 资源释放机制

---

## 平台支持

| 平台 | 支持情况 | 最低系统版本 / 环境要求 |
|------|----------|------------------------|
| **Android** | ✅ 完整支持 | Android 5.0（API Level 21+） |
| **iOS** | ✅ 完整支持 | iOS 12.0+（iPhone / iPad） |
| **HarmonyOS** | ⏳ 规划中 | — |
| **Web / 小程序** | ❌ 不支持 | 原生插件仅支持 App 端 |

---

## 安装与配置

### 1. 安装插件

将 `camera-view` 目录放置于 uni-app 项目的 `uni_modules/` 目录下：

```
your-project/
└── uni_modules/
    └── camera-view/        ← 插件目录
        ├── utssdk/
        │   ├── app-android/
        │   ├── app-ios/
        │   └── interface.uts
        ├── components/
        ├── readme.md
        ├── changelog.md
        └── package.json
```

### 2. 权限声明

- **Android**：插件会自动注入 `android.permission.CAMERA` 动态权限，无需手动配置。
- **iOS**：需在 `manifest.json` 中配置相机权限使用描述（`NSCameraUsageDescription`）：
  ```json
  /* manifest.json -> app-plus -> distribute -> ios */
  "plistcmds": [
    "Set :NSCameraUsageDescription 需使用相机进行拍照和扫描"
  ]
  ```
  *(插件已内置 `app-ios/Info.plist`，打包时将自动完成权限配置合并)*

---

## 快速开始

### 1. 显示相机与拍照上传

```javascript
import { showCamera, takePicture, closeCamera } from '@/uni_modules/camera-view'

// 打开相机
showCamera({
  cameraFacing: 'back',
  success: (res) => {
    console.log('相机打开成功，当前镜头：', res.cameraFacing)
  },
  fail: (err) => {
    console.error('相机打开失败：', err.errCode, err.errMsg)
  }
})

// 拍照并使用 uni.uploadFile 直接上传（无需 uni.chooseMedia）
takePicture((path) => {
  if (path) {
    // Android / iOS 均返回本地文件绝对路径
    const filePath = path.startsWith('file://') ? path : 'file://' + path
    console.log('拍照成功：', filePath)

    // 直接上传
    uni.uploadFile({
      url: 'https://api.example.com/upload',
      filePath: filePath,
      name: 'file',
      success: (uploadRes) => {
        console.log('上传成功：', uploadRes.data)
      }
    })
  }
})

// 离开时关闭相机
closeCamera()
```

### 2. 叠加文本水印与方向旋转

```javascript
import { showCamera, addView } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

// 添加旋转水印（文字沿右侧顺时针 90° 排版）
addView({
  uid: 'watermark-text',
  type: 'text',
  text: `现场记录 · ${new Date().toLocaleString()}`,
  watermark: true,
  style: {
    top: 20,
    fontSize: 14,
    fontColor: '#FFFFFF',
    fontWeight: 'bold',
    textAlign: 'center',
    rotation: 'right' // 'top'(0°) | 'right'(90°) | 'bottom'(180°) | 'left'(270°)
  }
})
```

### 3. 开启点击对焦

```javascript
import { showCamera, enableTapToFocus } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

// 开启后点击画面任意区域触发对焦，并在点击处展示白色对焦动效
enableTapToFocus()
```

### 4. 扫码模式与动态扫描条

```javascript
import { showCamera, showScanBar, startScanMode, getScanFrame, stopScanMode } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

setTimeout(() => {
  // 1. 显示扫描条动画
  showScanBar({
    image: 'https://example.com/scan-line.png',
    widthPercent: 80,
    startY: 60,
    endY: 360
  })

  // 2. 启动扫码帧捕获
  startScanMode()

  // 3. 高频同步抓帧
  const timer = setInterval(() => {
    const frameBase64 = getScanFrame(85)
    if (frameBase64) {
      // 传入解码库进行解析
      // const res = decodeQRCode(frameBase64)
    }
  }, 300)
}, 400)
```

---

## API 概览

| 方法 | 类型定义 / 入参 | 说明 |
|------|-----------------|------|
| `showCamera(options?)` | `(options?: CameraOptions) => void` | 显示相机窗口（支持自定义宽高、位置、镜头、视图、扫描条及回调） |
| `closeCamera()` | `() => void` | 关闭相机窗口并释放双端原生资源 |
| `takePicture(callback)` | `(callback: (path: string) => void) => void` | 拍照并合成水印，回调返回本地绝对文件路径 |
| `enableTapToFocus()` | `() => void` | 开启点击对焦功能与动画 |
| `disableTapToFocus()` | `() => void` | 关闭点击对焦功能 |
| `addView(viewConfig)` | `(viewConfig: View) => void` | 动态添加单个文本或图片叠加元素（支持水印与旋转） |
| `updateView(uid, viewConfig)` | `(uid: string, viewConfig: View) => void` | 根据 `uid` 动态更新指定叠加元素的内容与样式 |
| `removeView(uid)` | `(uid: string) => void` | 根据 `uid` 移除指定叠加元素 |
| `updateViews(views)` | `(views: View[]) => void` | 批量重置所有叠加视图 |
| `clearViews()` | `() => void` | 清空所有叠加视图（保留相机画面与扫描条） |
| `switchCamera()` | `() => void` | 运行时切换前置 / 后置摄像头 |
| `startScanMode()` | `() => boolean` | 启动扫码帧捕获模式 |
| `stopScanMode()` | `() => boolean` | 停止扫码帧捕获模式 |
| `getScanFrame(quality?)` | `(quality?: number) => string \| null` | 同步获取最新一帧 Base64 JPEG 图像数据 |
| `isScanModeActive()` | `() => boolean` | 查询扫码模式当前是否运行中 |
| `showScanBar(options)` | `(options: ScanBarOptions) => void` | 动态显示自定义扫描条动画 |
| `hideScanBar()` | `() => void` | 动态隐藏扫描条动画 |

> 完整参数规格与高级用法详见 [`uni_modules/camera-view/readme.md`](uni_modules/camera-view/readme.md)。

---

## 目录结构

```
camera-view/
├── utssdk/
│   ├── interface.uts                   # 全平台 TypeScript 接口定义
│   ├── unierror.uts                    # UTS 标准错误规范定义
│   ├── app-android/                    # Android 原生实现层
│   │   ├── index.uts                   # UTS Android 桥接层
│   │   └── camera/
│   │       ├── CameraView.kt           # 单例外观入口
│   │       ├── CameraController.kt     # 相机生命周期、硬件控制与帧捕获
│   │       ├── CameraViewManager.kt    # 原生 UI 容器、叠加层、点击对焦框与扫描条
│   │       ├── CameraPermissionHelper.kt # 动态权限请求与校验
│   │       └── ImageProcessor.kt       # Bitmap 水印合成、方向矫正与持久化
│   ├── app-ios/                        # iOS 原生实现层
│   │   ├── Info.plist                  # iOS 权限配置模版
│   │   ├── index.uts                   # UTS iOS 桥接层
│   │   └── camera/
│   │       ├── CameraView.swift        # 单例外观入口
│   │       ├── CameraViewController.swift # 自适应子控制器容器
│   │       ├── CameraController.swift  # AVFoundation 相机硬件调度
│   │       ├── CameraViewManager.swift # 视图管理、对焦动画与扫描条
│   │       ├── CameraCallbacks.swift   # 回调协议定义
│   │       └── ImageProcessor.swift    # CoreGraphics 水印合成与裁剪
│   └── app-harmony/                    # HarmonyOS 适配预留
├── components/
│   ├── scan-photo.vue                  # 扫码 / 拍照双模式开箱即用组件
│   ├── all-test.vue                    # 全 API 交互式功能调试面板
│   └── const.js                        # 测试常量集
├── readme.md                           # 插件详尽说明文档
├── changelog.md                        # 版本发布与更新日志
└── package.json                        # 插件配置与元信息
```

---

## 版本要求

| 工具 / 框架 | 最低版本要求 |
|-------------|--------------|
| HBuilderX | 4.0.0+ |
| uni-app | 3.1.0+（Vue2 / Vue3） |
| uni-app X | 3.1.0+ |
| Android SDK | 21+（Android 5.0 及以上） |
| iOS SDK | iOS 12.0+ |

---

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

**版权所有 © 2025-2026 武汉数智云科技有限公司**

在遵守 MIT 协议的前提下，您可以自由使用、修改和分发本项目代码，但需保留原始版权声明。

---

## 关于我们

**武汉数智云科技有限公司**

专注于移动端原生能力扩展与企业级应用开发，致力于为 uni-app 生态提供高质量的原生插件与解决方案。

*如有问题或建议，欢迎提交 Issue 或 Pull Request。*
