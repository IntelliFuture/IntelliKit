private enum PreviousKey<Key> {
  case missing
  case value(Key)
}

/// Removes only consecutive equal keys, keeping the first element of each run.
public struct AsyncRemoveDuplicatesSequence<Base: AsyncSequence, Key: Equatable>: AsyncSequence {
  public typealias Element = Base.Element
  private let base: Base
  private let keyPath: KeyPath<Element, Key>

  public init(base: Base, by keyPath: KeyPath<Element, Key>) {
    self.base = base; self.keyPath = keyPath
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: Base.AsyncIterator
    private let keyPath: KeyPath<Element, Key>
    private var previous = PreviousKey<Key>.missing

    fileprivate init(iterator: Base.AsyncIterator, keyPath: KeyPath<Element, Key>) {
      self.iterator = iterator; self.keyPath = keyPath
    }

    /// Propagates upstream errors and checks cancellation even while discarding repeated elements.
    public mutating func next() async throws -> Element? {
      while true {
        try Task.checkCancellation()
        let next = try await iterator.next()
        try Task.checkCancellation()
        guard let element = next else { return nil }
        let key = element[keyPath: keyPath]
        if case let .value(old) = previous, old == key { continue }
        previous = .value(key)
        return element
      }
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(iterator: base.makeAsyncIterator(), keyPath: keyPath)
  }
}

public extension AsyncSequence {
  func removeDuplicates<Key: Equatable>(by keyPath: KeyPath<Element, Key>) -> AsyncRemoveDuplicatesSequence<Self, Key> {
    AsyncRemoveDuplicatesSequence(base: self, by: keyPath)
  }
}
