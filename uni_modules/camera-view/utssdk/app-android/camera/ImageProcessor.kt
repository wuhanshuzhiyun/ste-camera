package uts.ste.camera

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import io.dcloud.uts.console
import java.io.File
import java.io.FileOutputStream

/**
 * 图片处理工具类
 */
object ImageProcessor {

    // 可配置的 JPEG 压缩质量
    var jpegQuality: Int = 90

    fun saveBitmapToFile(context: Activity?, bitmap: Bitmap, quality: Int = jpegQuality): String? {
        if (context == null) return null
        if (bitmap.isRecycled) {
            console.log("Bitmap 已被回收，无法保存")
            return null
        }
        return try {
            val cacheDir = context.cacheDir
            val fileName = "camera_${System.currentTimeMillis()}.jpg"
            val file = File(cacheDir, fileName)

            FileOutputStream(file).use { outputStream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), outputStream)
                outputStream.flush()
            }
            file.absolutePath
        } catch (e: Throwable) {
            console.log("保存图片失败：${e.message}")
            null
        }
    }

    fun rotateBitmap(bitmap: Bitmap, degrees: Float): Bitmap {
        if (degrees == 0f) return bitmap
        return try {
            val matrix = android.graphics.Matrix()
            matrix.postRotate(degrees)
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: Throwable) {
            console.log("旋转图片失败：${e.message}")
            bitmap
        }
    }

    /**
     * 水平镜像翻转（用于前置摄像头自拍）
     */
    fun flipBitmapHorizontal(bitmap: Bitmap): Bitmap {
        return try {
            val matrix = android.graphics.Matrix()
            matrix.preScale(-1f, 1f)
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: Throwable) {
            console.log("镜像翻转失败：${e.message}")
            bitmap
        }
    }

    /**
     * 将水印配置叠加绘制到照片上
     *
     * @param context          Activity（获取 displayMetrics）
     * @param bitmap           原始照片 Bitmap
     * @param watermarks       水印配置列表
     * @param containerWidthDp 相机容器宽度（dp）；为 0 时退回到屏幕宽度（向后兼容）
     */
    fun drawWatermarks(context: Activity, bitmap: Bitmap, watermarks: List<Map<String, Any?>>,
                       containerWidthDp: Int = 0): Bitmap {
        if (watermarks.isEmpty()) return bitmap

        val mutableBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(mutableBitmap)

        val density = context.resources.displayMetrics.density
        val photoWidth = mutableBitmap.width.toFloat()

        // dp → photo-px 比例：
        //   正确公式：photoWidth / containerWidthDp（水印 dp 坐标直接对应容器 dp 宽度）
        //   旧公式（全屏）：density * (photoWidth / screenWidthPx) ≈ photoWidth / (screenWidthPx/density)
        //   两者在容器铺满屏幕时等价；容器非全屏时旧公式偏移，改为正确公式。
        val containerDp = if (containerWidthDp > 0) containerWidthDp.toFloat()
                          else (context.resources.displayMetrics.widthPixels / density)
        val dpToPhoto = photoWidth / containerDp

        for (config in watermarks) {
            val type = config["type"] as? String ?: continue
            val style = config["style"] as? Map<*, *>

            when (type) {
                "text" -> drawTextWatermark(canvas, config, style, dpToPhoto, photoWidth)
                "image" -> drawImageWatermark(canvas, config, style, dpToPhoto)
            }
        }
        return mutableBitmap
    }

    private fun drawTextWatermark(
        canvas: Canvas,
        config: Map<String, Any?>,
        style: Map<*, *>?,
        dpToPhoto: Float,
        photoWidth: Float
    ) {
        val text = config["text"] as? String ?: return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // 字体样式
        val fontSizeDp = (style?.get("fontSize") as? Number)?.toFloat() ?: 14f
        paint.textSize = fontSizeDp * dpToPhoto

        val fontColor = style?.get("fontColor") as? String ?: "#FFFFFF"
        paint.color = try { Color.parseColor(fontColor) } catch (e: Exception) { Color.WHITE }

        val fontWeight = style?.get("fontWeight") as? String ?: "normal"
        val isBold = fontWeight == "bold" || (fontWeight.toIntOrNull() ?: 0) >= 700
        val fontStyleVal = style?.get("fontStyle") as? String ?: "normal"
        val isItalic = fontStyleVal == "italic"
        paint.typeface = when {
            isBold && isItalic -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC)
            isBold -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            isItalic -> Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
            else -> Typeface.DEFAULT
        }

        // 位置
        val topDp = (style?.get("top") as? Number)?.toFloat() ?: 0f
        val topPx = topDp * dpToPhoto
        val fm = paint.fontMetrics
        val y = topPx - fm.ascent

        val textAlign = style?.get("textAlign") as? String ?: "left"
        val textOffsetDp = (style?.get("textOffset") as? Number)?.toFloat() ?: 0f
        val textOffsetPx = textOffsetDp * dpToPhoto

        val x = when (textAlign) {
            "center" -> { paint.textAlign = Paint.Align.CENTER; photoWidth / 2f + textOffsetPx }
            "right" -> { paint.textAlign = Paint.Align.RIGHT; photoWidth - textOffsetPx }
            else -> { paint.textAlign = Paint.Align.LEFT; textOffsetPx }
        }

        canvas.drawText(text, x, y, paint)
    }

    private fun drawImageWatermark(
        canvas: Canvas,
        config: Map<String, Any?>,
        style: Map<*, *>?,
        dpToPhoto: Float
    ) {
        val imageUrl = config["image"] as? String ?: return

        val watermarkBitmap: Bitmap? = CameraViewManager.getPreloadedBitmap(imageUrl)
            ?: run {
                if (!imageUrl.startsWith("http")) {
                    try {
                        // decodeFile 只接受纯路径，去掉可能携带的 file:// 前缀
                        val path = if (imageUrl.startsWith("file://")) imageUrl.removePrefix("file://") else imageUrl
                        BitmapFactory.decodeFile(path)
                    } catch (e: Exception) {
                        console.log("本地水印图片加载失败：${e.message}"); null
                    }
                } else {
                    console.log("水印图片未预加载，跳过绘制：$imageUrl"); null
                }
            }
        watermarkBitmap ?: return

        val rawWidthDp = (style?.get("width") as? Number)?.toFloat()
        val rawHeightDp = (style?.get("height") as? Number)?.toFloat()
        val topPx = ((style?.get("top") as? Number)?.toFloat() ?: 0f) * dpToPhoto
        val leftPx = ((style?.get("left") as? Number)?.toFloat() ?: 0f) * dpToPhoto

        val bmpW = watermarkBitmap.width.toFloat()
        val bmpH = watermarkBitmap.height.toFloat()

        // 根据传入的宽高决定目标尺寸：
        //   - 都未传：使用图片实际像素尺寸（不做缩放）
        //   - 都传了：拉伸到指定尺寸
        //   - 只传宽：高按比例缩放
        //   - 只传高：宽按比例缩放
        val dstWidthPx: Float
        val dstHeightPx: Float
        when {
            rawWidthDp != null && rawHeightDp != null -> {
                // 宽高都传 → 拉伸
                dstWidthPx = rawWidthDp * dpToPhoto
                dstHeightPx = rawHeightDp * dpToPhoto
            }
            rawWidthDp != null -> {
                // 只传宽 → 高按比例
                dstWidthPx = rawWidthDp * dpToPhoto
                dstHeightPx = if (bmpW > 0f) dstWidthPx * bmpH / bmpW else dstWidthPx
            }
            rawHeightDp != null -> {
                // 只传高 → 宽按比例
                dstHeightPx = rawHeightDp * dpToPhoto
                dstWidthPx = if (bmpH > 0f) dstHeightPx * bmpW / bmpH else dstHeightPx
            }
            else -> {
                // 都未传 → 使用图片实际像素尺寸
                dstWidthPx = bmpW
                dstHeightPx = bmpH
            }
        }

        val scaledBitmap = Bitmap.createScaledBitmap(
            watermarkBitmap,
            dstWidthPx.toInt().coerceAtLeast(1),
            dstHeightPx.toInt().coerceAtLeast(1),
            true
        )
        canvas.drawBitmap(scaledBitmap, leftPx, topPx, null)
        // 回收缩放后的 Bitmap（createScaledBitmap 创建了新对象）
        if (!scaledBitmap.isRecycled) {
            scaledBitmap.recycle()
        }
    }
}
