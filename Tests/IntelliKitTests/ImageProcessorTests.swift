import CoreGraphics
import Foundation
import ImageIO
import IntelliKitImageProcessing
import Testing
import UniformTypeIdentifiers

private func fixture(
  width: Int = 120, height: Int = 60, orientation: Int = 1,
  transparent: Bool = false, frames: Int = 1, withGPS: Bool = false
) throws -> Data {
  let context = try #require(CGContext(data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  if !transparent {
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  }
  let image = try #require(context.makeImage())
  let data = NSMutableData()
  let type = frames > 1 ? UTType.gif : UTType.tiff
  let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil))
  var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
  if withGPS {
    properties[kCGImagePropertyGPSDictionary] = [
      kCGImagePropertyGPSLatitude: 35.0, kCGImagePropertyGPSLatitudeRef: "N",
      kCGImagePropertyGPSLongitude: 139.0, kCGImagePropertyGPSLongitudeRef: "E",
    ]
    properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2026:10:26 12:00:00"]
  }
  for _ in 0..<frames { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
  #expect(CGImageDestinationFinalize(destination))
  return data as Data
}

private func properties(_ data: Data) throws -> [CFString: Any] {
  let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
  return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

@Test func orientationAndThumbnailDimensions() throws {
  let data = try fixture(orientation: 6)
  let info = try ImageProcessor.inspect(data)
  #expect(info.pixelSize == ImagePixelSize(width: 60, height: 120))
  let thumbnail = try ImageProcessor.thumbnail(data, maximumPixelSize: 40)
  #expect(thumbnail.width == 20)
  #expect(thumbnail.height == 40)
  let result = try ImageProcessor.process(data, options: .init(maximumPixelSize: 40, outputFormat: .png))
  #expect(result.pixelSize == ImagePixelSize(width: 20, height: 40))
  #expect(try ImageProcessor.inspect(result.data).pixelSize == result.pixelSize)
}

@Test func smallerImageIsNotUpscaled() throws {
  let result = try ImageProcessor.process(fixture(width: 8, height: 4), options: .init(maximumPixelSize: 100))
  #expect(result.pixelSize == ImagePixelSize(width: 8, height: 4))
}

@Test func rejectsInvalidDataLimitsAndOptions() throws {
  #expect(throws: ImageProcessingError.invalidData) { try ImageProcessor.inspect(Data([0, 1, 2])) }
  #expect(throws: ImageProcessingError.invalidOptions) { try ImageProcessor.thumbnail(Data(), maximumPixelSize: 0) }
  let data = try fixture()
  #expect(throws: ImageProcessingError.inputTooLarge) { try ImageProcessor.inspect(data, maximumInputBytes: data.count - 1) }
  #expect(throws: ImageProcessingError.invalidOptions) {
    try ImageProcessor.process(data, options: .init(outputFormat: .jpeg(quality: .nan)))
  }
  #expect(throws: ImageProcessingError.invalidOptions) {
    try ImageProcessor.process(data, options: .init(outputFormat: .jpeg(background: .init(red: -1, green: 0, blue: 0))))
  }
}

@Test func transparentPixelsHaveExplicitOutputPolicy() throws {
  let data = try fixture(width: 4, height: 4, transparent: true)
  let png = try ImageProcessor.process(data, options: .init(outputFormat: .png))
  let pngProperties = try properties(png.data)
  #expect((pngProperties[kCGImagePropertyHasAlpha] as? Bool) == true)
  let pngImage = try ImageProcessor.thumbnail(png.data, maximumPixelSize: 4)
  var alpha = [UInt8](repeating: 0, count: 4)
  try alpha.withUnsafeMutableBytes { bytes in
    let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1,
      bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(pngImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
  }
  #expect(alpha[3] == 0)
  let jpeg = try ImageProcessor.process(data)
  #expect(jpeg.typeIdentifier == UTType.jpeg.identifier)
  let image = try ImageProcessor.thumbnail(jpeg.data, maximumPixelSize: 4)
  var rgba = [UInt8](repeating: 0, count: 4)
  try rgba.withUnsafeMutableBytes { bytes in
    let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1,
      bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
  }
  #expect(rgba[0] > 245 && rgba[1] > 245 && rgba[2] > 245)
}

@Test func multiframeRequiresExplicitPolicyAndPreservesBytes() throws {
  let data = try fixture(frames: 2)
  #expect(throws: ImageProcessingError.multipleFramesNotAllowed) { try ImageProcessor.process(data) }
  let result = try ImageProcessor.process(data, options: .init(maximumPixelSize: 10, multipleFrames: .preserveOriginal))
  #expect(result.data == data)
  #expect(result.frameCount == 2)
  #expect(result.isOriginal)
  #expect(result.pixelSize == ImagePixelSize(width: 120, height: 60))
}

@Test func metadataPoliciesStripOrPreserveGPS() throws {
  let data = try fixture(orientation: 6, withGPS: true)
  #expect(try properties(data)[kCGImagePropertyGPSDictionary] != nil)
  let stripped = try ImageProcessor.process(data)
  #expect(try properties(stripped.data)[kCGImagePropertyGPSDictionary] == nil)
  let preserved = try ImageProcessor.process(data, options: .init(maximumPixelSize: 40, metadata: .preserve))
  let values = try properties(preserved.data)
  #expect(values[kCGImagePropertyGPSDictionary] != nil)
  #expect((values[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 == 1)
  #expect(try ImageProcessor.inspect(preserved.data).pixelSize == ImagePixelSize(width: 20, height: 40))
}

@Test func localFileProcessingPreservesOriginalAndEnforcesLimit() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("source.tiff")
  let data = try fixture()
  try data.write(to: url)
  #expect(try ImageProcessor.inspect(fileURL: url).pixelSize == ImagePixelSize(width: 120, height: 60))
  let result = try ImageProcessor.process(fileURL: url)
  #expect(result.typeIdentifier == UTType.jpeg.identifier)
  #expect(try Data(contentsOf: url) == data)
  #expect(throws: ImageProcessingError.inputTooLarge) { try ImageProcessor.inspect(fileURL: url, maximumInputBytes: 1) }
  #expect(throws: ImageProcessingError.fileURLRequired) {
    try ImageProcessor.inspect(fileURL: URL(string: "https://example.invalid/image.png")!)
  }
}

@Test func cancelledTaskDoesNotProcessImage() async throws {
  let data = try fixture()
  let task = Task { () throws -> ProcessedImage in
    withUnsafeCurrentTask { $0?.cancel() }
    return try ImageProcessor.process(data)
  }
  do {
    _ = try await task.value
    Issue.record("Cancelled image processing unexpectedly succeeded")
  } catch is CancellationError {
    // Expected; no network or external file fixture required.
  }
}
