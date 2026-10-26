import Foundation

public struct ImagePixelSize: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public struct ImageInfo: Equatable, Sendable {
  public let typeIdentifier: String
  /// Display dimensions after applying EXIF orientation.
  public let pixelSize: ImagePixelSize
  public let frameCount: Int
  public let orientation: Int
}

public struct RGBColor: Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public init(red: Double, green: Double, blue: Double) {
    self.red = red; self.green = green; self.blue = blue
  }
  public static let white = RGBColor(red: 1, green: 1, blue: 1)
}

public enum ImageOutputFormat: Equatable, Sendable {
  /// JPEG cannot preserve alpha; transparent pixels are composited over the supplied color.
  case jpeg(quality: Double = 0.8, background: RGBColor = .white)
  case png
}

public enum ImageMetadataPolicy: Sendable {
  case strip
  /// Preserves supported EXIF/GPS/IPTC/TIFF dictionaries, updating orientation and pixel dimensions.
  case preserve
}

public enum MultipleFramePolicy: Sendable {
  case reject
  /// Bypasses conversion, metadata stripping and resizing for sources with multiple frames.
  /// The result's isOriginal flag explicitly reports this behavior.
  case preserveOriginal
}

public struct ImageProcessingOptions: Sendable {
  public var maximumPixelSize: Int
  public var maximumInputBytes: Int
  public var outputFormat: ImageOutputFormat
  public var metadata: ImageMetadataPolicy
  public var multipleFrames: MultipleFramePolicy

  public init(
    maximumPixelSize: Int = 2048,
    maximumInputBytes: Int = 20 * 1024 * 1024,
    outputFormat: ImageOutputFormat = .jpeg(),
    metadata: ImageMetadataPolicy = .strip,
    multipleFrames: MultipleFramePolicy = .reject
  ) {
    self.maximumPixelSize = maximumPixelSize
    self.maximumInputBytes = maximumInputBytes
    self.outputFormat = outputFormat
    self.metadata = metadata
    self.multipleFrames = multipleFrames
  }
}

public enum ImageProcessingError: Error, Equatable {
  case invalidOptions
  case invalidData
  case inputTooLarge
  case fileURLRequired
  case multipleFramesNotAllowed
  case encodingFailed
}

public struct ProcessedImage: Sendable {
  public let data: Data
  public let typeIdentifier: String
  public let pixelSize: ImagePixelSize
  public let frameCount: Int
  public let isOriginal: Bool
}
