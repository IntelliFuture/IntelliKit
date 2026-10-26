import Foundation
import IntelliKit
import Testing

private struct UmbrellaConfiguration: Apply { var name = "old" }

@Test func umbrellaExposesFoundationAndImageAPI() {
  #expect(UmbrellaConfiguration().apply { $0.name = "new" }.name == "new")
  #expect(throws: ImageProcessingError.invalidData) { try ImageProcessor.inspect(Data()) }
  let options = ImageProcessingOptions(outputFormat: .png)
  #expect(options.maximumPixelSize == 2048)
  _ = NSObject().apply { _ in }
}
