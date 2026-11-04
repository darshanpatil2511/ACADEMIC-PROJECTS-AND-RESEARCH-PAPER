// Regenerate the icon: swiftc -O Tools/make_app_icon.swift -o /tmp/render && /tmp/render App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 1024×1024 CurbLens app icon: a parking sign inside camera viewfinder corners,
// with a green "you can park" check. Opaque (iOS applies the rounded mask itself).
let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
let S = CGFloat(size)

// Background gradient (top lighter blue to deep blue). CG origin is bottom-left.
let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x1F6BFF), rgb(0x0A2E8C)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Viewfinder corners.
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let inset: CGFloat = 150, arm: CGFloat = 150
for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (S - inset, inset, -1.0, 1.0),
                       (inset, S - inset, 1.0, -1.0), (S - inset, S - inset, -1.0, -1.0)] {
    ctx.move(to: CGPoint(x: x, y: y + dy * arm))
    ctx.addLine(to: CGPoint(x: x, y: y))
    ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
    ctx.strokePath()
}

// Parking sign: white rounded rectangle with a bold blue P.
let sign = CGRect(x: (S - 400) / 2, y: (S - 500) / 2, width: 400, height: 500)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.3))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(CGPath(roundedRect: sign, cornerWidth: 64, cornerHeight: 64, transform: nil))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

let font = CTFontCreateUIFontForLanguage(.system, 400, nil)!
let heavy = CTFontCreateCopyWithSymbolicTraits(font, 400, nil, .traitBold, .traitBold) ?? font
let text = NSAttributedString(string: "P", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): heavy,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0x0A47D6),
])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
ctx.textPosition = CGPoint(x: sign.midX - bounds.midX, y: sign.midY - bounds.midY)
CTLineDraw(line, ctx)

// Green check badge at the sign's bottom-right corner, ringed in the background blue.
let badge = CGPoint(x: sign.maxX - 10, y: sign.minY + 10)
ctx.setFillColor(rgb(0x0B3AA8))
ctx.fillEllipse(in: CGRect(x: badge.x - 118, y: badge.y - 118, width: 236, height: 236))
ctx.setFillColor(rgb(0x30C85A))
ctx.fillEllipse(in: CGRect(x: badge.x - 96, y: badge.y - 96, width: 192, height: 192))
ctx.setStrokeColor(rgb(0xFFFFFF))
ctx.setLineWidth(30)
ctx.move(to: CGPoint(x: badge.x - 44, y: badge.y + 2))
ctx.addLine(to: CGPoint(x: badge.x - 12, y: badge.y - 32))
ctx.addLine(to: CGPoint(x: badge.x + 46, y: badge.y + 36))
ctx.strokePath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
