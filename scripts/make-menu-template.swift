import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make-menu-template.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let cropped = image.cropping(to: CGRect(x: 160, y: 320, width: 320, height: 320)) else {
    fputs("could not read or crop input image\n", stderr)
    exit(1)
}

let size = 128
let bytesPerRow = size * 4
var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
guard let context = CGContext(data: &pixels,
                              width: size,
                              height: size,
                              bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("could not create bitmap context\n", stderr)
    exit(1)
}

context.interpolationQuality = .high
context.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
for index in stride(from: 0, to: pixels.count, by: 4) {
    let luminance = (0.2126 * Double(pixels[index])) + (0.7152 * Double(pixels[index + 1])) + (0.0722 * Double(pixels[index + 2]))
    let alpha = UInt8(max(0, min(255, Int((255 - luminance) * 1.15))))
    pixels[index] = 255
    pixels[index + 1] = 255
    pixels[index + 2] = 255
    pixels[index + 3] = alpha
}

guard let outputContext = CGContext(data: &pixels,
                                    width: size,
                                    height: size,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let result = outputContext.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("could not write output image\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("could not finalize output image\n", stderr)
    exit(1)
}
