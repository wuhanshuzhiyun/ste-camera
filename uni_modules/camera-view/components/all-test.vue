<template>
	<view class="demo-page">
		<scroll-view class="methods" scroll-y>
			<!-- ===== 顶部标题 ===== -->
			<view class="header">
				<text class="header-title">camera-view 插件功能测试</text>
				<text class="header-sub">v1.1.0 · Android</text>
			</view>

			<!-- ===== 状态栏 ===== -->
			<view class="status-bar">
				<view class="status-item">
					<view :class="['status-dot', cameraVisible ? 'dot-green' : 'dot-gray']"></view>
					<text class="status-label">相机：{{ cameraVisible ? '运行中' : '已关闭' }}</text>
				</view>
				<view class="status-item">
					<view :class="['status-dot', scanActive ? 'dot-blue' : 'dot-gray']"></view>
					<text class="status-label">扫码模式：{{ scanActive ? '运行中' : '已停止' }}</text>
				</view>
				<view class="status-item">
					<text class="status-label">当前镜头：{{ cameraFacing === 'front' ? '前置' : '后置' }}</text>
				</view>
			</view>

			<!-- ===== 功能分组：基础控制 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">📷</text>
					<text>基础控制</text>
				</view>
				<view class="btn-row">
					<button class="btn btn-primary" @click="onShowCamera">显示相机</button>
					<button class="btn btn-danger" @click="onCloseCamera">关闭相机</button>
					<button class="btn btn-warning" @click="onSwitchCamera">切换镜头</button>
				</view>
				<view class="btn-row">
					<button class="btn btn-primary" @click="onShowFrontCamera">前置相机</button>
					<button class="btn btn-primary" @click="onShowBackCamera">后置相机</button>
					<button class="btn btn-default" @click="onShowSmallCamera">小窗模式</button>
				</view>
			</view>

			<!-- ===== 功能分组：拍照 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">🤳</text>
					<text>拍照功能</text>
				</view>
				<view class="btn-row">
					<button class="btn btn-success" @click="onTakePicture">拍照</button>
					<button class="btn btn-default" @click="onTakeWithWatermark">带水印拍照</button>
					<button v-if="lastPhoto" class="btn btn-default" @click="clearPhoto">清除预览</button>
				</view>
				<!-- 拍照结果预览 -->
				<view v-if="lastPhoto" class="photo-preview">
					<text class="preview-label">最新拍照结果：</text>
					<image :src="lastPhoto" mode="widthFix" class="preview-image" @click="previewFullPhoto" />
					<text class="preview-path">{{ lastPhotoPath }}</text>
				</view>
			</view>

			<!-- ===== 功能分组：视图叠加层管理 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">🎨</text>
					<text>视图叠加层管理</text>
				</view>
				<!-- 文本视图 -->
				<view class="sub-section">
					<text class="sub-title">文本视图</text>
					<view class="input-row">
						<text class="input-label">文本内容：</text>
						<input v-model="textContent" class="input-field" placeholder="输入要叠加的文字" />
					</view>
					<view class="input-row">
						<text class="input-label">颜色：</text>
						<view class="color-options">
							<view
								v-for="color in colorOptions"
								:key="color.value"
								:class="['color-dot', textColor === color.value ? 'color-dot-active' : '']"
								:style="{ backgroundColor: color.value }"
								@click="textColor = color.value"
							></view>
						</view>
					</view>
					<view class="input-row">
						<text class="input-label">对齐：</text>
						<view class="align-options">
							<text
								v-for="align in ['left', 'center', 'right']"
								:key="align"
								:class="['align-btn', textAlign === align ? 'align-btn-active' : '']"
								@click="textAlign = align"
							>
								{{ align }}
							</text>
						</view>
					</view>
					<view class="btn-row">
						<button class="btn btn-primary" @click="onAddTextView">添加文本</button>
						<button class="btn btn-warning" @click="onAddWatermarkText">添加文本水印</button>
						<button class="btn btn-default" @click="onAddItalicText">斜体文本</button>
					</view>
				</view>

				<!-- 图片视图 -->
				<view class="sub-section">
					<text class="sub-title">图片视图</text>
					<view class="btn-row">
						<button class="btn btn-primary" @click="onAddImageView">添加图片</button>
						<button class="btn btn-warning" @click="onAddWatermarkImage">图片水印</button>
						<button class="btn btn-default" @click="onAddCornerImage">右上角图片</button>
					</view>
				</view>

				<!-- 旋转视图 -->
				<view class="sub-section">
					<text class="sub-title">旋转视图（rotation）</text>
					<view class="btn-row">
						<button class="btn btn-primary" @click="onAddRotationTop">top (0°)</button>
						<button class="btn btn-primary" @click="onAddRotationRight">right (90°)</button>
					</view>
					<view class="btn-row">
						<button class="btn btn-primary" @click="onAddRotationBottom">bottom (180°)</button>
						<button class="btn btn-primary" @click="onAddRotationLeft">left (270°)</button>
					</view>
					<view class="btn-row">
						<button class="btn btn-default" @click="onAddRotationAllDirections">四方向同时测试</button>
						<button class="btn btn-danger" @click="onClearViews">清除</button>
					</view>
				</view>

				<!-- 批量视图管理 -->
				<view class="sub-section">
					<text class="sub-title">批量管理</text>
					<view class="btn-row">
						<button class="btn btn-primary" @click="onUpdateViews">重设所有视图</button>
						<button class="btn btn-danger" @click="onClearViews">清除所有视图</button>
					</view>
					<view class="btn-row">
						<button class="btn btn-default" @click="onUpdateSpecificView">更新指定视图</button>
						<button class="btn btn-default" @click="onRemoveSpecificView">移除指定视图</button>
					</view>
				</view>

				<!-- UID 追踪测试 -->
				<view class="sub-section">
					<text class="sub-title">UID 追踪测试</text>
					<view class="uid-list">
						<view v-for="(item, idx) in trackedViews" :key="item.uid" class="uid-item">
							<text class="uid-text">{{ item.uid }}: {{ item.desc }}</text>
							<view class="uid-actions">
								<text class="uid-btn" @click="onUpdateTracked(item)">改</text>
								<text class="uid-btn uid-btn-danger" @click="onRemoveTracked(item)">删</text>
							</view>
						</view>
						<text v-if="trackedViews.length === 0" class="uid-empty">暂无追踪视图</text>
					</view>
					<view class="btn-row">
						<button class="btn btn-primary" @click="onAddTrackedView">添加追踪视图</button>
						<button class="btn btn-default" @click="trackedViews = []">清空列表</button>
					</view>
				</view>
			</view>

			<!-- ===== 功能分组：扫码模式 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">📱</text>
					<text>扫码模式（帧获取）</text>
				</view>
				<view class="scan-desc">
					<text class="desc-text">扫码模式会持续捕获摄像头帧，返回 Base64 JPEG 数据，可用于二维码识别等场景</text>
				</view>
				<view class="btn-row">
					<button class="btn btn-success" @click="onStartScanMode" :disabled="scanActive">启动扫码</button>
					<button class="btn btn-danger" @click="onStopScanMode" :disabled="!scanActive">停止扫码</button>
					<button class="btn btn-default" @click="onCheckScanStatus">查询状态</button>
				</view>
				<view class="btn-row">
					<button class="btn btn-primary" @click="onGetSingleFrame" :disabled="!scanActive">获取单帧</button>
					<button class="btn btn-primary" @click="onStartAutoCapture" :disabled="!scanActive || autoCaptureRunning">自动抓帧</button>
					<button class="btn btn-warning" @click="onStopAutoCapture" :disabled="!autoCaptureRunning">停止抓帧</button>
				</view>

				<!-- quality 滑动条 -->
				<view class="quality-row">
					<text class="quality-label">压缩质量：{{ frameQuality }}</text>
					<slider :value="frameQuality" min="10" max="100" step="5" @change="frameQuality = $event.detail.value" class="quality-slider" />
				</view>

				<!-- 帧预览 -->
				<view v-if="scanFrameBase64" class="scan-frame-preview">
					<text class="preview-label">最新帧预览（Base64）：</text>
					<image :src="'data:image/jpeg;base64,' + scanFrameBase64" mode="widthFix" class="scan-frame-image" />
					<text class="frame-info">帧大小：{{ frameSize }}</text>
					<text class="frame-info">抓取次数：{{ frameCaptureCount }}</text>
				</view>
			</view>

			<!-- ===== 功能分组：扫描条配置 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">🔍</text>
					<text>扫描条动画</text>
				</view>
				<view class="scan-desc">
					<text class="desc-text">开启扫码模式时可显示从上到下的扫描条动画，扫描条为图片，支持自定义宽度、起止位置</text>
				</view>

				<!-- 扫描条开关 -->
				<view class="input-row">
					<text class="input-label">显示扫描条：</text>
					<switch :checked="scanBarShow" @change="scanBarShow = $event.detail.value" />
				</view>

				<!-- 扫描条图片 URL -->
				<view class="input-row">
					<text class="input-label">图片URL：</text>
					<input v-model="scanBarImage" class="input-field" placeholder="扫描条图片路径或URL" />
				</view>

				<!-- 宽度百分比 -->
				<view class="quality-row">
					<text class="quality-label">宽度：{{ scanBarWidthPercent }}%</text>
					<slider :value="scanBarWidthPercent" min="10" max="100" step="5" @change="scanBarWidthPercent = $event.detail.value" class="quality-slider" />
				</view>

				<!-- 开始位置 -->
				<view class="quality-row">
					<text class="quality-label">起始Y（dp）：{{ scanBarStartY }}</text>
					<slider :value="scanBarStartY" min="0" max="100" step="5" @change="scanBarStartY = $event.detail.value" class="quality-slider" />
				</view>

				<!-- 结束位置 -->
				<view class="quality-row">
					<text class="quality-label">结束Y（dp）：{{ scanBarEndY }}</text>
					<slider :value="scanBarEndY" min="0" max="100" step="5" @change="scanBarEndY = $event.detail.value" class="quality-slider" />
				</view>

				<view class="btn-row">
					<button class="btn btn-primary" @click="onShowCameraWithScanBar">打开相机（含扫描条）</button>
				</view>
			</view>

			<!-- ===== 功能分组：组合场景测试 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">🧪</text>
					<text>组合场景测试</text>
				</view>
				<view class="btn-row">
					<button class="btn btn-primary" @click="onSceneWatermarkPhoto">水印拍照场景</button>
					<button class="btn btn-primary" @click="onSceneScanAndCapture">扫码抓帧场景</button>
				</view>
				<view class="btn-row">
					<button class="btn btn-default" @click="onSceneMultiLayer">多图层叠加</button>
					<button class="btn btn-default" @click="onSceneFrontSelfie">前置自拍</button>
				</view>
			</view>

			<!-- ===== 日志区域 ===== -->
			<view class="section">
				<view class="section-title">
					<text class="section-icon">📋</text>
					<text>操作日志</text>
					<text class="log-clear" @click="logs = []">清空</text>
				</view>
				<scroll-view scroll-y class="log-scroll" :scroll-top="logScrollTop">
					<view v-for="(log, idx) in logs" :key="idx" class="log-item">
						<text :class="['log-time']">{{ log.time }}</text>
						<text :class="['log-msg', log.type === 'error' ? 'log-error' : log.type === 'success' ? 'log-success' : log.type === 'warn' ? 'log-warn' : '']">
							{{ log.msg }}
						</text>
					</view>
					<view v-if="logs.length === 0" class="log-empty">
						<text>暂无日志</text>
					</view>
				</scroll-view>
			</view>

			<!-- 底部安全区 -->
			<view class="safe-bottom"></view>
		</scroll-view>
	</view>
