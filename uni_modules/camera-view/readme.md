# camera-view 原生相机插件（UTS）

基于 UTS 开发的高性能 Android / iOS 原生相机插件。底层基于 **Android Camera1** 与 **iOS AVFoundation** 实现，支持自定义相机窗口大小与位置、动态视图叠加与旋转、拍照水印合成、点击对焦、高频扫码帧捕获、扫描条动画等全套功能。

---

## 平台支持

| 平台 | 支持情况 | 最低系统版本 / 环境要求 |
|------|----------|------------------------|
| **Android** | ✅ 完整支持 | Android 5.0（API Level 21+） |
| **iOS** | ✅ 完整支持 | iOS 12.0+（iPhone / iPad） |
| **HarmonyOS** | ⏳ 规划中 | — |
| **Web / 小程序** | ❌ 不支持 | 原生插件仅支持 App 端 |

> **开发环境要求**：HBuilderX ^4.0.0，uni-app（Vue2 / Vue3）或 uni-app X。

---

## 功能特性

- **跨平台双端原生**：Android 与 iOS 双端底层深度原生定制，画面渲染丝滑，帧率稳定
- **自定义窗口布局**：支持设置相机画面的宽高与位置（支持全屏、半屏、悬浮小窗、画中画等多种排版）
- **视图叠加与旋转**：在相机画面上动态叠加文本或图片，支持按 `uid` 增删改及 0° / 90° / 180° / 270° 四方向旋转
- **硬件级拍照水印**：标记 `watermark: true` 的叠加元素将在拍摄时自动合成进最终照片
- **原生点击对焦**：支持点击画面任意位置触发精准对焦，并附带白色对焦框缩放动效
- **高频扫码帧捕获**：毫秒级捕获预览帧，同步输出 Base64 JPEG 数据，可无缝对接各类二维码/条形码识别引擎
- **动态扫描条**：内置单程循环扫描动画，支持自定义图片、起止位置与宽度比例，支持运行时动态显隐
- **前后摄像头切换**：支持前置/后置摄像头实时切换与镜像校正
- **状态与错误回调**：`showCamera` 提供 `success`、`fail`（含细分错误码）与 `complete` 回调
- **生命周期管理**：提供配套的 `onPause` / `onResume` / `onDestroy` 机制，保障原生硬件资源安全释放

---

## 安装与配置

### 1. 目录结构

将 `camera-view` 放置于项目的 `uni_modules/` 目录下：

```
your-project/
└── uni_modules/
    └── camera-view/
        ├── utssdk/
        │   ├── interface.uts           # 类型定义
        │   ├── app-android/            # Android 原生实现
        │   └── app-ios/                # iOS 原生实现
        ├── components/
        │   ├── scan-photo.vue          # 扫码/拍照通用组件
        │   └── all-test.vue            # 全 API 调试面板
        ├── readme.md
        ├── changelog.md
        └── package.json
```

### 2. 权限配置说明

- **Android 权限**：插件会自动申请并处理动态相机权限，`AndroidManifest.xml` 会由 HBuilderX 自动注入 `<uses-permission android:name="android.permission.CAMERA" />`。
- **iOS 权限**：需在 `manifest.json` 中配置相机使用描述（`NSCameraUsageDescription`），否则在调用相机时系统会直接终止应用：
  ```json
  /* manifest.json -> app-plus -> distribute -> ios */
  "plistcmds": [
    "Set :NSCameraUsageDescription 需使用相机进行拍照和扫描"
  ]
  ```
  *(插件已内置 `app-ios/Info.plist`，在打包基座时将自动合并)*

---

## 快速开始

### 1. 显示相机并拍照上传

```javascript
import { showCamera, closeCamera, takePicture } from '@/uni_modules/camera-view'

// 1. 显示全屏后置相机
showCamera({
  cameraFacing: 'back',
  success: (res) => {
    console.log('相机启动成功，当前镜头：', res.cameraFacing)
  },
  fail: (err) => {
    console.error('相机启动失败：', err.errCode, err.errMsg)
  }
})

// 2. 拍照获取本地绝对路径，并直接上传
takePicture((path) => {
  if (path) {
    // path 格式如：/data/user/0/.../cache/camera_xxx.jpg 或 file:///var/mobile/...
    const filePath = path.startsWith('file://') ? path : 'file://' + path
    console.log('拍照成功：', filePath)

    // 直接使用 uni.uploadFile 上传，无需且不要调用 uni.chooseMedia
    uni.uploadFile({
      url: 'https://api.example.com/upload',
      filePath: filePath,
      name: 'file',
      success: (uploadRes) => {
        console.log('上传完成：', uploadRes.data)
      }
    })
  } else {
    console.log('拍照取消或失败')
  }
})

// 3. 关闭相机并释放资源
closeCamera()
```

