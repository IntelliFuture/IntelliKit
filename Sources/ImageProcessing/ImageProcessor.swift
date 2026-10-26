import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Synchronous CPU/file work. Call from an appropriate worker task, rather than a view's body.
/// This type does not fetch URLs, own source files, or select an App's privacy/upload policy.
public enum ImageProcessor {
  public static func inspect(_ data: Data, maximumInputBytes: Int = 20 * 1024 * 1024) throws -> ImageInfo {
    try info(source(data, maximumInputBytes: maximumInputBytes))
  }

  public static func inspect(fileURL: URL, maximumInputBytes: Int = 20 * 1024 * 1024) throws -> ImageInfo {
    try inspect(read(fileURL, maximumInputBytes: maximumInputBytes), maximumInputBytes: maximumInputBytes)
  }

  /// Returns an upright thumbnail of the first frame, without upscaling.
  public static func thumbnail(
    _ data: Data, maximumPixelSize: Int, maximumInputBytes: Int = 20 * 1024 * 1024
  ) throws -> CGImage {
    guard maximumPixelSize > 0 else { throw ImageProcessingError.invalidOptions }
    return try thumbnail(source(data, maximumInputBytes: maximumInputBytes), maximumPixelSize: maximumPixelSize)
  }

  public static func thumbnail(
    fileURL: URL, maximumPixelSize: Int, maximumInputBytes: Int = 20 * 1024 * 1024
  ) throws -> CGImage {
    try thumbnail(read(fileURL, maximumInputBytes: maximumInputBytes),
      maximumPixelSize: maximumPixelSize, maximumInputBytes: maximumInputBytes)
  }

  public static func process(_ data: Data, options: ImageProcessingOptions = .init()) throws -> ProcessedImage {
    try validate(options)
    let source = try source(data, maximumInputBytes: options.maximumInputBytes)
    let original = try info(source)
    try Task.checkCancellation()
    if original.frameCount > 1 {
      switch options.multipleFrames {
        case .reject: throw ImageProcessingError.multipleFramesNotAllowed
        case .preserveOriginal:
          return ProcessedImage(data: data, typeIdentifier: original.typeIdentifier,
            pixelSize: original.pixelSize, frameCount: original.frameCount, isOriginal: true)
      }
    }
    try Task.checkCancellation()
    var image = try thumbnail(source, maximumPixelSize: options.maximumPixelSize)
    let outputType: UTType
    var properties: [CFString: Any] = [:]
    if options.metadata == .preserve {
      let originalProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
      for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                  kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
        properties[key] = originalProperties[key]
      }
      if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
        tiff[kCGImagePropertyTIFFOrientation] = nil
        properties[kCGImagePropertyTIFFDictionary] = tiff
      }
      if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        exif[kCGImagePropertyExifPixelXDimension] = image.width
        exif[kCGImagePropertyExifPixelYDimension] = image.height
        properties[kCGImagePropertyExifDictionary] = exif
      }
    }
    switch options.outputFormat {
      case .png: outputType = .png
      case let .jpeg(quality, background):
        outputType = .jpeg
        image = try flatten(image, background: background)
        properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    properties[kCGImagePropertyOrientation] = 1
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, outputType.identifier as CFString, 1, nil) else {
      throw ImageProcessingError.encodingFailed
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.encodingFailed }
    try Task.checkCancellation()
    return ProcessedImage(data: output as Data, typeIdentifier: outputType.identifier,
      pixelSize: .init(width: image.width, height: image.height), frameCount: 1, isOriginal: false)
  }

  public static func process(fileURL: URL, options: ImageProcessingOptions = .init()) throws -> ProcessedImage {
    try validate(options)
    return try process(read(fileURL, maximumInputBytes: options.maximumInputBytes), options: options)
  }

  private static func read(_ url: URL, maximumInputBytes: Int) throws -> Data {
    guard maximumInputBytes > 0 else { throw ImageProcessingError.invalidOptions }
    guard url.isFileURL else { throw ImageProcessingError.fileURLRequired }
    try Task.checkCancellation()
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard let size, size <= maximumInputBytes else { throw ImageProcessingError.inputTooLarge }
    // Source ownership and security-scoped access belong to the caller. Recheck the mapped size below.
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count <= maximumInputBytes else { throw ImageProcessingError.inputTooLarge }
    try Task.checkCancellation()
    return data
  }

  private static func source(_ data: Data, maximumInputBytes: Int) throws -> CGImageSource {
    guard maximumInputBytes > 0 else { throw ImageProcessingError.invalidOptions }
    try Task.checkCancellation()
    guard data.count <= maximumInputBytes else { throw ImageProcessingError.inputTooLarge }
    guard !data.isEmpty,
      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      CGImageSourceGetCount(source) > 0 else { throw ImageProcessingError.invalidData }
    return source
  }

  private static func info(_ source: CGImageSource) throws -> ImageInfo {
    guard let type = CGImageSourceGetType(source),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0, height > 0 else { throw ImageProcessingError.invalidData }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let swapsAxes = (5...8).contains(orientation)
    return ImageInfo(typeIdentifier: type as String,
      pixelSize: .init(width: swapsAxes ? height : width, height: swapsAxes ? width : height),
      frameCount: CGImageSourceGetCount(source), orientation: orientation)
  }

  private static func thumbnail(_ source: CGImageSource, maximumPixelSize: Int) throws -> CGImage {
    try Task.checkCancellation()
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ] as CFDictionary) else { throw ImageProcessingError.invalidData }
    try Task.checkCancellation()
    return image
  }

  private static func flatten(_ image: CGImage, background: RGBColor) throws -> CGImage {
    guard let context = CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ImageProcessingError.encodingFailed }
    context.setFillColor(CGColor(red: background.red, green: background.green, blue: background.blue, alpha: 1))
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.fill(bounds)
    context.draw(image, in: bounds)
    guard let result = context.makeImage() else { throw ImageProcessingError.encodingFailed }
    return result
  }

  private static func validate(_ options: ImageProcessingOptions) throws {
    guard options.maximumPixelSize > 0, options.maximumInputBytes > 0 else {
      throw ImageProcessingError.invalidOptions
    }
    if case let .jpeg(quality, background) = options.outputFormat {
      guard [quality, background.red, background.green, background.blue].allSatisfy({
        $0.isFinite && (0...1).contains($0)
      }) else { throw ImageProcessingError.invalidOptions }
    }
  }
}