</template>

<script setup>
import { ref, reactive, nextTick, onMounted, onUnmounted } from 'vue';
import {
	showCamera,
	closeCamera,
	takePicture,
	updateViews,
	addView,
	updateView,
	removeView,
	clearViews,
	switchCamera,
	startScanMode,
	stopScanMode,
	getScanFrame,
	isScanModeActive
} from '@/uni_modules/camera-view';

// ===== 状态 =====
const cameraVisible = ref(false);
const scanActive = ref(false);
const cameraFacing = ref('back');
const lastPhoto = ref('');
const lastPhotoPath = ref('');

// 文本配置
const textContent = ref('相机叠加层');
const textColor = ref('#FFFFFF');
const textAlign = ref('center');

// 扫码
const frameQuality = ref(85);
const scanFrameBase64 = ref('');
const frameSize = ref('--');
const frameCaptureCount = ref(0);
const autoCaptureRunning = ref(false);
let autoCaptureTimer = null;

// 扫描条配置
const scanBarShow = ref(true);
const scanBarImage = ref('https://image.whzb.com/chain/inte-mall/00-普通图片/00-开发版/通用/扫码图片.png');
const scanBarWidthPercent = ref(80);
const scanBarStartY = ref(30);
// endY 为距顶部距离（dp），需大于 startY，默认 350dp（约接近底部）
const scanBarEndY = ref(350);

