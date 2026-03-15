#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private struct IconSlot {
    let pointSize: Int
    let scale: Int

    var pixelSize: Int {
        pointSize * scale
    }

    var filename: String {
        let suffix = scale == 1 ? "" : "@\(scale)x"
        return "icon_\(pointSize)x\(pointSize)\(suffix).png"
    }
}

private enum DetailLevel {
    case tiny
    case compact
    case full

    static func forCanvasSize(_ size: CGFloat) -> DetailLevel {
        switch size {
        case ..<80:
            return .tiny
        case ..<180:
            return .compact
        default:
            return .full
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private let iconSlots = [
    IconSlot(pointSize: 16, scale: 1),
    IconSlot(pointSize: 16, scale: 2),
    IconSlot(pointSize: 32, scale: 1),
    IconSlot(pointSize: 32, scale: 2),
    IconSlot(pointSize: 128, scale: 1),
    IconSlot(pointSize: 128, scale: 2),
    IconSlot(pointSize: 256, scale: 1),
    IconSlot(pointSize: 256, scale: 2),
    IconSlot(pointSize: 512, scale: 1),
    IconSlot(pointSize: 512, scale: 2),
]

private func makeBitmap(size: Int, draw: (CGContext, CGRect) -> Void) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context"])
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "GenerateAppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create graphics context"])
    }

    NSGraphicsContext.current = graphicsContext
    let context = graphicsContext.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    draw(context, CGRect(x: 0, y: 0, width: size, height: size))
    return bitmap
}

private func roundedPath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func rgbGradient(
    colors: [NSColor],
    locations: [CGFloat]
) -> CGGradient {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = colors.map { $0.cgColor } as CFArray
    return CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations)!
}

private func drawGradientStroke(
    context: CGContext,
    path: CGPath,
    lineWidth: CGFloat,
    colors: [NSColor],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(rgbGradient(colors: colors, locations: locations), start: start, end: end, options: [])
    context.restoreGState()
}

private func drawScreenGrid(context: CGContext, rect: CGRect, clipPath: CGPath, size: CGFloat, detailLevel: DetailLevel) {
    guard detailLevel != .tiny else { return }

    let gridInsetX = rect.width * 0.07
    let gridInsetY = rect.height * 0.08
    let gridRect = rect.insetBy(dx: gridInsetX, dy: gridInsetY)

    context.saveGState()
    context.addPath(clipPath)
    context.clip()
    context.setLineWidth(max(1, size * 0.0022))

    let horizontalLines = detailLevel == .compact ? 3 : 5
    for index in 1...horizontalLines {
        let progress = CGFloat(index) / CGFloat(horizontalLines + 1)
        let y = gridRect.minY + gridRect.height * progress
        let alpha = detailLevel == .compact ? 0.055 : 0.07
        context.setStrokeColor(NSColor(hex: 0xE8EEF9, alpha: alpha).cgColor)
        context.move(to: CGPoint(x: gridRect.minX, y: y))
        context.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        context.strokePath()
    }

    let verticalLines = detailLevel == .compact ? 3 : 4
    for index in 1...verticalLines {
        let progress = CGFloat(index) / CGFloat(verticalLines + 1)
        let x = gridRect.minX + gridRect.width * progress
        let alpha = detailLevel == .compact ? 0.03 : 0.05
        context.setStrokeColor(NSColor(hex: 0xE8EEF9, alpha: alpha).cgColor)
        context.move(to: CGPoint(x: x, y: gridRect.minY))
        context.addLine(to: CGPoint(x: x, y: gridRect.maxY))
        context.strokePath()
    }

    context.restoreGState()
}

private func heartbeatPath(in rect: CGRect, detailLevel: DetailLevel) -> CGPath {
    let width = rect.width
    let height = rect.height
    let baseline = rect.midY
    let path = CGMutablePath()

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + width * x, y: baseline + height * y)
    }

    path.move(to: point(0.00, 0.00))
    path.addLine(to: point(0.20, 0.00))
    path.addLine(to: point(0.26, 0.00))
    path.addCurve(
        to: point(0.33, 0.12),
        control1: point(0.28, 0.00),
        control2: point(0.30, 0.12)
    )
    path.addLine(to: point(0.37, -0.08))
    path.addLine(to: point(0.45, 0.58))
    path.addLine(to: point(0.53, -0.60))
    path.addLine(to: point(0.60, 0.02))
    path.addCurve(
        to: point(0.73, 0.16),
        control1: point(0.64, 0.02),
        control2: point(0.67, 0.16)
    )
    path.addCurve(
        to: point(0.81, 0.00),
        control1: point(0.76, 0.16),
        control2: point(0.78, 0.00)
    )
    path.addLine(to: point(1.00, 0.00))

    if detailLevel == .tiny {
        let simplified = CGMutablePath()
        simplified.move(to: point(0.00, 0.00))
        simplified.addLine(to: point(0.24, 0.00))
        simplified.addLine(to: point(0.33, 0.10))
        simplified.addLine(to: point(0.40, -0.05))
        simplified.addLine(to: point(0.48, 0.52))
        simplified.addLine(to: point(0.57, -0.46))
        simplified.addLine(to: point(0.66, 0.05))
        simplified.addLine(to: point(0.76, 0.12))
        simplified.addLine(to: point(0.84, 0.00))
        simplified.addLine(to: point(1.00, 0.00))
        return simplified
    }

    return path
}