### 2. 叠加文本/图片水印与旋转

```javascript
import { showCamera, addView } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

// 添加居中文本水印
addView({
  uid: 'watermark-text',
  type: 'text',
  text: `巡检时间：${new Date().toLocaleString()}`,
  watermark: true,
  style: {
    top: 24,
    fontColor: '#FFFFFF',
    fontWeight: 'bold',
    textAlign: 'center',
    fontSize: 16
  }
})

// 添加旋转水印（文字在右侧顺时针旋转 90°）
addView({
  uid: 'watermark-rotate',
  type: 'text',
  text: '设备编号：DEV-20260831',
  watermark: true,
  style: {
    top: 30,
    fontColor: '#00FF00',
    rotation: 'right', // 顺时针旋转 90°
    fontSize: 14
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

### 4. 扫码模式与动态抓帧

```javascript
import { showCamera, startScanMode, getScanFrame, stopScanMode } from '@/uni_modules/camera-view'

showCamera({ cameraFacing: 'back' })

// 等待相机稳定后启动扫码
setTimeout(() => {
  const ok = startScanMode()
  if (!ok) return

  // 高频定时同步获取帧数据
  const timer = setInterval(() => {
    const frameBase64 = getScanFrame(80) // 返回 Base64 JPEG 字符串
    if (frameBase64) {
      // 传入二维码/条形码识别库（如 jsQR、zxing 等）
      // decodeQRCode('data:image/jpeg;base64,' + frameBase64)
    }
  }, 300)

  // 识别完成后停止
  // clearInterval(timer)
  // stopScanMode()
}, 400)
```

---

## API 文档

### showCamera(options?)

打开并显示相机窗口。

```typescript
showCamera(options?: CameraOptions): void
```

#### CameraOptions 参数：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `width` | `number` | 屏幕宽度 | 相机窗口宽度（dp） |
| `height` | `number` | 屏幕高度 | 相机窗口高度（dp） |
| `top` | `number` | `0` | 窗口距屏幕顶部的距离（dp） |
| `left` | `number` | `0` | 窗口距屏幕左侧的距离（dp） |
| `cameraFacing` | `'front' \| 'back'` | `'back'` | 初始摄像头方向（前置 / 后置） |
| `views` | `View[]` | — | 初始叠加的视图元素数组 |
| `scanBar` | `ScanBarOptions` | — | 初始扫描条配置 |
| `success` | `(res: CameraOpenSuccessResult) => void` | — | 相机打开成功回调 |
| `fail` | `(res: CameraOpenFailResult) => void` | — | 相机打开失败回调 |
| `complete` | `(res: any) => void` | — | 完成回调（无论成功或失败均触发） |

#### CameraOpenSuccessResult 返回值：

| 属性 | 类型 | 说明 |
|------|------|------|
| `cameraFacing` | `'front' \| 'back'` | 当前实际启用的摄像头 |

#### CameraOpenFailResult 返回值：

| 属性 | 类型 | 说明 |
|------|------|------|
| `errCode` | `number` | 错误码：`1`=权限被拒绝，`2`=相机设备被占用/无法打开，`3`=未知异常 |
| `errMsg` | `string` | 详细错误说明 |

---

### closeCamera()

关闭相机窗口并完全释放双端原生资源（预览层、会话、相机句柄与定时器）。

```typescript
closeCamera(): void
```

---

### takePicture(callback)

拍照。回调返回照片保存至应用缓存目录的本地绝对文件路径。

```typescript
takePicture(callback: (path: string) => void): void
```

> **裁剪与合成规则**：
> 1. 拍照结果会自动按照相机窗口的宽高比居中裁剪，确保所见即所得；
> 2. 标记了 `watermark: true` 的所有视图元素会按当前样式合成至照片中；
> 3. 前置摄像头会自动做镜像校正。

---

### enableTapToFocus() / disableTapToFocus()

开启或关闭点击对焦功能。开启后用户点击相机画面任意区域即可重新对焦，并在点击处展示白色方形聚焦框动效。

```typescript
enableTapToFocus(): void
disableTapToFocus(): void
```

---

### addView(viewConfig)

在相机画面上添加单个叠加视图元素（文本或图片）。

```typescript
addView(viewConfig: View): void
```

#### View 参数：

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| `uid` | `string` | 否 | 元素唯一标识，用于后续精准更新或移除 |
| `type` | `'text' \| 'image'` | 是 | 视图类型 |
| `text` | `string` | 否 | 文本内容（`type === 'text'` 时使用） |
| `image` | `string` | 否 | 图片本地路径或 HTTP/HTTPS URL（`type === 'image'` 时使用） |
| `watermark` | `boolean` | 否 | 是否作为水印，`true` 时会合成进拍照结果。默认 `false` |
| `style` | `ViewStyle` | 否 | 样式配置 |

#### ViewStyle 参数：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `top` | `number` | `0` | 距窗口顶部的距离（dp） |
| `left` | `number` | `0` | 距窗口左侧的距离（dp），仅对图片生效 |
| `fontSize` | `number` | `14` | 字体大小（dp），仅对文本生效 |
| `fontColor` | `string` | `'#FFFFFF'` | 字体颜色（十六进制颜色代码，如 `'#FFFFFF'`） |
| `fontStyle` | `'normal' \| 'italic'` | `'normal'` | 字体样式 |
| `fontWeight` | `string` | `'normal'` | 字体粗细：`'normal'` \| `'bold'` \| `'100'`~`'900'` |
| `textAlign` | `'left' \| 'center' \| 'right'` | `'left'` | 文本水平对齐方式 |
| `textOffset` | `number` | `0` | 水平方向对齐偏移量（dp） |
| `width` | `number` | — | 图片宽度（dp），仅对图片生效 |
| `height` | `number` | — | 图片高度（dp），仅对图片生效 |
| `rotation` | `'top' \| 'right' \| 'bottom' \| 'left'` | `'top'` | 旋转方向：`top`(0°) / `right`(90°) / `bottom`(180°) / `left`(270°)。位置与对齐方式以旋转后的坐标系为准 |

---

### updateView(uid, viewConfig)

根据 `uid` 更新指定叠加元素的内容与样式。

```typescript
updateView(uid: string, viewConfig: View): void
```

---

### removeView(uid)

根据 `uid` 移除指定叠加元素。

```typescript
removeView(uid: string): void
```

---

### updateViews(views)

清空现有的全部叠加元素，并重设为新的视图数组。

```typescript
updateViews(views: View[]): void
```

---

### clearViews()

清空所有叠加视图元素（相机预览层与扫描条动画保持不变）。

```typescript
clearViews(): void
```

---

### switchCamera()

在运行时切换前置 / 后置摄像头。

```typescript
switchCamera(): void
```

---

### startScanMode() / stopScanMode()

启动或停止扫码帧捕获模式。必须在相机显示成功后调用。

```typescript
startScanMode(): boolean  // 返回是否启动成功
stopScanMode(): boolean   // 返回是否停止成功
```

---

### getScanFrame(quality?)

同步获取当前最新的一帧图像数据，返回 JPEG Base64 字符串（不含 `data:image/jpeg;base64,` 前缀）。

```typescript
getScanFrame(quality?: number): string | null
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `quality` | `number` | `85` | JPEG 压缩质量（1-100），推荐 75-85 |

