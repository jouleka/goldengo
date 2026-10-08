import AppKit
import CoreGraphics

// A reproducible, opaque app icon using Goldengo's existing warm ink and gold palette.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, 1])!
}
let background = CGGradient(colorsSpace: space,
                            colors: [color(42, 38, 32), color(23, 20, 15)] as CFArray,
                            locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: 1024),
                           end: CGPoint(x: 1024, y: 0), options: [])
context.setStrokeColor(color(224, 174, 74))
context.setLineWidth(86)
context.setLineCap(.round)
context.setLineJoin(.round)
context.addArc(center: CGPoint(x: 512, y: 512), radius: 246,
               startAngle: .pi / 4, endAngle: 7 * .pi / 4, clockwise: false)
context.addLine(to: CGPoint(x: 686, y: 512))
context.addLine(to: CGPoint(x: 544, y: 512))
context.strokePath()
let image = NSBitmapImageRep(cgImage: context.makeImage()!)
let output = CommandLine.arguments.dropFirst().first
    ?? "AppProject/Goldengo/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
