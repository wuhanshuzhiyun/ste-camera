# camera-view 原生相机插件（UTS）

基于 UTS 开发的 Android 原生相机插件。支持自定义窗口大小与位置，可在相机画面上动态叠加文本和图片，支持拍照水印、扫码帧捕获、扫描条动画等功能。

---

## 平台支持

| 平台 | 支持情况 |
|------|----------|
| Android | ✅ 完整支持 |
| iOS | ❌ 暂不支持 |
| 鸿蒙 | ❌ 暂不支持 |
| Web / 小程序 | ❌ 不支持 |

> **最低 Android 版本**：Android 5.0（API 21）

---

## 功能特性

- **自定义窗口**：支持设置相机画面的宽高、位置，实现小窗、半屏、悬浮等布局
- **视图叠加**：在相机预览画面上叠加任意文本或图片元素，支持独立管理（按 uid 增删改）
- **拍照水印**：叠加层中标记为 `watermark: true` 的元素会直接印入拍摄的照片
- **扫码模式**：持续捕获摄像头帧，以 Base64 JPEG 返回，可对接任意二维码/条形码识别库
- **扫描条动画**：内置从上到下的扫描条循环动画，支持自定义图片、宽度与起止位置
- **前后摄像头**：支持前置/后置摄像头切换
- **生命周期管理**：提供 `onPause` / `onResume` / `onDestroy` 配套方法，确保资源正确释放

---

## 安装

将 `camera-view` 目录放置于项目的 `uni_modules/` 目录下，HBuilderX 会自动识别。

---

## 快速开始

### 1. 显示相机并拍照

```javascript
import { showCamera, closeCamera, takePicture } from '@/uni_modules/camera-view'

// 显示相机（全屏，后置）
showCamera({
  cameraFacing: 'back'
})

// 拍照
takePicture((path) => {
  if (path) {
    // path 为绝对文件路径，如 /data/user/0/.../cache/camera_xxx.jpg
    const filePath = path.startsWith('file://') ? path : 'file://' + path
    console.log('拍照成功：', filePath)
  } else {
    console.log('拍照失败')
  }
})

// 关闭相机
closeCamera()
```

### 2. 叠加文本水印

```javascript
import { showCamera, addView } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

// 叠加一个文本水印（watermark: true 会印在照片上）
addView({
  uid: 'watermark-text',
  type: 'text',
  text: `拍摄时间：${new Date().toLocaleString()}`,
  watermark: true,
  style: {
    top: 20,
    fontColor: '#FFFFFF',
    fontWeight: 'bold',
    textAlign: 'center',
    fontSize: 16
  }
})
```

### 3. 扫码模式

```javascript
import { showCamera, startScanMode, getScanFrame, stopScanMode } from '@/uni_modules/camera-view'

// 1. 先显示相机
showCamera({ cameraFacing: 'back' })

// 2. 等相机稳定后（建议 400ms）启动扫码模式
setTimeout(() => {
  const ok = startScanMode()
  if (!ok) return

  // 3. 定时抓帧，送入识别库
  const timer = setInterval(() => {
    const frame = getScanFrame(80)  // 返回 Base64 JPEG 字符串
    if (frame) {
      // 将 frame 传给二维码识别库，如 jsQR / zxing 等
      // decodeQRCode('data:image/jpeg;base64,' + frame)
    }
  }, 500)

  // 4. 识别完成后停止
  // clearInterval(timer)
  // stopScanMode()
}, 400)
```

---

## API 文档

### showCamera(options?)

显示相机窗口。

```typescript
showCamera(options?: CameraOptions): void
```

**CameraOptions 参数：**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `width` | `number` | 屏幕宽度 | 相机窗口宽度（dp） |
| `height` | `number` | 屏幕高度 | 相机窗口高度（dp） |
| `top` | `number` | `0` | 窗口距屏幕顶部的距离（dp） |
| `left` | `number` | `0` | 窗口距屏幕左侧的距离（dp） |
| `cameraFacing` | `'front' \| 'back'` | `'back'` | 初始摄像头（前置/后置） |
| `views` | `View[]` | — | 初始叠加的视图元素数组 |
| `scanBar` | `ScanBarOptions` | — | 扫描条配置（仅在扫码模式下有视觉意义） |