---

### isScanModeActive()

查询扫码模式当前是否正在运行中。

```typescript
isScanModeActive(): boolean
```

---

### showScanBar(options) / hideScanBar()

动态显示或隐藏扫描条动画。

```typescript
showScanBar(options: ScanBarOptions): void
hideScanBar(): void
```

#### ScanBarOptions 参数：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `image` | `string` | — | 扫描条图片路径或 URL（必填） |
| `widthPercent` | `number` | `80` | 扫描条宽度占相机窗口宽度的百分比（0-100） |
| `startY` | `number` | `30` | 扫描条起始 Y 位置（dp） |
| `endY` | `number` | — | 扫描条终止 Y 位置（dp），需大于 `startY` |

---

## 典型应用场景示例

### 场景一：全屏相机 + 点击对焦 + 水印拍照 + 上传

```javascript
import { showCamera, enableTapToFocus, addView, takePicture, closeCamera } from '@/uni_modules/camera-view'

// 1. 打开相机
showCamera({
  cameraFacing: 'back',
  success: () => {
    // 2. 开启点击对焦
    enableTapToFocus()

    // 3. 叠加工程水印
    addView({
      uid: 'project-tag',
      type: 'text',
      text: '工程项目验收',
      watermark: true,
      style: { top: 20, fontColor: '#FFFFFF', fontWeight: 'bold', textAlign: 'center', fontSize: 18 }
    })
    addView({
      uid: 'time-tag',
      type: 'text',
      text: new Date().toLocaleString(),
      watermark: true,
      style: { top: 48, fontColor: '#FFD700', textAlign: 'right', textOffset: 12, fontSize: 13 }
    })
  }
})

// 4. 拍照并直传
function onCapture() {
  takePicture((path) => {
    if (path) {
      uni.uploadFile({
        url: 'https://api.example.com/photos',
        filePath: path.startsWith('file://') ? path : 'file://' + path,
        name: 'photo',
        formData: { tag: 'acceptance' },
        success: (res) => console.log('上传成功', res.data)
      })
    }
  })
}
```

