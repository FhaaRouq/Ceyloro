import Foundation
import CoreGraphics

public enum PNGQuantizer {
    private struct ColorBin {
        var r: UInt32
        var g: UInt32
        var b: UInt32
        var count: UInt32
    }

    private struct Box {
        var bins: [ColorBin]
        var count: UInt32

        var rMin: UInt8
        var rMax: UInt8
        var gMin: UInt8
        var gMax: UInt8
        var bMin: UInt8
        var bMax: UInt8

        init(bins: [ColorBin]) {
            self.bins = bins
            var total: UInt32 = 0
            var r0: UInt8 = 255, r1: UInt8 = 0
            var g0: UInt8 = 255, g1: UInt8 = 0
            var b0: UInt8 = 255, b1: UInt8 = 0
            for bin in bins {
                total += bin.count
                let r = UInt8(bin.r)
                let g = UInt8(bin.g)
                let b = UInt8(bin.b)
                if r < r0 { r0 = r }
                if r > r1 { r1 = r }
                if g < g0 { g0 = g }
                if g > g1 { g1 = g }
                if b < b0 { b0 = b }
                if b > b1 { b1 = b }
            }
            self.count = total
            self.rMin = r0; self.rMax = r1
            self.gMin = g0; self.gMax = g1
            self.bMin = b0; self.bMax = b1
        }

        var volume: Int {
            let dr = Int(rMax) - Int(rMin)
            let dg = Int(gMax) - Int(gMin)
            let db = Int(bMax) - Int(bMin)
            return max(dr, max(dg, db))
        }

        func split() -> (Box, Box)? {
            guard bins.count > 1 else { return nil }
            let dr = Int(rMax) - Int(rMin)
            let dg = Int(gMax) - Int(gMin)
            let db = Int(bMax) - Int(bMin)

            var sortedBins = bins
            if dr >= dg && dr >= db {
                sortedBins.sort { $0.r < $1.r }
            } else if dg >= dr && dg >= db {
                sortedBins.sort { $0.g < $1.g }
            } else {
                sortedBins.sort { $0.b < $1.b }
            }

            let halfCount = count / 2
            var currentCount: UInt32 = 0
            var splitIndex = 1
            for (idx, bin) in sortedBins.enumerated() {
                currentCount += bin.count
                if currentCount >= halfCount && idx > 0 {
                    splitIndex = idx
                    break
                }
            }

            let leftBins = Array(sortedBins[..<splitIndex])
            let rightBins = Array(sortedBins[splitIndex...])
            guard !leftBins.isEmpty && !rightBins.isEmpty else { return nil }
            return (Box(bins: leftBins), Box(bins: rightBins))
        }

        var averageColor: (r: UInt8, g: UInt8, b: UInt8) {
            guard count > 0 else { return (0, 0, 0) }
            var rSum: UInt64 = 0
            var gSum: UInt64 = 0
            var bSum: UInt64 = 0
            for bin in bins {
                rSum += UInt64(bin.r) * UInt64(bin.count)
                gSum += UInt64(bin.g) * UInt64(bin.count)
                bSum += UInt64(bin.b) * UInt64(bin.count)
            }
            return (
                r: UInt8(min(rSum / UInt64(count), 255)),
                g: UInt8(min(gSum / UInt64(count), 255)),
                b: UInt8(min(bSum / UInt64(count), 255))
            )
        }
    }