**示例：**
```javascript
// 半屏相机（占屏幕上方 60%）
showCamera({
  width: screenWidth,
  height: Math.floor(screenHeight * 0.6),
  top: 0,
  cameraFacing: 'back',
  views: [{
    type: 'text',
    text: '对准目标拍摄',
    watermark: false,
    style: { top: 20, fontColor: '#fff', textAlign: 'center', fontSize: 16 }
  }]
})

// 小窗模式（右上角）
showCamera({
  width: 150,
  height: 200,
  top: 60,
  left: screenWidth - 160
})
```

---

### closeCamera()

关闭相机并释放所有资源。

```typescript
closeCamera(): void
```

---

### takePicture(callback)

拍照。回调返回照片的本地绝对路径（保存于应用缓存目录）。

```typescript
takePicture(callback: (path: string | null) => void): void
```

> **注意**：拍照结果会按照相机窗口的宽高比自动居中裁剪，确保与预览画面完全一致。如果叠加了 `watermark: true` 的视图元素，它们会被合成到照片中。

---

### addView(viewConfig)

在相机画面上添加单个叠加元素（文本或图片）。

```typescript
addView(viewConfig: View): void
```

**View 参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `uid` | `string` | 可选。元素的唯一标识，用于后续的 updateView / removeView |
| `type` | `'text' \| 'image'` | 元素类型 |
| `text` | `string` | 文本内容（type 为 `text` 时使用） |
| `image` | `string` | 图片路径或 HTTP URL（type 为 `image` 时使用） |
| `watermark` | `boolean` | 是否为水印，`true` 时会印入拍照结果。默认 `false` |
| `style` | `ViewStyle` | 样式配置，见下表 |

**ViewStyle 参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `top` | `number` | 距窗口顶部的距离（dp） |
| `left` | `number` | 距窗口左侧的距离（dp），仅图片生效 |
| `fontSize` | `number` | 字体大小（dp），仅文本生效 |
| `fontColor` | `string` | 字体颜色，十六进制，如 `'#FFFFFF'`，仅文本生效 |
| `fontStyle` | `'normal' \| 'italic'` | 字体样式，仅文本生效 |
| `fontWeight` | `string` | 字体粗细，`'normal'` \| `'bold'` \| `'100'`~`'900'`，仅文本生效 |
| `textAlign` | `'left' \| 'center' \| 'right'` | 文本水平对齐方式，仅文本生效 |
| `textOffset` | `number` | 水平方向偏移量（dp），配合 `textAlign` 微调位置 |
| `width` | `number` | 图片宽度（dp），仅图片生效 |
| `height` | `number` | 图片高度（dp），仅图片生效 |

> **图片尺寸规则**：宽高都传 → 按指定尺寸拉伸；只传宽 → 高按图片比例自适应；只传高 → 宽按比例自适应；都不传 → 使用图片实际像素尺寸。

**示例：**
```javascript
// 添加文本元素（不作为水印）
addView({
  uid: 'hint-text',
  type: 'text',
  text: '对准二维码',
  watermark: false,
  style: {
    top: 30,
    fontColor: '#00FF00',
    fontWeight: 'bold',
    textAlign: 'center',
    fontSize: 18
  }
})

// 添加图片水印
addView({
  uid: 'logo',
  type: 'image',
  image: 'https://example.com/logo.png',
  watermark: true,
  style: { width: 80, height: 80, left: 10, top: 10 }
})
```

---

### updateViews(views)

清除所有现有叠加元素，替换为新的视图数组。

```typescript
updateViews(views: View[]): void
```

---

### updateView(uid, viewConfig)

根据 uid 更新单个叠加元素的内容与样式。

```typescript
updateView(uid: string, viewConfig: View): void
```

---

### removeView(uid)

根据 uid 移除单个叠加元素。

```typescript
removeView(uid: string): void
```

