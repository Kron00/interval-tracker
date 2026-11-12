import AppKit

let size = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let side = CGFloat(size)

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.02, green: 0.59, blue: 0.41, alpha: 1),
        CGColor(red: 0.01, green: 0.31, blue: 0.23, alpha: 1),
    ] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])

let center = CGPoint(x: side / 2, y: side / 2)
let radius = side * 0.31
let workSweep = CGFloat.pi * 2 * 0.17
let restSweep = CGFloat.pi * 2 * 0.08
context.setLineWidth(side * 0.085)
context.setLineCap(.round)

var angle = CGFloat.pi / 2 - restSweep / 2
for _ in 0..<4 {
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.addArc(
        center: center, radius: radius,
        startAngle: angle, endAngle: angle - workSweep, clockwise: true)
    context.strokePath()
    angle -= workSweep + restSweep
}

let playHeight = side * 0.2
let playWidth = playHeight * 0.87
let playLeft = center.x - playWidth * 0.38
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.move(to: CGPoint(x: playLeft, y: center.y + playHeight / 2))
context.addLine(to: CGPoint(x: playLeft + playWidth, y: center.y))
context.addLine(to: CGPoint(x: playLeft, y: center.y - playHeight / 2))
context.closePath()
context.fillPath()

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outputPath))
