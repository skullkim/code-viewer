// Reports the average alpha of a rectangle in a PNG, 0.00–1.00.
//
// Exists because the colour counter cannot answer the question an icon actually poses: is the
// corner transparent and the middle opaque. A counter that reads "0 colours" in a gradient
// says nothing about either, and that is what the icon self-test was doing before.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 6,
      let x = Int(args[2]), let y = Int(args[3]), let w = Int(args[4]), let h = Int(args[5]),
      let image = NSImage(contentsOfFile: args[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("사용법: probe-image-alpha.swift <png> <x> <y> <w> <h>\n".utf8))
    exit(2)
}

let scale = Double(cgImage.width) / Double(image.size.width)
let rect = CGRect(x: Double(x) * scale, y: Double(y) * scale,
                  width: Double(w) * scale, height: Double(h) * scale)
guard let cropped = cgImage.cropping(to: rect) else {
    FileHandle.standardError.write(Data("FAIL: 사각형이 이미지 밖이다 — 이미지 \(cgImage.width)x\(cgImage.height)\n".utf8))
    exit(2)
}

let width = cropped.width, height = cropped.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    // `premultipliedLast` because CoreGraphics refuses plain `.last` for 8-bit RGB — it returns
    // a nil context, and the first version of this exited on that with no message, which cost
    // two round trips to diagnose. Premultiplication folds alpha into the *colour* channels; the
    // alpha byte itself is untouched, and the alpha byte is all this reads.
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("FAIL: 비트맵 컨텍스트를 못 만들었다\n".utf8))
    exit(2)
}
context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

let total = pixels.enumerated().reduce(0.0) { sum, pair in
    pair.offset % 4 == 3 ? sum + Double(pair.element) : sum
}
print(String(format: "%.2f", total / Double(width * height) / 255.0))
