import Foundation

/// Configuration helpers consolidated from EveryDayJapanese, NGAPlus and mtn.
/// The existing helpers reference the Then pattern: https://github.com/devxoul/Then.
public protocol Apply {}

public extension Apply {
  /// Returns a configured value copy. Reference-type members retain their usual reference semantics.
  @inlinable
  func apply(_ configure: (inout Self) throws -> Void) rethrows -> Self {
    var value = self
    try configure(&value)
    return value
  }
}

public extension Apply where Self: AnyObject {
  /// Configures and returns the same instance; mutations before a thrown error are not rolled back.
  @inlinable
  func apply(_ configure: (Self) throws -> Void) rethrows -> Self {
    try configure(self)
    return self
  }
}

extension NSObject: Apply {}
