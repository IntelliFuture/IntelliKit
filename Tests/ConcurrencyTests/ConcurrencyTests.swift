import Dispatch
import Foundation
@testable import IntelliKitConcurrency
import Testing

private enum Failure: Error { case expected }
private final class Payload: Sendable {}

private struct WaitingSequence: AsyncSequence, Sendable {
  typealias Element = Int
  let stream: AsyncStream<Int>
  let onNext: @Sendable () -> Void
  struct AsyncIterator: AsyncIteratorProtocol {
    var base: AsyncStream<Int>.AsyncIterator
    let onNext: @Sendable () -> Void
    mutating func next() async -> Int? { onNext(); return await base.next() }
  }
  func makeAsyncIterator() -> AsyncIterator { .init(base: stream.makeAsyncIterator(), onNext: onNext) }
}

private struct Signal: Sendable {
  let stream: AsyncStream<Void>
  let continuation: AsyncStream<Void>.Continuation
  init() {
    let slot = Locked<AsyncStream<Void>.Continuation?>(nil)
    stream = AsyncStream { continuation in slot.withLock { $0 = continuation } }
    continuation = slot.withLock { $0! }
  }
  func fire() { continuation.yield(()); continuation.finish() }
  func wait() async { for await _ in stream { return } }
}

@Test(arguments: [false, true]) func lockedStateSurvivesConcurrentUpdatesAndThrows(useLegacyLock: Bool) throws {
  let value = Locked(0, useLegacyLock: useLegacyLock)
  DispatchQueue.concurrentPerform(iterations: 1000) { _ in value.withLock { $0 += 1 } }
  #expect(value.withLock { $0 } == 1000)
  #expect(throws: Failure.self) {
    try value.withLock { value in value += 1; throw Failure.expected }
  }
  #expect(value.withLock { $0 } == 1001)
}

@Test func cancellationHandleRunsOnceAndCanReenter() {
  let calls = Locked(0)
  let slot = Locked<CancellationHandle?>(nil)
  let handle = CancellationHandle {
    calls.withLock { $0 += 1 }
    slot.withLock { $0 }?.cancel()
  }
  slot.withLock { $0 = handle }
  DispatchQueue.concurrentPerform(iterations: 100) { _ in handle.cancel() }
  #expect(calls.withLock { $0 } == 1)
  slot.withLock { $0 = nil }
}

@Test func synchronousCompletionAndDuplicateCallbackKeepFirstValue() async throws {
  let cancelled = Locked(0)
  let value: Int = try await AsyncCallback.value { callback in
    callback(.success(7))
    callback(.success(9))
    return CancellationHandle { cancelled.withLock { $0 += 1 } }
  }
  #expect(value == 7)
  #expect(cancelled.withLock { $0 } == 0)
}

@Test func callbackFailurePropagates() async {
  do {
    let _: Int = try await AsyncCallback.value { callback in callback(.failure(Failure.expected)); return nil }
    Issue.record("Unexpected success")
  } catch is Failure {} catch { Issue.record("Unexpected error: \(error)") }
}

@Test func alreadyCancelledTaskDoesNotRegister() async {
  let starts = Locked(0)
  let task = Task.detached {
    withUnsafeCurrentTask { $0?.cancel() }
    let _: Int = try await AsyncCallback.value { callback in
      starts.withLock { $0 += 1 }; callback(.success(1)); return nil
    }
  }
  do { try await task.value; Issue.record("Unexpected success") } catch is CancellationError {} catch {
    Issue.record("Unexpected error: \(error)")
  }
  #expect(starts.withLock { $0 } == 0)
}

