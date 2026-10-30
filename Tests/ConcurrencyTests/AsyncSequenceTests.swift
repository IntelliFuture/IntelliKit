import IntelliKitConcurrency
import Testing

private struct Item: Sendable { let id: Int; let key: Int? }
private enum StreamFailure: Error { case expected }

private func items(_ values: [Item]) -> AsyncStream<Item> {
  AsyncStream { continuation in
    for value in values { continuation.yield(value) }
    continuation.finish()
  }
}

@Test func sequenceKeepsFirstNilAndOnlyRemovesConsecutiveDuplicates() async throws {
  let stream = items([
    Item(id: 1, key: nil), Item(id: 2, key: nil), Item(id: 3, key: 1),
    Item(id: 4, key: 1), Item(id: 5, key: nil), Item(id: 6, key: 1),
  ]).removeDuplicates(by: \.key)
  var ids: [Int] = []
  for try await value in stream { ids.append(value.id) }
  #expect(ids == [1, 3, 5, 6])
}

@Test func upstreamErrorsAreNotSwallowed() async {
  let stream = AsyncThrowingStream<Int, Error> { continuation in
    continuation.yield(1)
    continuation.finish(throwing: StreamFailure.expected)
  }
  var received: [Int] = []
  do {
    for try await value in stream.removeDuplicates(by: \.self) { received.append(value) }
    Issue.record("Expected upstream error")
  } catch is StreamFailure {} catch { Issue.record("Unexpected error: \(error)") }
  #expect(received == [1])
}

private struct ArraySequence<Element: Sendable>: AsyncSequence, Sendable {
  let elements: [Element]
  struct AsyncIterator: AsyncIteratorProtocol {
    var iterator: IndexingIterator<[Element]>
    mutating func next() async -> Element? { iterator.next() }
  }
  func makeAsyncIterator() -> AsyncIterator { AsyncIterator(iterator: elements.makeIterator()) }
}

@Test func eachIteratorHasIndependentHistory() async throws {
  let sequence = ArraySequence(elements: [1, 1, 2]).removeDuplicates(by: \.self)
  var first = sequence.makeAsyncIterator()
  var second = sequence.makeAsyncIterator()
  #expect(try await first.next() == 1)
  #expect(try await first.next() == 2)
  #expect(try await second.next() == 1)
  #expect(try await second.next() == 2)
  #expect(try await first.next() == nil)
}

@Test func cancelledIterationThrowsInsteadOfDrainingStream() async {
  let task = Task.detached {
    withUnsafeCurrentTask { $0?.cancel() }
    var iterator = ArraySequence(elements: [1, 1, 1]).removeDuplicates(by: \.self).makeAsyncIterator()
    return try await iterator.next()
  }
  do { _ = try await task.value; Issue.record("Unexpected success") } catch is CancellationError {} catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@MainActor
@Test func sequenceCanBeConsumedOnMainActor() async throws {
  let sequence = ArraySequence(elements: [1, 1, 2]).removeDuplicates(by: \.self)
  var output: [Int] = []
  for try await value in sequence { output.append(value) }
  #expect(output == [1, 2])
}
