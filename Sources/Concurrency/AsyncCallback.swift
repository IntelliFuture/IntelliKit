import Foundation

/// An explicit, idempotent cancellation handle. Releasing it does not cancel the operation.
public final class CancellationHandle: Sendable {
  private let action: Locked<(@Sendable () -> Void)?>

  public init(_ cancel: @escaping @Sendable () -> Void) { action = Locked(cancel) }

  public func cancel() {
    let cancel = action.withLock { value in
      let cancel = value
      value = nil
      return cancel
    }
    cancel?()
  }
}

/// Adapts a one-shot callback API. The first callback or task cancellation wins.
/// Registration must return promptly; cancelling while it registers cancels its handle as soon as it arrives.
public enum AsyncCallback {
  public static func value<Value: Sendable>(
    start: @Sendable (@escaping @Sendable (Result<Value, Error>) -> Void) -> CancellationHandle?
  ) async throws -> Value {
    let state = CallbackState<Value>()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard state.install(continuation) else { return }
        let handle = start { state.complete($0) }
        state.register(handle)
      }
    } onCancel: {
      state.cancel()
    }
  }
}

private final class CallbackState<Value: Sendable>: Sendable {
  private struct State: Sendable {
    var continuation: CheckedContinuation<Value, Error>?
    var finished = false
    var handle: CancellationHandle?
    var wasCancelled = false
  }
  private let state = Locked(State())

  func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
    let canStart = state.withLock { state in
      if state.finished { return false }
      state.continuation = continuation
      return true
    }
    if !canStart { continuation.resume(throwing: CancellationError()) }
    return canStart
  }

  func register(_ handle: CancellationHandle?) {
    let shouldCancel = state.withLock { state in
      if state.wasCancelled { return true }
      if !state.finished { state.handle = handle }
      return false
    }
    if shouldCancel { handle?.cancel() }
  }

  func complete(_ result: Result<Value, Error>) {
    let pending = state.withLock { state -> (CheckedContinuation<Value, Error>?, CancellationHandle?) in
      guard !state.finished else { return (nil, nil) }
      state.finished = true
      let pending = (state.continuation, state.handle)
      state.continuation = nil
      state.handle = nil
      return pending
    }
    pending.0?.resume(with: result)
    withExtendedLifetime(pending.1) {}
  }

  func cancel() {
    let pending = state.withLock { state -> (CheckedContinuation<Value, Error>?, CancellationHandle?) in
      guard !state.finished else { return (nil, nil) }
      state.finished = true
      state.wasCancelled = true
      let pending = (state.continuation, state.handle)
      state.continuation = nil
      state.handle = nil
      return pending
    }
    // No user or framework code executes while our state lock is held.
    pending.0?.resume(throwing: CancellationError())
    pending.1?.cancel()
  }
}