@Test
func cancellationDuringRegistrationCancelsLateHandleAndIgnoresCallback() async {
  let calls = Locked(0)
  let callbackSlot = Locked<(@Sendable (Result<Int, Error>) -> Void)?>(nil)
  let task = Task.detached {
    try await AsyncCallback.value { callback -> CancellationHandle? in
      callbackSlot.withLock { $0 = callback }
      // Cancel from inside registration, before its handle exists. No timing or blocking wait.
      withUnsafeCurrentTask { $0?.cancel() }
      return CancellationHandle {
        calls.withLock { $0 += 1 }
        callback(.success(999)) // A framework cancellation callback must not deadlock or resume twice.
      }
    }
  }
  do { let _: Int = try await task.value; Issue.record("Unexpected success") } catch is CancellationError {} catch {
    Issue.record("Unexpected error: \(error)")
  }
  callbackSlot.withLock { $0 }?(.success(1000))
  #expect(calls.withLock { $0 } == 1)
}

@Test(.timeLimit(.minutes(1)))
func concurrentCallbacksResumeOnlyOnce() async throws {
  let value: Int = try await AsyncCallback.value { callback in
    DispatchQueue.concurrentPerform(iterations: 100) { index in callback(.success(index)) }
    return nil
  }
  #expect((0..<100).contains(value))
}

@Test(.timeLimit(.minutes(1)))
func cancellationOfRegisteredOperationWorksWithoutAnyCompletion() async {
  let registered = Signal()
  let cancelled = Signal()
  let task = Task.detached {
    let _: Int = try await AsyncCallback.value { _ in
      registered.fire()
      return CancellationHandle { cancelled.fire() }
    }
  }
  await registered.wait()
  task.cancel()
  do { try await task.value; Issue.record("Unexpected success") } catch is CancellationError {} catch {
    Issue.record("Unexpected error: \(error)")
  }
  await cancelled.wait()
}

@Test(.timeLimit(.minutes(1)))
func callbackAndCancellationRaceHasOneTerminalResult() async throws {
  for index in 0..<100 {
    let registered = Signal()
    let callbackSlot = Locked<(@Sendable (Result<Int, Error>) -> Void)?>(nil)
    let cancellations = Locked(0)
    let task = Task.detached {
      try await AsyncCallback.value { callback -> CancellationHandle? in
        callbackSlot.withLock { $0 = callback }
        registered.fire()
        return CancellationHandle { cancellations.withLock { $0 += 1 } }
      }
    }
    await registered.wait()
    DispatchQueue.concurrentPerform(iterations: 2) { branch in
      if branch == 0 { task.cancel() } else { callbackSlot.withLock { $0 }?(.success(index)) }
    }
    do { let value: Int = try await task.value; #expect(value == index) } catch is CancellationError {}
    #expect((0...1).contains(cancellations.withLock { $0 }))
  }
}

@Test func completedValueIsNotKeptAliveByRetainedCallback() async throws {
  let callbackSlot = Locked<(@Sendable (Result<Payload, Error>) -> Void)?>(nil)
  var value: Payload? = try await AsyncCallback.value { callback in
    callbackSlot.withLock { $0 = callback }
    callback(.success(Payload()))
    return nil
  }
  weak var weakValue = value
  #expect(weakValue != nil)
  value = nil
  #expect(weakValue == nil)
  weakValue = nil
  // A framework can retain its callback after completion; no successful payload should be retained with it.
  callbackSlot.withLock { $0 = nil }
}

@Test(.timeLimit(.minutes(1)))
func cancellingPendingSequenceDoesNotBecomeNormalEndOfStream() async {
  let entered = Signal()
  let slot = Locked<AsyncStream<Int>.Continuation?>(nil)
  let stream = AsyncStream<Int> { continuation in slot.withLock { $0 = continuation } }
  let sequence = WaitingSequence(stream: stream, onNext: { entered.fire() })
  let task = Task.detached {
    var iterator = sequence.removeDuplicates(by: \.self).makeAsyncIterator()
    return try await iterator.next()
  }
  await entered.wait()
  task.cancel()
  do { _ = try await task.value; Issue.record("Cancellation was hidden as normal completion") } catch is CancellationError {} catch {
    Issue.record("Unexpected error: \(error)")
  }
  slot.withLock { $0 }?.finish()
}