// UID 追踪
const trackedViews = ref([]);
let uidCounter = 1;

// 日志
const logs = ref([]);
const logScrollTop = ref(0);

// 颜色选项
const colorOptions = [
	{
		value: '#FFFFFF'
	},
	{
		value: '#FF0000'
	},
	{
		value: '#00FF00'
	},
	{
		value: '#FFFF00'
	},
	{
		value: '#00BFFF'
	},
	{
		value: '#FF69B4'
	}
];

// ===== 日志工具 =====
function log(msg, type = 'info') {
	const now = new Date();
	const time = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`;
	logs.value.unshift({
		time,
		msg,
		type
	});
	if (logs.value.length > 50) logs.value.pop();
}

// ===== 基础控制 =====

/**
 * 显示相机（全屏，后置，带示例水印）
 */
const onShowCamera = async () => {
	if (cameraVisible.value) {
		log('相机已在运行中', 'warn');
		uni.showToast({
			title: '相机已运行',
			icon: 'none'
		});
		return;
	}
	try {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		console.log('111111111111111111');
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.6),
			top: 0,
			left: 0,
			cameraFacing: 'back',
			views: [
				{
					type: 'text',
					text: 'camera-view Demo',
					watermark: false,
					style: {
						top: 20,
						fontColor: '#FFFFFF',
						fontWeight: 'bold',
						textAlign: 'center',
						fontSize: 18
					}
				}
			],
			success: () => {
				console.log('2222222222222222');
				cameraVisible.value = true;
				cameraFacing.value = 'back';
				log('相机已显示（全屏60%高，后置）', 'success');
			},
			fail: (e) => {
				console.log('3333333333', e);
			},
			complete: (res) => {
				console.log('44444', res);
			}
		});
	} catch (e) {
		log('显示相机失败：' + e.message, 'error');
	}
};

/**
 * 前置相机
 */
const onShowFrontCamera = async () => {
	if (cameraVisible.value) {
		onCloseCamera();
		await new Promise((r) => setTimeout(r, 300));
	}
	try {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.55),
			top: 0,
			left: 0,
			cameraFacing: 'front',
			views: [
				{
					type: 'text',
					text: '前置摄像头',
					watermark: false,
					style: {
						top: 16,
						fontColor: '#FFFF00',
						fontWeight: 'bold',
						textAlign: 'center',
						fontSize: 16
					}
				}
			],
			success: () => {
				cameraVisible.value = true;
				cameraFacing.value = 'front';
				log('相机已显示（前置）', 'success');
			}
		});
	} catch (e) {
		log('显示前置相机失败：' + e.message, 'error');
	}
};

/**
 * 后置相机
 */
const onShowBackCamera = async () => {
	if (cameraVisible.value) {
		onCloseCamera();
		await new Promise((r) => setTimeout(r, 300));
	}
	try {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.55),
			top: 0,
			left: 0,
			cameraFacing: 'back',
			success: () => {
				cameraVisible.value = true;
				cameraFacing.value = 'back';
				log('相机已显示（后置）', 'success');
			}
		});
	} catch (e) {
		log('显示后置相机失败：' + e.message, 'error');
	}
};

/**
 * 小窗模式（右上角，宽200dp，高300dp）
 */
const onShowSmallCamera = async () => {
	if (cameraVisible.value) {
		log('请先关闭当前相机', 'warn');
		uni.showToast({
			title: '请先关闭相机',
			icon: 'none'
		});
		return;
	}
	try {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: 150,
			height: 200,
			top: 60,
			left: windowWidth - 160,
			cameraFacing: 'back',
			views: [
				{
					type: 'text',
					text: '小窗',
					watermark: false,
					style: {
						top: 8,
						fontColor: '#FFFFFF',
						fontSize: 12,
						textAlign: 'center'
					}
				}
			],
			success: () => {
				cameraVisible.value = true;
				cameraFacing.value = 'back';
				log('小窗相机已显示（右下角 200×280dp）', 'success');
			}
		});
	} catch (e) {
		log('显示小窗失败：' + e.message, 'error');
	}
};

/**
 * 关闭相机
 */
const onCloseCamera = () => {
	// 同时停止扫码模式
	if (scanActive.value) {
		onStopScanMode();
	}
	if (autoCaptureRunning.value) {
		onStopAutoCapture();
	}
	closeCamera();
	cameraVisible.value = false;
	log('相机已关闭', 'info');
};

/**
 * 切换前后摄像头
 */
const onSwitchCamera = () => {
	if (!cameraVisible.value) {
		log('相机未开启，无法切换', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	switchCamera();
	cameraFacing.value = cameraFacing.value === 'back' ? 'front' : 'back';
	log(`已切换到${cameraFacing.value === 'front' ? '前置' : '后置'}摄像头`, 'success');
};

// ===== 拍照 =====

const onTakePicture = () => {
	if (!cameraVisible.value) {
		log('相机未开启，无法拍照', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	log('正在拍照...');
	takePicture((path) => {
		if (path) {
			const filePath = path.startsWith('file://') ? path : 'file://' + path;
			lastPhoto.value = filePath;
			lastPhotoPath.value = path;
			log('拍照成功：' + path.split('/').pop(), 'success');
			uni.showToast({
				title: '拍照成功',
				icon: 'success'
			});
		} else {
			log('拍照失败（回调返回 null）', 'error');
			uni.showToast({
				title: '拍照失败',
				icon: 'none'
			});
		}
	});
};

/**
 * 先添加水印再拍照
 */
const onTakeWithWatermark = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	// 先更新水印
	updateViews([
		{
			type: 'text',
			text: `水印 ${new Date().toLocaleTimeString()}`,
			watermark: true,
			style: {
				top: 30,
				fontColor: '#FF4444',
				fontWeight: 'bold',
				textAlign: 'center',
				fontSize: 20
			}
		},
		{
			type: 'text',
			text: '© camera-view plugin',
			watermark: true,
			style: {
				top: 60,
				fontColor: '#FFFFFF',
				textAlign: 'right',
				textOffset: 16,
				fontSize: 14
			}
		}
	]);
	log('已设置文字水印，开始拍照...');
	// 稍等一下让视图更新
	setTimeout(() => {
		takePicture((path) => {
			if (path) {
				const filePath = path.startsWith('file://') ? path : 'file://' + path;
				lastPhoto.value = filePath;
				lastPhotoPath.value = path;
				log('水印拍照成功：' + path.split('/').pop(), 'success');
				uni.showToast({
					title: '水印拍照成功',
					icon: 'success'
				});
			} else {
				log('水印拍照失败', 'error');
			}
		});
	}, 300);
};

const clearPhoto = () => {
	lastPhoto.value = '';
	lastPhotoPath.value = '';
};

const previewFullPhoto = () => {
	if (lastPhoto.value) {
		uni.previewImage({
			urls: [lastPhoto.value],
			current: lastPhoto.value
		});
	}
};

// ===== 视图管理 =====

const onAddTextView = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	const t = textContent.value || '叠加文本';
	addView({
		type: 'text',
		text: t,
		watermark: false,
		style: {
			top: 80 + Math.floor(Math.random() * 100),
			fontColor: textColor.value,
			fontWeight: 'normal',
			textAlign: textAlign.value,
			fontSize: 18
		}
	});
	log(`添加文本视图："${t}"（${textAlign.value} ${textColor.value}）`, 'success');
};

const onAddWatermarkText = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	addView({
		type: 'text',
		text: `水印 ${new Date().getHours()}:${new Date().getMinutes()}`,
		watermark: true,
		style: {
			top: 20,
			fontColor: '#FFDD00',
			fontWeight: 'bold',
			textAlign: 'left',
			textOffset: 12,
			fontSize: 16
		}
	});
	log('添加文本水印（会印在照片上）', 'success');
};

const onAddItalicText = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	addView({
		type: 'text',
		text: '斜体 italic',
		watermark: false,
		style: {
			top: 140,
			fontColor: '#00FFCC',
			fontStyle: 'italic',
			fontWeight: 'bold',
			textAlign: 'center',
			fontSize: 22
		}
	});
	log('添加斜体文本视图', 'success');
};

// ===== 旋转视图测试 =====

/** rotation=0 top：顶部朝上，top=距顶，textAlign 正常 */
const onAddRotationTop = () => {
	if (!cameraVisible.value) { log('相机未开启', 'warn'); return; }
	addView({
		type: 'text',
		text: '↑ top (0°)',
		watermark: false,
		style: {
			top: 20,
			fontColor: '#FFFFFF',
			fontWeight: 'bold',
			textAlign: 'center',
			fontSize: 18,
			rotation: 'top'
		}
	});
	log('添加旋转视图 rotation="top"（0°）', 'success');
};

/** rotation="right"：顶部朝右，top=距右侧 */
const onAddRotationRight = () => {
	if (!cameraVisible.value) { log('相机未开启', 'warn'); return; }
	addView({
		type: 'text',
		text: '→ right (90°)',
		watermark: false,
		style: {
			top: 20,
			fontColor: '#FFD700',
			fontWeight: 'bold',
			textAlign: 'center',
			fontSize: 18,
			rotation: 'right'
		}
	});
	log('添加旋转视图 rotation="right"（90°），top=距右侧20dp，textAlign=left→靠近顶部', 'success');
};

/** rotation="bottom"：顶部朝下，top=距底部 */
const onAddRotationBottom = () => {
	if (!cameraVisible.value) { log('相机未开启', 'warn'); return; }
	addView({
		type: 'text',
		text: '↓ bottom (180°)',
		watermark: false,
		style: {
			top: 20,
			fontColor: '#FF6B6B',
			fontWeight: 'bold',
			textAlign: 'center',
			fontSize: 18,
			rotation: 'bottom'
		}
	});
	log('添加旋转视图 rotation="bottom"（180°），top=距底部20dp', 'success');
};

/** rotation="left"：顶部朝左，top=距左侧 */
const onAddRotationLeft = () => {
	if (!cameraVisible.value) { log('相机未开启', 'warn'); return; }
	addView({
		type: 'text',
		text: '← left (270°)',
		watermark: false,
		style: {
			top: 20,
			fontColor: '#00BFFF',
			fontWeight: 'bold',
			textAlign: 'center',
			fontSize: 18,
			rotation: 'left'
		}
	});
	log('添加旋转视图 rotation="left"（270°），top=距左侧20dp，textAlign=left→靠近底部', 'success');
};

/** 四方向同时添加，直观对比 */
const onAddRotationAllDirections = () => {
	if (!cameraVisible.value) { log('相机未开启', 'warn'); return; }
	clearViews();
	// top (0°)：顶部居中，白色
	addView({
		type: 'text',
		text: '↑ top',
		watermark: false,
		style: { top: 0, fontColor: '#FFFFFF', fontWeight: 'bold', textAlign: 'center', fontSize: 16, rotation: 'top' }
	});
	// right (90°)：距右侧16dp，黄色
	addView({
		type: 'text',
		text: '→ right',
		watermark: false,
		style: { top: -20, fontColor: '#FFD700', fontWeight: 'bold', textAlign: 'center', fontSize: 16, rotation: 'right' }
	});
	// bottom (180°)：距底部16dp，红色
	addView({
		type: 'text',
		text: '↓ bottom',
		watermark: false,
		style: { top: 0, fontColor: '#FF6B6B', fontWeight: 'bold', textAlign: 'center', fontSize: 16, rotation: 'bottom' }
	});
	// left (270°)：距左侧16dp，蓝色
	addView({
		type: 'text',
		text: '← left',
		watermark: false,
		style: { top: 0, fontColor: '#00BFFF', fontWeight: 'bold', textAlign: 'center', fontSize: 16, rotation: 'left' }
	});
	log('已添加四方向旋转视图（top白/right黄/bottom红/left蓝）', 'success');
};

const onAddImageView = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	addView({
		type: 'image',
		image: 'https://image.whzb.com/chain/StellarUI/image/08a5aa2f299c47569771bc58c6b50bb4.gif',
		watermark: false,
		style: {
			width: 80,
			height: 80,
			left: Math.floor(Math.random() * 200),
			top: 120
		}
	});
	log('添加图片视图（非水印）', 'success');
};

const onAddWatermarkImage = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	addView({
		type: 'image',
		image: 'https://image.whzb.com/chain/StellarUI/售罄.png',
		watermark: true,
		style: {
			width: 100,
			height: 100,
			left: 20,
			top: 60
		}
	});
	log('添加图片水印（会印在照片上）', 'success');
};

const onAddCornerImage = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	addView({
		type: 'image',
		image: 'https://image.whzb.com/chain/StellarUI/已打印.png',
		watermark: true,
		style: {
			width: 60,
			height: 60,
			left: 260,
			top: 16
		}
	});
	log('添加右上角图片水印', 'success');
};

const onUpdateViews = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	updateViews([
		{
			type: 'text',
			text: '已重设视图 ' + new Date().toLocaleTimeString(),
			watermark: false,
			style: {
				top: 40,
				fontColor: '#FFFFFF',
				fontWeight: 'bold',
				textAlign: 'center',
				fontSize: 18
			}
		},
		{
			type: 'text',
			text: '第二行文字',
			watermark: true,
			style: {
				top: 70,
				fontColor: '#FFD700',
				textAlign: 'left',
				textOffset: 10,
				fontSize: 14
			}
		}
	]);
	trackedViews.value = [];
	log('已重设所有视图（updateViews）', 'success');
};

const onClearViews = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		return;
	}
	clearViews();
	trackedViews.value = [];
	log('已清除所有视图', 'info');
};

// UID 追踪功能
const onAddTrackedView = () => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	const uid = `view_${uidCounter++}`;
	const topPos = 50 + trackedViews.value.length * 35;
	addView({
		uid,
		type: 'text',
		text: `[${uid}] 追踪视图`,
		watermark: false,
		style: {
			top: topPos,
			fontColor: '#00FFCC',
			fontWeight: 'bold',
			textAlign: 'left',
			textOffset: 10,
			fontSize: 16
		}
	});
	trackedViews.value.push({
		uid,
		desc: `文本@top${topPos}`
	});
	log(`添加追踪视图 uid=${uid}`, 'success');
};

const onUpdateTracked = (item) => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		return;
	}
	updateView(item.uid, {
		type: 'text',
		text: `[${item.uid}] 已更新 ${new Date().getSeconds()}s`,
		watermark: false,
		style: {
			top: Math.floor(Math.random() * 150) + 30,
			fontColor: '#FF9900',
			fontWeight: 'bold',
			textAlign: 'center',
			fontSize: 16
		}
	});
	item.desc = '已更新';
	log(`更新视图 uid=${item.uid}`, 'success');
};

const onRemoveTracked = (item) => {
	if (!cameraVisible.value) {
		log('相机未开启', 'warn');
		return;
	}
	removeView(item.uid);
	trackedViews.value = trackedViews.value.filter((v) => v.uid !== item.uid);
	log(`移除视图 uid=${item.uid}`, 'info');
};

const onUpdateSpecificView = () => {
	if (trackedViews.value.length === 0) {
		log('没有追踪中的视图，请先添加', 'warn');
		uni.showToast({
			title: '请先添加追踪视图',
			icon: 'none'
		});
		return;
	}
	onUpdateTracked(trackedViews.value[0]);
};

const onRemoveSpecificView = () => {
	if (trackedViews.value.length === 0) {
		log('没有追踪中的视图', 'warn');
		uni.showToast({
			title: '请先添加追踪视图',
			icon: 'none'
		});
		return;
	}
	onRemoveTracked(trackedViews.value[0]);
};

// ===== 扫码模式 =====

const onStartScanMode = () => {
	if (!cameraVisible.value) {
		log('请先打开相机', 'warn');
		uni.showToast({
			title: '请先打开相机',
			icon: 'none'
		});
		return;
	}
	const result = startScanMode();
	scanActive.value = result;
	if (result) {
		log('扫码模式已启动', 'success');
		uni.showToast({
			title: '扫码模式启动',
			icon: 'success'
		});
	} else {
		log('扫码模式启动失败（相机未就绪？）', 'error');
	}
};

const onStopScanMode = () => {
	if (autoCaptureRunning.value) onStopAutoCapture();
	const result = stopScanMode();
	scanActive.value = false;
	scanFrameBase64.value = '';
	log(`扫码模式已停止（result=${result}）`, 'info');
};

const onCheckScanStatus = () => {
	const active = isScanModeActive();
	scanActive.value = active;
	log(`扫码模式状态：${active ? '运行中' : '已停止'}`, active ? 'success' : 'info');
	uni.showToast({
		title: `扫码：${active ? '运行中' : '已停止'}`,
		icon: 'none'
	});
};

const onGetSingleFrame = () => {
	if (!scanActive.value) {
		log('扫码模式未启动', 'warn');
		return;
	}
	const frame = getScanFrame(frameQuality.value);
	if (frame) {
		scanFrameBase64.value = frame;
		frameCaptureCount.value++;
		frameSize.value = Math.round(frame.length / 1024) + ' KB (base64)';
		log(`获取单帧成功，大小 ${frameSize.value}，quality=${frameQuality.value}`, 'success');
	} else {
		log('获取帧失败（帧数据为 null，相机可能刚启动）', 'warn');
	}
};

const onStartAutoCapture = () => {
	if (!scanActive.value) {
		log('扫码模式未启动', 'warn');
		return;
	}
	autoCaptureRunning.value = true;
	frameCaptureCount.value = 0;
	log('开始自动抓帧（每500ms）', 'info');
	autoCaptureTimer = setInterval(() => {
		if (!isScanModeActive()) {
			onStopAutoCapture();
			return;
		}
		const frame = getScanFrame(frameQuality.value);
		if (frame) {
			scanFrameBase64.value = frame;
			frameCaptureCount.value++;
			frameSize.value = Math.round(frame.length / 1024) + ' KB';
		}
	}, 500);
};

const onStopAutoCapture = () => {
	if (autoCaptureTimer) {
		clearInterval(autoCaptureTimer);
		autoCaptureTimer = null;
	}
	autoCaptureRunning.value = false;
	log(`自动抓帧已停止，共抓取 ${frameCaptureCount.value} 帧`, 'info');
};

/**
 * 打开相机，并携带扫描条配置
 */
const onShowCameraWithScanBar = async () => {
	if (cameraVisible.value) {
		onCloseCamera();
		await new Promise((r) => setTimeout(r, 300));
	}
	try {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.6),
			top: 0,
			left: 0,
			cameraFacing: 'back',
			scanBar: scanBarShow.value
				? {
						image: scanBarImage.value,
						widthPercent: scanBarWidthPercent.value,
						startY: scanBarStartY.value,
						endY: scanBarEndY.value
				  }
				: undefined,
			success: () => {
				cameraVisible.value = true;
				cameraFacing.value = 'back';
				log(`相机已显示（含扫描条，宽${scanBarWidthPercent.value}%，startY=${scanBarStartY.value}dp，endY=${scanBarEndY.value}dp）`, 'success');
			}
		});
	} catch (e) {
		log('显示相机（扫描条）失败：' + e.message, 'error');
	}
};

// ===== 组合场景 =====

/**
 * 场景1：带多层水印拍照
 */
const onSceneWatermarkPhoto = async () => {
	log('=== 场景：水印拍照 ===', 'info');
	if (!cameraVisible.value) {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.6),
			top: 0,
			left: 0,
			cameraFacing: 'back',
			success: async () => {
				cameraVisible.value = true;
				await new Promise((r) => setTimeout(r, 500));
				// 设置多层水印
				updateViews([
					{
						type: 'text',
						text: '© Demo 测试水印',
						watermark: true,
						style: {
							top: 20,
							fontColor: '#FFFFFF',
							fontWeight: 'bold',
							textAlign: 'center',
							fontSize: 18
						}
					},
					{
						type: 'text',
						text: new Date().toLocaleString(),
						watermark: true,
						style: {
							top: 50,
							fontColor: '#FFFF00',
							textAlign: 'right',
							textOffset: 10,
							fontSize: 13
						}
					},
					{
						type: 'image',
						image: 'https://image.whzb.com/chain/StellarUI/已打印.png',
						watermark: true,
						style: {
							width: 70,
							height: 70,
							left: 10,
							top: 15
						}
					}
				]);
				log('水印已设置，1秒后拍照', 'info');
				setTimeout(() => {
					takePicture((path) => {
						if (path) {
							const filePath = path.startsWith('file://') ? path : 'file://' + path;
							lastPhoto.value = filePath;
							lastPhotoPath.value = path;
							log('场景拍照成功：' + path.split('/').pop(), 'success');
							uni.showToast({
								title: '拍照成功，查看预览',
								icon: 'success'
							});
						} else {
							log('场景拍照失败', 'error');
						}
					});
				}, 1000);
			}
		});
	}
};

/**
 * 场景2：扫码抓帧场景
 */
const onSceneScanAndCapture = async () => {
	log('=== 场景：扫码抓帧 ===', 'info');
	if (!cameraVisible.value) {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.5),
			top: 0,
			left: 0,
			cameraFacing: 'back',
			views: [
				{
					type: 'text',
					text: '扫码识别区域',
					watermark: false,
					style: {
						top: 20,
						fontColor: '#00FF00',
						fontWeight: 'bold',
						textAlign: 'center',
						fontSize: 18
					}
				}
			],
			success: async () => {
				cameraVisible.value = true;
				await new Promise((r) => setTimeout(r, 500));
				const started = startScanMode();
				scanActive.value = started;
				if (!started) {
					log('扫码模式启动失败', 'error');
					return;
				}
				log('扫码模式已启动，等待1秒后抓取帧...', 'info');
				setTimeout(() => {
					const frame = getScanFrame(80);
					if (frame) {
						scanFrameBase64.value = frame;
						frameCaptureCount.value++;
						frameSize.value = Math.round(frame.length / 1024) + ' KB';
						log('场景抓帧成功，大小=' + frameSize.value, 'success');
					} else {
						log('场景抓帧失败（等待相机预热中）', 'warn');
					}
				}, 1000);
			}
		});
	}
};

/**
 * 场景3：多图层叠加
 */
const onSceneMultiLayer = async () => {
	log('=== 场景：多图层叠加 ===', 'info');
	if (!cameraVisible.value) {
		const { windowWidth, windowHeight } = await uni.getSystemInfo();
		showCamera({
			width: windowWidth,
			height: Math.floor(windowHeight * 0.55),
			top: 0,
			left: 0,
			success: async () => {
				cameraVisible.value = true;
				await new Promise((r) => setTimeout(r, 400));
				clearViews();
				const layers = [
					{
						type: 'text',
						text: '图层1 - 顶部左对齐',
						watermark: false,
						style: {
							top: 20,
							fontColor: '#FF4444',
							textAlign: 'left',
							textOffset: 10,
							fontSize: 14
						}
					},
					{
						type: 'text',
						text: '图层2 - 居中',
						watermark: false,
						style: {
							top: 50,
							fontColor: '#FFFFFF',
							fontWeight: 'bold',
							textAlign: 'center',
							fontSize: 16
						}
					},
					{
						type: 'text',
						text: '图层3 - 右对齐',
						watermark: true,
						style: {
							top: 80,
							fontColor: '#00FF00',
							textAlign: 'right',
							textOffset: 10,
							fontSize: 14
						}
					},
					{
						type: 'text',
						text: '图层4 - 斜体',
						watermark: false,
						style: {
							top: 110,
							fontColor: '#00BFFF',
							fontStyle: 'italic',
							textAlign: 'center',
							fontSize: 16
						}
					},
					{
						type: 'image',
						image: 'https://image.whzb.com/chain/StellarUI/已打印.png',
						watermark: true,
						style: {
							width: 60,
							height: 60,
							left: 10,
							top: 140
						}
					},
					{
						type: 'image',
						image: 'https://image.whzb.com/chain/StellarUI/售罄.png',
						watermark: true,
						style: {
							width: 60,
							height: 60,
							left: 90,
							top: 140
						}
					}
				];
				layers.forEach((layer, i) => {
					setTimeout(() => addView(layer), i * 100);
				});
				log(`多图层叠加：共 ${layers.length} 个图层`, 'success');
			}
		});
	}
};

/**
 * 场景4：前置自拍
 */
const onSceneFrontSelfie = async () => {
	log('=== 场景：前置自拍 ===', 'info');
	if (cameraVisible.value) {
		onCloseCamera();
		await new Promise((r) => setTimeout(r, 300));
	}
	const { windowWidth, windowHeight } = await uni.getSystemInfo();
	showCamera({
		width: windowWidth,
		height: Math.floor(windowHeight * 0.6),
		top: 0,
		left: 0,
		cameraFacing: 'front',
		views: [
			{
				type: 'text',
				text: '自拍模式',
				watermark: true,
				style: {
					top: 20,
					fontColor: '#FF69B4',
					fontWeight: 'bold',
					textAlign: 'center',
					fontSize: 20
				}
			}
		],
		success: async () => {
			cameraVisible.value = true;
			cameraFacing.value = 'front';
			log('前置自拍模式已开启', 'success');
			// 3秒后自动拍照
			setTimeout(() => {
				if (cameraVisible.value) {
					log('3秒倒计时结束，自动拍照', 'info');
					takePicture((path) => {
						if (path) {
							const filePath = path.startsWith('file://') ? path : 'file://' + path;
							lastPhoto.value = filePath;
							lastPhotoPath.value = path;
							log('前置自拍成功：' + path.split('/').pop(), 'success');
							uni.showToast({
								title: '自拍成功！',
								icon: 'success'
							});
						} else {
							log('前置自拍失败', 'error');
						}
					});
				}
			}, 3000);
			uni.showToast({
				title: '3秒后自动拍照',
				icon: 'none'
			});
		}
	});
};

// ===== 生命周期 =====

/**
 * 组件挂载时：同步一次扫码模式状态（防止热重载后状态不一致）
 */
onMounted(() => {
	const active = isScanModeActive();
	scanActive.value = active;
});

/**
 * 组件卸载/页面关闭时：停止定时抓帧、停止扫码模式、关闭相机
 */
onUnmounted(() => {
	// 停止自动抓帧定时器
	if (autoCaptureTimer) {
		clearInterval(autoCaptureTimer);
		autoCaptureTimer = null;
	}
	autoCaptureRunning.value = false;

	// 停止扫码模式
	if (isScanModeActive()) {
		stopScanMode();
	}
	scanActive.value = false;

	// 关闭相机（无论 cameraVisible 状态如何都调用，确保原生层完全清理）
	closeCamera();
	cameraVisible.value = false;
});
</script>

<style lang="scss">
.demo-page {
	width: 100%;
	height: 100vh;
	overflow: hidden;

	.methods {
		background: #0d1117;
		width: 100%;
		height: 60vh;
		margin-top: 40vh;
	}
}

// 顶部标题
.header {
	background: linear-gradient(135deg, #1a2233 0%, #0d1a2e 100%);
	padding: 60rpx 30rpx 30rpx;
	border-bottom: 1px solid #1e2d40;

	.header-title {
		display: block;
		font-size: 36rpx;
		font-weight: bold;
		color: #58a6ff;
		letter-spacing: 2rpx;
	}

	.header-sub {
		display: block;
		font-size: 22rpx;
		color: #8b949e;
		margin-top: 8rpx;
	}
}

// 状态栏
.status-bar {
	display: flex;
	flex-direction: row;
	flex-wrap: wrap;
	gap: 12rpx;
	padding: 16rpx 24rpx;
	background: #161b22;
	border-bottom: 1px solid #21262d;

	.status-item {
		display: flex;
		align-items: center;
		gap: 8rpx;
		background: #0d1117;
		padding: 6rpx 16rpx;
		border-radius: 20rpx;
		border: 1px solid #21262d;
	}

	.status-dot {
		width: 12rpx;
		height: 12rpx;
		border-radius: 50%;
	}

	.dot-green {
		background: #3fb950;
		box-shadow: 0 0 6rpx #3fb950;
	}

	.dot-blue {
		background: #58a6ff;
		box-shadow: 0 0 6rpx #58a6ff;
	}

	.dot-gray {
		background: #484f58;
	}

	.status-label {
		font-size: 22rpx;
		color: #8b949e;
	}
}

// 区块
.section {
	margin: 20rpx 20rpx 0;
	background: #161b22;
	border-radius: 16rpx;
	border: 1px solid #21262d;
	padding: 24rpx;

	.section-title {
		display: flex;
		align-items: center;
		gap: 12rpx;
		margin-bottom: 20rpx;
		font-size: 28rpx;
		font-weight: bold;
		color: #e6edf3;

		.section-icon {
			font-size: 28rpx;
		}

		.log-clear {
			margin-left: auto;
			font-size: 22rpx;
			color: #58a6ff;
			font-weight: normal;
		}
	}
}

.sub-section {
	margin-top: 16rpx;
	padding-top: 16rpx;
	border-top: 1px solid #21262d;

	.sub-title {
		font-size: 24rpx;
		color: #8b949e;
		margin-bottom: 12rpx;
		display: block;
	}
}

// 按钮行
.btn-row {
	display: flex;
	flex-direction: row;
	gap: 12rpx;
	margin-bottom: 12rpx;

	.btn {
		flex: 1;
		min-height: 72rpx;
		border-radius: 10rpx;
		font-size: 24rpx;
		font-weight: 600;
		border: none;
		padding: 0 10rpx;
		line-height: 72rpx;

		&[disabled] {
			opacity: 0.4;
		}
	}

	.btn-primary {
		background: #1f6feb;
		color: #fff;
	}

	.btn-success {
		background: #238636;
		color: #fff;
	}

	.btn-danger {
		background: #da3633;
		color: #fff;
	}

	.btn-warning {
		background: #bb8009;
		color: #fff;
	}

	.btn-default {
		background: #21262d;
		color: #c9d1d9;
		border: 1px solid #30363d;
	}
}

// 输入行
.input-row {
	display: flex;
	align-items: center;
	gap: 12rpx;
	margin-bottom: 12rpx;

	.input-label {
		font-size: 24rpx;
		color: #8b949e;
		min-width: 110rpx;
	}

	.input-field {
		flex: 1;
		height: 64rpx;
		background: #0d1117;
		border: 1px solid #30363d;
		border-radius: 8rpx;
		color: #e6edf3;
		font-size: 24rpx;
		padding: 0 16rpx;
	}
}

// 颜色选择
.color-options {
	display: flex;
	gap: 12rpx;

	.color-dot {
		width: 40rpx;
		height: 40rpx;
		border-radius: 50%;
		border: 3rpx solid transparent;

		&.color-dot-active {
			border-color: #58a6ff;
			transform: scale(1.2);
		}
	}
}

// 对齐选择
.align-options {
	display: flex;
	gap: 8rpx;

	.align-btn {
		padding: 6rpx 16rpx;
		font-size: 22rpx;
		color: #8b949e;
		background: #21262d;
		border-radius: 6rpx;
		border: 1px solid #30363d;

		&.align-btn-active {
			color: #fff;
			background: #1f6feb;
			border-color: #1f6feb;
		}
	}
}

// 照片预览
.photo-preview {
	margin-top: 16rpx;
	padding: 16rpx;
	background: #0d1117;
	border-radius: 10rpx;
	border: 1px solid #30363d;

	.preview-label {
		font-size: 22rpx;
		color: #8b949e;
		display: block;
		margin-bottom: 10rpx;
	}

	.preview-image {
		width: 100%;
		border-radius: 8rpx;
	}

	.preview-path {
		display: block;
		font-size: 20rpx;
		color: #484f58;
		margin-top: 8rpx;
		word-break: break-all;
	}
}

// 扫码
.scan-desc {
	margin-bottom: 16rpx;

	.desc-text {
		font-size: 22rpx;
		color: #8b949e;
		line-height: 1.6;
	}
}

.quality-row {
	display: flex;
	align-items: center;
	gap: 16rpx;
	margin-top: 8rpx;
	margin-bottom: 12rpx;

	.quality-label {
		font-size: 22rpx;
		color: #8b949e;
		min-width: 160rpx;
	}

	.quality-slider {
		flex: 1;
	}
}

.scan-frame-preview {
	margin-top: 16rpx;
	padding: 16rpx;
	background: #0d1117;
	border-radius: 10rpx;
	border: 1px solid #30363d;

	.scan-frame-image {
		width: 100%;
		border-radius: 8rpx;
	}

	.frame-info {
		display: block;
		font-size: 20rpx;
		color: #58a6ff;
		margin-top: 6rpx;
	}
}

// UID 列表
.uid-list {
	margin-bottom: 12rpx;

	.uid-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 12rpx 16rpx;
		background: #0d1117;
		border-radius: 8rpx;
		margin-bottom: 8rpx;
		border: 1px solid #21262d;

		.uid-text {
			font-size: 22rpx;
			color: #8b949e;
			flex: 1;
		}

		.uid-actions {
			display: flex;
			gap: 10rpx;
		}

		.uid-btn {
			font-size: 22rpx;
			color: #58a6ff;
			padding: 4rpx 16rpx;
			background: #1f6feb22;
			border-radius: 6rpx;

			&.uid-btn-danger {
				color: #f85149;
				background: #da363322;
			}
		}
	}

	.uid-empty {
		font-size: 22rpx;
		color: #484f58;
		text-align: center;
		padding: 20rpx;
		display: block;
	}
}

// 日志
.log-scroll {
	height: 400rpx;
	background: #0d1117;
	border-radius: 10rpx;
	padding: 12rpx;

	.log-item {
		display: flex;
		gap: 12rpx;
		padding: 6rpx 0;
		border-bottom: 1px solid #1c2128;

		.log-time {
			font-size: 20rpx;
			color: #484f58;
			min-width: 100rpx;
		}

		.log-msg {
			font-size: 22rpx;
			color: #c9d1d9;
			flex: 1;
			line-height: 1.5;
			word-break: break-all;
		}

		.log-success {
			color: #3fb950;
		}

		.log-error {
			color: #f85149;
		}

		.log-warn {
			color: #d29922;
		}
	}

	.log-empty {
		font-size: 22rpx;
		color: #484f58;
		text-align: center;
		padding: 40rpx;
		display: block;
	}
}

.safe-bottom {
	height: 60rpx;
}
</style>
