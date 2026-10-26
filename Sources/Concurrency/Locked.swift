import Foundation

/// Short, synchronous access to Sendable state, with an iOS 16-compatible implementation.
/// Do not suspend, recursively lock, or call arbitrary callbacks inside withLock.
public final class Locked<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  public init(_ value: Value) { self.value = value }

  /// Throwing releases the lock; mutations made before the throw remain visible.
  public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}
