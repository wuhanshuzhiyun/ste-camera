import UIKit
import Foundation

/// 图片处理工具类（对标 Android ImageProcessor.kt）
/// 单例模式，负责：水印绘制、图片旋转/镜像、保存到缓存目录
@objc public class ImageProcessor: NSObject {

    // MARK: - 单例
    @objc public static let shared = ImageProcessor()
    private override init() { super.init() }

    // MARK: - JPEG 压缩质量（可配置）
    @objc public var jpegQuality: CGFloat = 0.9

    // MARK: - 保存图片到缓存目录

    /// 将 UIImage 保存为 JPEG 到 App 缓存目录，返回文件绝对路径
    @objc public func saveImageToCache(_ image: UIImage, quality: CGFloat = -1) -> String? {
        let q = quality < 0 ? jpegQuality : min(max(quality, 0.01), 1.0)
        NSLog("[ImageProcessor] saveImageToCache: image.size=\(image.size), imageOrientation=\(image.imageOrientation)")
        guard let data = image.jpegData(compressionQuality: q) else {
            NSLog("[ImageProcessor] saveImageToCache: jpegData compression failed")
            return nil
        }
        NSLog("[ImageProcessor] saveImageToCache: jpeg data length=\(data.count) bytes, quality=\(q)")
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = cachesDir else { return nil }
        let fileName = "camera_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let fileURL = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            NSLog("[ImageProcessor] saveImageToCache: saved to \(fileURL.path)")
            return fileURL.path
        } catch {
            NSLog("[ImageProcessor] saveImageToCache: write failed \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 图片旋转

    /// 按指定角度旋转图片（角度：0 / 90 / 180 / 270）
    @objc public func rotateImage(_ image: UIImage, degrees: CGFloat) -> UIImage {
        if degrees == 0 { return image }
        let radians = degrees * .pi / 180
        let newSize: CGSize
        // 90° / 270° 时宽高互换
        if Int(degrees) % 180 != 0 {
            newSize = CGSize(width: image.size.height, height: image.size.width)
        } else {
            newSize = image.size
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        image.draw(in: CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        ))
        let rotated = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return rotated
    }

    // MARK: - 水平镜像翻转（用于前置摄像头）

    @objc public func flipImageHorizontal(_ image: UIImage) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        context.translateBy(x: image.size.width, y: 0)
        context.scaleBy(x: -1, y: 1)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let flipped = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return flipped
    }

    // MARK: - 绘制水印

    /// 将水印配置列表叠加绘制到照片上，返回新图片
    /// - Parameters:
    ///   - image: 原始照片
    ///   - watermarks: 水印配置数组（与 Android 端格式完全一致）
    @objc public func drawWatermarks(on image: UIImage, watermarks: [[String: Any]]) -> UIImage {
        guard !watermarks.isEmpty else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))

        let photoW = image.size.width
        let photoH = image.size.height

        // 以屏幕主 scale 与图片宽度计算 dp→px 的比例
        // 与 Android 端 dpToPhoto = density * (photoWidth / screenWidthPx) 等效
        let screenScale = UIScreen.main.scale
        let screenW = UIScreen.main.bounds.width * screenScale
        let dpToPhoto = screenScale * (photoW / screenW)

        for config in watermarks {
            guard let type = config["type"] as? String else { continue }
            let style = config["style"] as? [String: Any]

            switch type {
            case "text":
                drawTextWatermark(config: config, style: style, dpToPhoto: dpToPhoto, photoW: photoW, photoH: photoH)
            case "image":
                drawImageWatermark(config: config, style: style, dpToPhoto: dpToPhoto)
            default:
                break
            }
        }

        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    // MARK: - 绘制文字水印