---

### clearViews()

移除所有叠加元素（SurfaceView 和扫描条除外）。

```typescript
clearViews(): void
```

---

### switchCamera()

切换前置/后置摄像头。

```typescript
switchCamera(): void
```

---

### startScanMode()

启动扫码模式，开始持续捕获摄像头预览帧。必须在相机显示后调用。

```typescript
startScanMode(): boolean  // 返回是否启动成功
```

---

### stopScanMode()

停止扫码模式，释放帧缓冲资源。

```typescript
stopScanMode(): boolean  // 返回是否停止成功
```

---

### getScanFrame(quality?)

获取最新一帧的 JPEG Base64 字符串，用于二维码/条形码识别。该方法为**同步调用**，适合高频调用。

```typescript
getScanFrame(quality?: number): string | null
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `quality` | `number` | `85` | JPEG 压缩质量（1-100），建议 70-85 以平衡质量和性能 |

> 返回值为 Base64 字符串（不含 `data:image/jpeg;base64,` 前缀），如未就绪则返回 `null`。

---

### isScanModeActive()

检查扫码模式当前是否正在运行。

```typescript
isScanModeActive(): boolean
```

---

### showScanBar(options)

动态显示扫描条动画。若已有扫描条则先移除再重建。

```typescript
showScanBar(options: ScanBarOptions): void
```

**ScanBarOptions 参数：**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `image` | `string` | — | 扫描条图片路径或 URL（必填） |
| `widthPercent` | `number` | `80` | 扫描条宽度占相机窗口宽度的百分比（0-100） |
| `startY` | `number` | `30` | 扫描条起始位置，距窗口顶部的距离（dp） |
| `endY` | `number` | — | 扫描条终止位置，距窗口顶部的距离（dp），需大于 startY |

> **动画说明**：扫描条从 `startY` 到 `endY` 做单程平移，附带淡入淡出效果，循环播放，单程时长约 2 秒。

**示例：**
```javascript
showScanBar({
  image: 'https://example.com/scan-line.png',
  widthPercent: 80,
  startY: 80,
  endY: 400
})
```

---

### hideScanBar()

停止扫描条动画并从视图中移除，相机继续运行。

```typescript
hideScanBar(): void
```

---

## 生命周期管理

插件提供三个生命周期方法，建议在页面对应生命周期中调用以防止资源泄漏：

```javascript
import { CameraView } from 'uts.ste.camera'  // 仅 uni-app x 需要

// 在 uni-app 中，通过 onShow/onHide 页面生命周期管理
onShow(() => {
  // 页面重新显示时恢复相机（如从其他页面返回）
  // CameraView.onResume()
})

onHide(() => {
  // 页面隐藏时暂停相机（释放相机硬件资源）
  // CameraView.onPause()
})
```

> **注意**：`closeCamera()` 会完全销毁相机视图，适合离开页面时调用；`onPause()` 仅停止预览并释放相机，视图保留，`onResume()` 可以恢复。

---

## 使用示例

### 场景一：半屏相机 + 拍照水印

```javascript
import { showCamera, addView, takePicture, closeCamera } from '@/uni_modules/camera-view'

// 1. 显示半屏相机
showCamera({
  width: uni.getSystemInfoSync().screenWidth,
  height: Math.floor(uni.getSystemInfoSync().screenHeight * 0.6),
  cameraFacing: 'back'
})

// 2. 添加多个水印
addView({
  uid: 'mark-title',
  type: 'text',
  text: '商品验收照',
  watermark: true,
  style: { top: 20, fontColor: '#FFFFFF', fontWeight: 'bold', textAlign: 'center', fontSize: 18 }
})
addView({
  uid: 'mark-time',
  type: 'text',
  text: new Date().toLocaleString(),
  watermark: true,
  style: { top: 48, fontColor: '#FFD700', textAlign: 'right', textOffset: 12, fontSize: 13 }
})