    /// Quantize a 32-bit RGBA CGImage into an 8-bit Indexed CGImage with palette.
    /// Preserves transparency if the source image contains transparent pixels.
    public static func quantize(image: CGImage, maxColors: Int = 256) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var rawPixels = [UInt32](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &rawPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Check transparency and build histogram with 5-bit color quantization bins
        var hasTransparency = false
        var histogram: [UInt16: UInt32] = [:]

        for pixel in rawPixels {
            let a = UInt8((pixel >> 24) & 0xFF)
            if a < 32 {
                hasTransparency = true
                continue
            }
            // Un-premultiply RGB if needed
            let rRaw = (pixel & 0xFF)
            let gRaw = ((pixel >> 8) & 0xFF)
            let bRaw = ((pixel >> 16) & 0xFF)

            let r = UInt8(min(255, (rRaw * 255) / UInt32(a)))
            let g = UInt8(min(255, (gRaw * 255) / UInt32(a)))
            let b = UInt8(min(255, (bRaw * 255) / UInt32(a)))

            // 5-bit key
            let key = (UInt16(r >> 3) << 10) | (UInt16(g >> 3) << 5) | UInt16(b >> 3)
            histogram[key, default: 0] += 1
        }

        // Available palette slots (slot 0 reserved for transparency if present)
        let paletteCapacity = hasTransparency ? maxColors - 1 : maxColors
        var bins: [ColorBin] = []
        bins.reserveCapacity(histogram.count)
        for (key, count) in histogram {
            let r = UInt32((key >> 10) & 0x1F) << 3
            let g = UInt32((key >> 5) & 0x1F) << 3
            let b = UInt32(key & 0x1F) << 3
            bins.append(ColorBin(r: r, g: g, b: b, count: count))
        }

        var palette: [(r: UInt8, g: UInt8, b: UInt8)] = []
        if hasTransparency {
            // Index 0: Transparent (Black placeholder)
            palette.append((0, 0, 0))
        }

        if bins.count <= paletteCapacity {
            for bin in bins {
                palette.append((UInt8(bin.r), UInt8(bin.g), UInt8(bin.b)))
            }
        } else {
            var boxes = [Box(bins: bins)]
            while boxes.count < paletteCapacity {
                // Find box with largest volume
                var bestIdx = -1
                var bestVolume = -1
                for (i, box) in boxes.enumerated() {
                    let v = box.volume
                    if v > bestVolume && box.bins.count > 1 {
                        bestVolume = v
                        bestIdx = i
                    }
                }
                guard bestIdx >= 0, let (box1, box2) = boxes[bestIdx].split() else { break }
                boxes.remove(at: bestIdx)
                boxes.append(box1)
                boxes.append(box2)
            }
            for box in boxes {
                palette.append(box.averageColor)
            }
        }

        // Pad palette to 256 entries if needed
        while palette.count < 256 {
            palette.append((0, 0, 0))
        }

        // Build 256*3 byte table for indexed color space
        var colorTable = [UInt8](repeating: 0, count: 256 * 3)
        for i in 0..<256 {
            colorTable[i * 3 + 0] = palette[i].r
            colorTable[i * 3 + 1] = palette[i].g
            colorTable[i * 3 + 2] = palette[i].b
        }

        guard let indexedSpace = CGColorSpace(indexedBaseSpace: colorSpace, last: 255, colorTable: &colorTable) else {
            return nil
        }

        // Map pixels to palette indices
        var indexedData = [UInt8](repeating: 0, count: width * height)
        let startIndex = hasTransparency ? 1 : 0
        let availableCount = palette.count

        for i in 0..<rawPixels.count {
            let pixel = rawPixels[i]
            let a = UInt8((pixel >> 24) & 0xFF)
            if hasTransparency && a < 32 {
                indexedData[i] = 0
                continue
            }
            let rRaw = (pixel & 0xFF)
            let gRaw = ((pixel >> 8) & 0xFF)
            let bRaw = ((pixel >> 16) & 0xFF)

            let r = a > 0 ? Int((rRaw * 255) / UInt32(a)) : 0
            let g = a > 0 ? Int((gRaw * 255) / UInt32(a)) : 0
            let b = a > 0 ? Int((bRaw * 255) / UInt32(a)) : 0

            var bestDist = Int.max
            var bestIdx = startIndex
            for pIdx in startIndex..<availableCount {
                let pr = Int(palette[pIdx].r)
                let pg = Int(palette[pIdx].g)
                let pb = Int(palette[pIdx].b)
                let dr = r - pr
                let dg = g - pg
                let db = b - pb
                // Perceptually weighted squared distance
                let dist = dr * dr * 2 + dg * dg * 4 + db * db * 3
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = pIdx
                    if dist == 0 { break }
                }
            }
            indexedData[i] = UInt8(bestIdx)
        }

        guard let indexedContext = CGContext(
            data: &indexedData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: indexedSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        return indexedContext.makeImage()
    }
}