### 场景二：集成 `scan-photo` 组件（扫码与拍照双 Tab）

插件内置了开箱即用的 UI 组件 `scan-photo.vue`：

```vue
<template>
  <view class="container">
    <scanPhoto
      @scan-mode="onScanFrame"
      @take-picture="onTakePicture"
    />
  </view>
</template>

<script setup>
import scanPhoto from '@/uni_modules/camera-view/components/scan-photo.vue'

function onScanFrame(base64) {
  // 接收到扫码帧数据，送入条码/二维码解析算法
}

function onTakePicture(path) {
  // 接收到拍照文件路径
  console.log('拍摄照片路径：', path)
}
</script>
```

---

## 最佳实践与注意事项

1. **拍照上传规范（无需 `uni.chooseMedia`）**：
   `takePicture` 回调返回的已是设备本地可读写缓存文件的绝对路径，直接传入 `uni.uploadFile` 即可。**切勿调用 `uni.chooseMedia` 或 `uni.chooseImage` 去二次封装**，否则在未声明 Camera 模块的基座中会触发「未添加模块」打包报错。
2. **时序调用建议**：
   - `enableTapToFocus`、`startScanMode`、`takePicture` 等方法需在 `showCamera` 成功启动后调用；
   - `startScanMode` 建议在相机打开后延迟 300-400ms 执行，等待硬件传感器完成曝光与测光初始化。
3. **iOS 权限配置**：
   iOS 系统对权限要求极高，若未在 `Info.plist` 中配置 `NSCameraUsageDescription`，调用相机将直接导致 App 闪退退出。请务必核对 `manifest.json` 的 iOS 分发配置。
4. **内存与资源回收**：
   在 Vue 页面的 `onUnload` 或 `onHide` 钩子中，请确保调用 `closeCamera()` 或 `stopScanMode()`，避免原生相机句柄长期占用造成功耗升高。

---

## 常见问题排查

**Q：为什么 iOS 点击打开相机应用直接闪退？**  
A：这是典型的缺少 `NSCameraUsageDescription` 权限描述导致。请检查 `manifest.json` 中是否配置了 `plistcmds` 或检查打基座时是否包含 `app-ios/Info.plist`。

**Q：拍照后使用 `uni.uploadFile` 上传报错？**  
A：检查文件路径前缀。部分平台返回的路径需补齐 `file://` 协议头；本插件已做规范化处理，建议使用 `path.startsWith('file://') ? path : 'file://' + path`。

**Q：`getScanFrame` 刚启动时返回 `null`？**  
A：相机启动后底层驱动输出第一帧需要数毫秒就绪时间，首次调用返回 `null` 属于正常现象，重试或定时循环抓帧即可。

---

## 版本信息

- **当前版本**：v1.1.0
- **最低 HBuilderX 版本**：4.0.0
- **最低 uni-app / uni-app X 版本**：3.1.0
- **Android 最低版本**：Android 5.0（API Level 21）
- **iOS 最低版本**：iOS 12.0+
