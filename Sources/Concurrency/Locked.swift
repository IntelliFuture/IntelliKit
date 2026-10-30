import Foundation
#if canImport(Synchronization)
import Synchronization
#endif

/// Short synchronous critical sections. Neither backend permits recursive locking or suspension.
public final class Locked<Value: Sendable>: Sendable {
  private let storage: LockStorage<Value>

  public convenience init(_ value: Value) { self.init(value, useLegacyLock: false) }

  // Exercises the fallback on modern test hosts without changing the public API.
  init(_ value: Value, useLegacyLock: Bool) {
    #if canImport(Synchronization)
    if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *), !useLegacyLock {
      storage = MutexStorage(value)
      return
    }
    #endif
    storage = NSLockStorage(value)
  }

  /// Throwing releases the lock; mutations made before the throw remain visible.
  public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try storage.withLock(body)
  }
}

private class LockStorage<Value: Sendable>: @unchecked Sendable {
  func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    fatalError("Abstract lock storage")
  }
}

private final class NSLockStorage<Value: Sendable>: LockStorage<Value>, @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value
  init(_ value: Value) { self.value = value }
  override func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}

#if canImport(Synchronization)
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
private final class MutexStorage<Value: Sendable>: LockStorage<Value>, @unchecked Sendable {
  private let mutex: Mutex<Value>
  init(_ value: Value) { mutex = Mutex(value) }
  override func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try mutex.withLock { value in try body(&value) }
  }
}
#endif