private func drawHeartbeat(context: CGContext, rect: CGRect, size: CGFloat, detailLevel: DetailLevel) {
    let path = heartbeatPath(in: rect, detailLevel: detailLevel)
    let strokeWidth = max(size * (detailLevel == .tiny ? 0.07 : 0.038), 1.5)

    context.saveGState()
    context.addPath(path)
    context.setLineWidth(strokeWidth * (detailLevel == .tiny ? 1.2 : 1.5))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(NSColor(hex: 0xFF4F77, alpha: detailLevel == .full ? 0.18 : 0.12).cgColor)
    context.setShadow(
        offset: .zero,
        blur: strokeWidth * (detailLevel == .tiny ? 0.6 : 1.5),
        color: NSColor(hex: 0xFF4F77, alpha: detailLevel == .full ? 0.30 : 0.16).cgColor
    )
    context.strokePath()
    context.restoreGState()

    drawGradientStroke(
        context: context,
        path: path,
        lineWidth: strokeWidth,
        colors: [
            NSColor(hex: 0xFF5A7B),
            NSColor(hex: 0xFF4774),
            NSColor(hex: 0xFF2C6A),
        ],
        locations: [0.0, 0.5, 1.0],
        start: CGPoint(x: rect.minX, y: rect.midY),
        end: CGPoint(x: rect.maxX, y: rect.midY)
    )

    guard detailLevel == .full else { return }

    drawGradientStroke(
        context: context,
        path: path,
        lineWidth: strokeWidth * 0.32,
        colors: [
            NSColor(hex: 0xFFD6E0, alpha: 0.55),
            NSColor(hex: 0xFFE4EC, alpha: 0.25),
        ],
        locations: [0.0, 1.0],
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY)
    )
}

private func drawControlGlyph(context: CGContext, rect: CGRect, size: CGFloat, detailLevel: DetailLevel) {
    let lineWidth = max(size * (detailLevel == .tiny ? 0.05 : 0.025), 1.4)
    let lineLengths: [CGFloat]
    let knobPositions: [CGFloat]
    let yOffsets: [CGFloat]

    switch detailLevel {
    case .tiny:
        lineLengths = [0.30, 0.22]
        knobPositions = [0.65, 0.38]
        yOffsets = [0.08, -0.12]
    case .compact:
        lineLengths = [0.34, 0.24, 0.30]
        knobPositions = [0.63, 0.38, 0.56]
        yOffsets = [0.14, 0.00, -0.14]
    case .full:
        lineLengths = [0.32, 0.22, 0.28]
        knobPositions = [0.62, 0.32, 0.58]
        yOffsets = [0.14, 0.00, -0.14]
    }

    for index in lineLengths.indices {
        let y = rect.midY + rect.height * yOffsets[index]
        let length = rect.width * lineLengths[index]
        let x = rect.midX - length / 2
        let lineRect = CGRect(x: x, y: y, width: length, height: 0)

        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: lineRect.minX, y: y))
        linePath.addLine(to: CGPoint(x: lineRect.maxX, y: y))

        context.saveGState()
        context.addPath(linePath)
        context.setLineWidth(lineWidth * 1.35)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor(hex: 0xFF4A75, alpha: detailLevel == .full ? 0.15 : 0.10).cgColor)
        context.setShadow(offset: .zero, blur: lineWidth, color: NSColor(hex: 0xFF4470, alpha: 0.18).cgColor)
        context.strokePath()
        context.restoreGState()

        drawGradientStroke(
            context: context,
            path: linePath,
            lineWidth: lineWidth,
            colors: [
                NSColor(hex: 0xFF5A7B),
                NSColor(hex: 0xFF316B),
            ],
            locations: [0.0, 1.0],
            start: CGPoint(x: lineRect.minX, y: y),
            end: CGPoint(x: lineRect.maxX, y: y)
        )

        let knobX = lineRect.minX + length * knobPositions[index]
        let knobRadius = lineWidth * (detailLevel == .tiny ? 0.42 : 0.52)
        let knobRect = CGRect(
            x: knobX - knobRadius,
            y: y - knobRadius,
            width: knobRadius * 2,
            height: knobRadius * 2
        )

        context.saveGState()
        context.setFillColor(NSColor(hex: 0xFF4A75, alpha: 0.14).cgColor)
        context.setShadow(offset: .zero, blur: knobRadius * 1.2, color: NSColor(hex: 0xFF4A75, alpha: 0.18).cgColor)
        context.fillEllipse(in: knobRect)
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: knobRect)
        context.clip()
        context.drawLinearGradient(
            rgbGradient(colors: [
                NSColor(hex: 0xFF6483),
                NSColor(hex: 0xFF336C),
            ], locations: [0.0, 1.0]),
            start: CGPoint(x: knobRect.midX, y: knobRect.maxY),
            end: CGPoint(x: knobRect.midX, y: knobRect.minY),
            options: []
        )
        context.restoreGState()
    }
}

