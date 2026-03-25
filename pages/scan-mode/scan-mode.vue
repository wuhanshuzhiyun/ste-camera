<template>
	<scanPhoto @error="onError" />
</template>

<script setup>
import scanPhoto from '@/uni_modules/camera-view/components/scan-photo.vue';

const onError = () => uni.navigateBack();
</script>

<style lang="scss"></style>
