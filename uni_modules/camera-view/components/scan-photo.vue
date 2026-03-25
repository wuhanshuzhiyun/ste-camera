<template>
	<view class="root">
		<!-- 底部操作栏（fixed，相机画面显示在其上方） -->
		<view class="bottom-bar">
			<!-- Tab 切换 -->
			<view class="tab-bar">
				<view v-for="tab in tabs" :key="tab.key" :class="['tab-item', activeTab === tab.key ? 'tab-active' : '']" @click="switchTab(tab.key)">
					<text class="tab-icon">{{ tab.icon }}</text>
					<text class="tab-label">{{ tab.label }}</text>
				</view>
			</view>

			<!-- 扫码模式操作区 -->
			<view v-if="activeTab === 'scan'" class="action-area">
				<view class="scan-status-row">
					<view :class="['scan-dot', scanActive ? 'dot-active' : '']"></view>
					<text class="scan-status-text">{{ scanActive ? '识别中...' : '未启动' }}</text>
				</view>
			</view>

			<!-- 拍照模式操作区 -->
			<view v-if="activeTab === 'photo'" class="action-area">
				<view class="btn-row">
					<button class="shutter-btn" @click="takePictureAction">
						<view class="shutter-inner"></view>
					</button>
				</view>
			</view>
		</view>
	</view>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { showCamera, closeCamera, takePicture, updateView, startScanMode, stopScanMode, getScanFrame, isScanModeActive, showScanBar, hideScanBar } from '@/uni_modules/camera-view';
import { TEXT_UID, scanBar, viewText, views } from './const';

const emit = defineEmits(['scan-mode', 'take-picture', 'success', 'error']);

// ===== Tab =====
const tabs = [
	{ key: 'scan', icon: '🔍', label: '扫码' },
	{ key: 'photo', icon: '📷', label: '拍照' }
];
const activeTab = ref('scan');

// ===== 状态 =====
const scanActive = ref(false);
const cameraFacing = ref('back');
let screenWidth = null;
let screenHeight = null;

// 自动抓帧定时器
let autoScanTimer = null;

// ===== 生命周期 =====
onMounted(() => {
	const info = uni.getSystemInfoSync();
	screenWidth = info.screenWidth;
	screenHeight = info.screenHeight;
	initCamera();
});

onUnmounted(() => {
	cleanup();
});

async function initCamera() {
	// 关闭可能存在的残留相机
	closeCamera();
	await sleep(100);
	// 初始化相机，默认扫码 Tab，带扫描条
	showCamera({
		height: screenHeight - 120,
		views: views(screenWidth, screenHeight),
		success: async (res) => {
			console.log('开启成功', res);
			// 等待相机稳定后自动启动扫码模式
			await sleep(100);
			enterScanTab();
			emit('success');
		},
		fail: (err) => {
			uni.showModal({
				title: err.errMsg,
				showCancel: false,
				success: () => emit('error', err)
			});
		}
	});
}

function cleanup() {
	stopAutoScan();
	if (scanActive.value) {
		stopScanMode();
		scanActive.value = false;
	}
	closeCamera();
}

// ===== 进入扫码 Tab 逻辑（显示扫描条 + 自动启动扫码）=====
function enterScanTab() {
	// 更新叠加视图为扫码提示
	updateView(TEXT_UID, viewText(screenHeight));
	// 显示扫描条
	showScanBar(scanBar(screenHeight));
	// 启动扫码模式 + 自动抓帧
	const ok = startScanMode();
	if (ok) {
		scanActive.value = true;
		startAutoScan();
	} else {
		uni.showToast({ title: '扫码启动失败', icon: 'none' });
	}
}

// ===== 进入拍照 Tab 逻辑（隐藏扫描条 + 停止扫码）=====
function enterPhotoTab() {
	// 停止扫码
	stopAutoScan();
	if (isScanModeActive()) {
		stopScanMode();
	}
	scanActive.value = false;
	// 隐藏扫描条
	hideScanBar();
	updateView(TEXT_UID, viewText(screenHeight, '对准商品，点击按钮识别'));
}

// ===== Tab 切换 =====
function switchTab(key) {
	if (activeTab.value === key) return;
	activeTab.value = key;
	if (key === 'scan') {
		enterScanTab();
	} else {
		enterPhotoTab();
	}
}

function startAutoScan() {
	autoScanTimer = setInterval(() => {
		if (!isScanModeActive()) {
			stopAutoScan();
			scanActive.value = false;
			return;
		}
		const frame = getScanFrame(80);
		emit('scan-mode', frame);
	}, 500);
}

function stopAutoScan() {
	if (autoScanTimer) {
		clearInterval(autoScanTimer);
		autoScanTimer = null;
	}
}

// ===== 拍照功能 =====
function takePictureAction() {
	takePicture((path) => {
		if (path) {
			emit('take-picture', path);
		} else {
			uni.showToast({ title: '拍照失败', icon: 'none' });
		}
	});
}

// ===== 工具 =====
function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}
</script>

<style lang="scss" scoped>
.root {
	width: 100vw;
	height: 100vh;
	background: #000;
	position: relative;
}

/* ===== 底部操作栏 ===== */
.bottom-bar {
	width: 100%;
	height: 120px;
	position: fixed;
	left: 0;
	right: 0;
	bottom: 0;
	background: #0d1117;
	border-top: 1px solid #21262d;
	z-index: 100;
}

/* Tab */
.tab-bar {
	display: flex;
	flex-direction: row;
	border-bottom: 1px solid #21262d;
}

.tab-item {
	flex: 1;
	display: flex;
	flex-direction: column;
	align-items: center;
	padding: 16rpx 0 12rpx;
	gap: 4rpx;

	.tab-icon {
		font-size: 32rpx;
	}

	.tab-label {
		font-size: 22rpx;
		color: #484f58;
	}

	&.tab-active {
		.tab-label {
			color: #58a6ff;
			font-weight: bold;
		}
	}
}

/* 操作区公共 */
.action-area {
	padding: 20rpx 30rpx 40rpx;
}

.btn-row {
	display: flex;
	flex-direction: row;
	align-items: center;
	justify-content: center;
}

.action-btn {
	flex: 1;
	height: 76rpx;
	border-radius: 12rpx;
	font-size: 26rpx;
	font-weight: 600;
	border: none;
	line-height: 76rpx;

	&[disabled] {
		opacity: 0.4;
	}
}

.btn-default {
	background: #21262d;
	color: #c9d1d9;
	border: 1px solid #30363d;
}

/* ===== 扫码区 ===== */
.scan-status-row {
	display: flex;
	align-items: center;
	gap: 12rpx;

	.scan-dot {
		width: 14rpx;
		height: 14rpx;
		border-radius: 50%;
		background: #484f58;
		flex-shrink: 0;

		&.dot-active {
			background: #3fb950;
			box-shadow: 0 0 8rpx #3fb950;
		}
	}

	.scan-status-text {
		font-size: 24rpx;
		color: #8b949e;
	}
}

/* 快门按钮 */
.shutter-btn {
	width: 120rpx;
	height: 120rpx;
	border-radius: 50%;
	background: transparent;
	border: 4rpx solid #fff;
	display: flex;
	align-items: center;
	justify-content: center;
	padding: 0;
	flex-shrink: 0;

	&:active {
		opacity: 0.7;
		transform: scale(0.95);
	}

	.shutter-inner {
		width: 96rpx;
		height: 96rpx;
		border-radius: 50%;
		background: #fff;
	}
}
</style>
