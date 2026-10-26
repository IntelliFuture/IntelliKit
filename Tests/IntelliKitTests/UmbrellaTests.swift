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
  #expect(Locked(1).withLock { $0 + 1 } == 2)
}

@Test func umbrellaExposesConcurrencyAndOwnedWorkspace() async throws {
  let result: Int = try await AsyncCallback.value { callback in callback(.success(3)); return nil }
  #expect(result == 3)
  let workspace = try TemporaryWorkspace()
  defer { try? workspace.cleanup() }
  let url = try workspace.write(Data("umbrella".utf8), named: "example.txt")
  #expect(try Data(contentsOf: url) == Data("umbrella".utf8))
  let values = AsyncStream<Int> { continuation in
    continuation.yield(1); continuation.yield(1); continuation.finish()
  }
  var output: [Int] = []
  for try await value in values.removeDuplicates(by: \.self) { output.append(value) }
  #expect(output == [1])
}
