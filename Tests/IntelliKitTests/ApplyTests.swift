import Foundation
import IntelliKitFoundation
import Testing

private struct Configuration: Apply { var count = 1 }
private final class Reference: NSObject { var count = 1 }
private enum Failure: Error { case expected }

@Test func valueConfigurationKeepsOriginal() throws {
  let original = Configuration()
  let result = original.apply { $0.count = 4 }
  #expect(original.count == 1)
  #expect(result.count == 4)
  #expect(throws: Failure.self) { try original.apply { _ in throw Failure.expected } }
}

@Test func referenceConfigurationKeepsIdentity() throws {
  let original = Reference()
  let result = original.apply { $0.count = 4 }
  #expect(result === original)
  #expect(original.count == 4)
  #expect(throws: Failure.self) { try original.apply { _ in throw Failure.expected } }
}