private func drawIcon(in context: CGContext, canvas: CGRect) {
    let size = canvas.width
    let detailLevel = DetailLevel.forCanvasSize(size)
    let inset = size * (detailLevel == .tiny ? 0.085 : 0.075)
    let iconRect = canvas.insetBy(dx: inset, dy: inset)
    let radius = iconRect.width * 0.19
    let iconPath = roundedPath(in: iconRect, radius: radius)

    context.clear(canvas)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.02),
        blur: size * (detailLevel == .tiny ? 0.04 : 0.08),
        color: NSColor(hex: 0x05070B, alpha: 0.45).cgColor
    )
    context.addPath(iconPath)
    context.setFillColor(NSColor(hex: 0x151923).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(iconPath)
    context.clip()
    context.drawLinearGradient(
        rgbGradient(
            colors: [
                NSColor(hex: 0x2F3540),
                NSColor(hex: 0x1B2028),
                NSColor(hex: 0x12161D),
            ],
            locations: [0.0, 0.48, 1.0]
        ),
        start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
        options: []
    )

    let blushRect = CGRect(
        x: iconRect.minX - iconRect.width * 0.15,
        y: iconRect.midY,
        width: iconRect.width * 0.95,
        height: iconRect.height * 0.7
    )
    context.drawRadialGradient(
        rgbGradient(
            colors: [
                NSColor(hex: 0xB03557, alpha: 0.14),
                NSColor(hex: 0xB03557, alpha: 0.0),
            ],
            locations: [0.0, 1.0]
        ),
        startCenter: CGPoint(x: blushRect.midX, y: blushRect.midY),
        startRadius: 0,
        endCenter: CGPoint(x: blushRect.midX, y: blushRect.midY),
        endRadius: blushRect.width * 0.72,
        options: []
    )

    let topSheenRect = CGRect(
        x: iconRect.minX,
        y: iconRect.midY,
        width: iconRect.width,
        height: iconRect.height * 0.55
    )
    context.drawLinearGradient(
        rgbGradient(
            colors: [
                NSColor(hex: 0xFFFFFF, alpha: 0.10),
                NSColor(hex: 0xFFFFFF, alpha: 0.02),
                NSColor(hex: 0xFFFFFF, alpha: 0.0),
            ],
            locations: [0.0, 0.45, 1.0]
        ),
        start: CGPoint(x: topSheenRect.midX, y: topSheenRect.maxY),
        end: CGPoint(x: topSheenRect.midX, y: topSheenRect.minY),
        options: []
    )
    context.restoreGState()

    drawScreenGrid(context: context, rect: iconRect, clipPath: iconPath, size: size, detailLevel: detailLevel)

    context.addPath(iconPath)
    context.setStrokeColor(NSColor(hex: 0x0A0D12, alpha: 0.55).cgColor)
    context.setLineWidth(max(1, size * 0.0105))
    context.strokePath()

    context.addPath(iconPath)
    context.setStrokeColor(NSColor(hex: 0xFFFFFF, alpha: detailLevel == .tiny ? 0.08 : 0.11).cgColor)
    context.setLineWidth(max(1, size * 0.0038))
    context.strokePath()

    let pulseRect = CGRect(
        x: iconRect.minX + iconRect.width * 0.12,
        y: iconRect.minY + iconRect.height * 0.42,
        width: iconRect.width * 0.76,
        height: iconRect.height * 0.34
    )
    drawHeartbeat(context: context, rect: pulseRect, size: size, detailLevel: detailLevel)

    let controlsRect = CGRect(
        x: iconRect.minX + iconRect.width * 0.28,
        y: iconRect.minY + iconRect.height * 0.19,
        width: iconRect.width * 0.44,
        height: iconRect.height * 0.12
    )
    drawControlGlyph(context: context, rect: controlsRect, size: size, detailLevel: detailLevel)
}

private func writePNG(bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }
    try data.write(to: url)
}

private func renderIcons(outputDirectory: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for slot in iconSlots {
        let bitmap = try makeBitmap(size: slot.pixelSize) { context, canvas in
            drawIcon(in: context, canvas: canvas)
        }
        try writePNG(bitmap: bitmap, to: outputDirectory.appendingPathComponent(slot.filename))
    }
}

let outputPath: String
if let path = CommandLine.arguments.dropFirst().first {
    outputPath = path
} else {
    outputPath = "ATIL/Resources/Assets.xcassets/AppIcon.appiconset"
}

let outputURL = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

do {
    try renderIcons(outputDirectory: outputURL.standardizedFileURL)
    print("Generated app icons in \(outputURL.standardizedFileURL.path)")
} catch {
    fputs("Failed to generate app icons: \(error.localizedDescription)\n", stderr)
    exit(1)
}