    private func drawTextWatermark(
        config: [String: Any],
        style: [String: Any]?,
        dpToPhoto: CGFloat,
        photoW: CGFloat,
        photoH: CGFloat
    ) {
        guard let text = config["text"] as? String else { return }

        // 字体大小
        let fontSizeDp = (style?["fontSize"] as? CGFloat) ?? 14
        let fontSize = fontSizeDp * dpToPhoto

        // 字体粗细 / 斜体
        let fontWeight = style?["fontWeight"] as? String ?? "normal"
        let fontStyleVal = style?["fontStyle"] as? String ?? "normal"
        let isBold   = fontWeight == "bold" || (Int(fontWeight) ?? 0) >= 700
        let isItalic = fontStyleVal == "italic"

        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold   { traits.insert(.traitBold) }
        if isItalic { traits.insert(.traitItalic) }

        let font: UIFont
        if traits.isEmpty {
            font = UIFont.systemFont(ofSize: fontSize)
        } else if let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            font = UIFont.systemFont(ofSize: fontSize)
        }

        // 字体颜色
        let fontColor = parseColor(style?["fontColor"] as? String) ?? .white

        // 位置
        let topDp  = (style?["top"] as? CGFloat) ?? 0
        let topPx  = topDp * dpToPhoto

        let textAlignStr = style?["textAlign"] as? String ?? "left"
        let textOffsetDp = (style?["textOffset"] as? CGFloat) ?? 0
        let textOffsetPx = textOffsetDp * dpToPhoto

        // 计算文字尺寸
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontColor
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let x: CGFloat
        let paragraphStyle = NSMutableParagraphStyle()
        switch textAlignStr {
        case "center":
            x = photoW / 2 - textSize.width / 2 + textOffsetPx
            paragraphStyle.alignment = .center
        case "right":
            x = photoW - textSize.width - textOffsetPx
            paragraphStyle.alignment = .right
        default:
            x = textOffsetPx
            paragraphStyle.alignment = .left
        }

        let allAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontColor,
            .paragraphStyle: paragraphStyle
        ]

        let drawRect = CGRect(x: x, y: topPx, width: textSize.width, height: textSize.height)
        (text as NSString).draw(in: drawRect, withAttributes: allAttrs)
    }

    // MARK: - 绘制图片水印

    private func drawImageWatermark(
        config: [String: Any],
        style: [String: Any]?,
        dpToPhoto: CGFloat
    ) {
        guard let imageUrl = config["image"] as? String else { return }

        // 优先取预加载的图片，否则尝试本地加载（与 Android 端一致）
        var watermarkImage: UIImage? = CameraViewManager.shared.getPreloadedImage(for: imageUrl)
        if watermarkImage == nil {
            if !imageUrl.hasPrefix("http") {
                watermarkImage = UIImage(contentsOfFile: imageUrl)
                if watermarkImage == nil {
                    return
                }
            } else {
                // 网络图片未预加载，跳过（与 Android 端一致）
                return
            }
        }
        guard let wImg = watermarkImage else { return }

        let rawWidthDp  = style?["width"]  as? CGFloat
        let rawHeightDp = style?["height"] as? CGFloat
        let topPx  = ((style?["top"]  as? CGFloat) ?? 0) * dpToPhoto
        let leftPx = ((style?["left"] as? CGFloat) ?? 0) * dpToPhoto

        let bmpW = wImg.size.width
        let bmpH = wImg.size.height

        // 目标尺寸（逻辑与 Android 端完全一致）
        let dstW: CGFloat
        let dstH: CGFloat
        if let rw = rawWidthDp, let rh = rawHeightDp {
            dstW = rw * dpToPhoto
            dstH = rh * dpToPhoto
        } else if let rw = rawWidthDp {
            dstW = rw * dpToPhoto
            dstH = bmpW > 0 ? dstW * bmpH / bmpW : dstW
        } else if let rh = rawHeightDp {
            dstH = rh * dpToPhoto
            dstW = bmpH > 0 ? dstH * bmpW / bmpH : dstH
        } else {
            dstW = bmpW
            dstH = bmpH
        }

        let drawRect = CGRect(x: leftPx, y: topPx, width: max(dstW, 1), height: max(dstH, 1))
        wImg.draw(in: drawRect)
    }

    // MARK: - 颜色解析（与 CameraViewManager 中的 parseColor 保持一致）

    private func parseColor(_ hexStr: String?) -> UIColor? {
        guard var hex = hexStr else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 6 { hex = "FF" + hex }
        guard hex.count == 8 else { return nil }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let a = CGFloat((value >> 24) & 0xFF) / 255
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >>  8) & 0xFF) / 255
        let b = CGFloat( value        & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