// 3. 拍照
takePicture((path) => {
  if (path) {
    const url = 'file://' + path
    // 展示或上传 url
  }
  closeCamera()
})
```

---

### 场景二：扫描条 + 扫码识别

```javascript
import { showCamera, showScanBar, startScanMode, getScanFrame, stopScanMode, closeCamera } from '@/uni_modules/camera-view'

const { screenWidth, screenHeight } = uni.getSystemInfoSync()
let timer = null

// 1. 打开相机
showCamera({ height: screenHeight - 120 })

// 2. 等相机稳定
setTimeout(() => {
  // 3. 显示扫描条动画
  showScanBar({
    image: 'https://example.com/scan-line.png',
    widthPercent: 80,
    startY: 80,
    endY: 400
  })

  // 4. 启动扫码模式
  startScanMode()

  // 5. 定时抓帧识别
  timer = setInterval(() => {
    const frame = getScanFrame(75)
    if (frame) {
      // 传给识别库
      // const result = jsQR(...)
      // if (result) { handleResult(result.data); clearTimer() }
    }
  }, 500)
}, 400)

function clearTimer() {
  clearInterval(timer)
  stopScanMode()
  closeCamera()
}
```

---

### 场景三：scan-photo 组件（集成扫码 + 拍照双模式）

插件内置了一个开箱即用的 `scan-photo` 组件，集成了扫码/拍照双 Tab 切换，可直接使用：

```vue
<template>
  <scanPhoto
    @scan-mode="onScanFrame"
    @take-picture="onTakePicture"
  />
</template>

<script setup>
import scanPhoto from '@/uni_modules/camera-view/components/scan-photo.vue'

function onScanFrame(base64) {
  // base64 为相机帧数据，传入识别库
}

function onTakePicture(path) {
  // path 为拍照文件绝对路径
  console.log('拍照：', path)
}
</script>
```

---

## 注意事项

### 权限
插件会自动处理 Android 6.0+ 的相机动态权限请求。`AndroidManifest.xml` 中需声明：
```xml
<uses-permission android:name="android.permission.CAMERA" />
```
HBuilderX 会自动注入该权限，无需手动配置。

### 调用时序
- `takePicture` / `startScanMode` 必须在 `showCamera` **之后** 调用
- `startScanMode` 建议在 `showCamera` 后等待 **300-500ms** 再调用（等待相机预热）
- `getScanFrame` 在 `startScanMode` 后立即调用可能返回 `null`（首帧尚未就绪），这是正常现象

### 资源释放
- 页面关闭/隐藏时务必调用 `closeCamera()` 或 `stopScanMode()`，否则相机硬件资源不会释放
- 不再使用的 uid 视图建议及时调用 `removeView()` 释放内存

### 图片加载
- `image` 类型视图和扫描条图片均支持 HTTP URL 和本地绝对路径
- 水印图片会在后台异步预加载；如果图片加载较慢，首次拍照时水印可能未就绪，建议等待加载完成后再拍照

---

## 常见问题

**Q：相机黑屏或无法启动？**  
A：检查是否已授予相机权限；确认 Android 版本 ≥ 5.0；部分机型相机被系统应用占用时会打开失败，稍后重试。

**Q：拍照结果与预览画面比例不一致？**  
A：插件会自动按预览窗口比例居中裁剪照片。如果出现黑边，说明设备相机支持的预览分辨率比例与窗口比例差距较大，属正常现象。

**Q：getScanFrame 总是返回 null？**  
A：确认已调用 `startScanMode()` 且返回 `true`；相机刚启动时前几帧可能为 null，等待 200-300ms 后重试。

**Q：水印未印入照片？**  
A：确认视图的 `watermark` 字段设置为 `true`；图片类型水印需等待图片异步加载完成后拍照。

**Q：扫描条不显示？**  
A：检查 `image` 字段是否为有效 URL 或路径；确认 `endY > startY`；`showScanBar` 需在相机显示后调用。

---

## 版本信息

- **当前版本**：v1.0.0
- **最低 HBuilderX 版本**：4.0.0
- **最低 uni-app 版本**：3.1.0
- **Android 最低版本**：Android 5.0（API Level 21）
