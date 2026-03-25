<template>
	<view class="home-page">
		<!-- 顶部标题 -->
		<view class="hero">
			<view class="hero-icon">📷</view>
			<text class="hero-title">camera-view</text>
			<text class="hero-sub">UTS 原生相机插件 · Android</text>
			<view class="hero-badge">
				<text class="badge-text">v1.0.0</text>
			</view>
		</view>

		<!-- 入口卡片 -->
		<view class="card-list">
			<!-- 全量测试 -->
			<view class="entry-card" @click="goFullTest">
				<view class="card-left">
					<view class="card-icon-wrap icon-blue">
						<text class="card-icon">🧪</text>
					</view>
				</view>
				<view class="card-body">
					<text class="card-title">全量功能测试</text>
					<text class="card-desc">显示/关闭相机、拍照、视图叠加、扫码模式、扫描条动画等完整功能验证</text>
				</view>
				<text class="card-arrow">›</text>
			</view>

			<!-- 扫码拍照 -->
			<view class="entry-card" @click="goScanMode">
				<view class="card-left">
					<view class="card-icon-wrap icon-green">
						<text class="card-icon">🔍</text>
					</view>
				</view>
				<view class="card-body">
					<text class="card-title">扫码 / 拍照</text>
					<text class="card-desc">实际使用场景演示：扫码识别与带水印拍照，底部 Tab 切换两种模式</text>
				</view>
				<text class="card-arrow">›</text>
			</view>
		</view>

		<!-- 功能特性列表 -->
		<view class="feature-section">
			<text class="feature-title">插件特性</text>
			<view class="feature-grid">
				<view class="feature-item" v-for="f in features" :key="f.label">
					<text class="feature-icon">{{ f.icon }}</text>
					<text class="feature-label">{{ f.label }}</text>
				</view>
			</view>
		</view>
	</view>
</template>

<script setup>
	const features = [
		{ icon: '📐', label: '自定义尺寸' },
		{ icon: '🖼️', label: '视图叠加' },
		{ icon: '💧', label: '照片水印' },
		{ icon: '🔄', label: '前后切换' },
		{ icon: '📷', label: '拍照输出' },
		{ icon: '📡', label: '帧捕获' },
		{ icon: '🔍', label: '扫码模式' },
		{ icon: '✨', label: '扫描条动画' },
	];

	const goFullTest = () => {
		uni.navigateTo({ url: '/pages/camera-test/camera-test' });
	};

	const goScanMode = () => {
		uni.navigateTo({ url: '/pages/scan-mode/scan-mode' });
	};
</script>

<style lang="scss">
	.home-page {
		min-height: 100vh;
		background: #0d1117;
		padding-bottom: 60rpx;
	}

	/* ===== Hero ===== */
	.hero {
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 100rpx 40rpx 60rpx;
		background: linear-gradient(160deg, #0d1a2e 0%, #0d1117 100%);

		.hero-icon {
			font-size: 80rpx;
			margin-bottom: 16rpx;
		}

		.hero-title {
			font-size: 52rpx;
			font-weight: bold;
			color: #58a6ff;
			letter-spacing: 4rpx;
		}

		.hero-sub {
			font-size: 24rpx;
			color: #8b949e;
			margin-top: 12rpx;
		}

		.hero-badge {
			margin-top: 20rpx;
			background: #1f6feb22;
			border: 1px solid #1f6feb66;
			border-radius: 30rpx;
			padding: 6rpx 24rpx;

			.badge-text {
				font-size: 22rpx;
				color: #58a6ff;
			}
		}
	}

	/* ===== 入口卡片 ===== */
	.card-list {
		padding: 0 30rpx;
		margin-top: 10rpx;
	}

	.entry-card {
		display: flex;
		align-items: center;
		gap: 24rpx;
		background: #161b22;
		border: 1px solid #21262d;
		border-radius: 20rpx;
		padding: 30rpx 24rpx;
		margin-bottom: 20rpx;
		active-opacity: 0.7;

		&:active {
			opacity: 0.75;
			transform: scale(0.98);
		}

		.card-left {
			flex-shrink: 0;

			.card-icon-wrap {
				width: 96rpx;
				height: 96rpx;
				border-radius: 24rpx;
				display: flex;
				align-items: center;
				justify-content: center;

				.card-icon {
					font-size: 44rpx;
				}
			}

			.icon-blue {
				background: #1f6feb22;
				border: 1px solid #1f6feb44;
			}

			.icon-green {
				background: #23863622;
				border: 1px solid #23863644;
			}
		}

		.card-body {
			flex: 1;

			.card-title {
				display: block;
				font-size: 30rpx;
				font-weight: bold;
				color: #e6edf3;
				margin-bottom: 10rpx;
			}

			.card-desc {
				display: block;
				font-size: 22rpx;
				color: #8b949e;
				line-height: 1.6;
			}
		}

		.card-arrow {
			font-size: 40rpx;
			color: #30363d;
			flex-shrink: 0;
		}
	}

	/* ===== 功能特性 ===== */
	.feature-section {
		margin: 30rpx 30rpx 0;

		.feature-title {
			display: block;
			font-size: 24rpx;
			color: #484f58;
			margin-bottom: 20rpx;
			letter-spacing: 2rpx;
		}

		.feature-grid {
			display: flex;
			flex-wrap: wrap;
			gap: 16rpx;
		}

		.feature-item {
			display: flex;
			align-items: center;
			gap: 8rpx;
			background: #161b22;
			border: 1px solid #21262d;
			border-radius: 30rpx;
			padding: 10rpx 20rpx;

			.feature-icon {
				font-size: 26rpx;
			}

			.feature-label {
				font-size: 22rpx;
				color: #8b949e;
			}
		}
	}
</style>
