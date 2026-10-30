import Foundation

/// Programmer- or configuration-level failures building a lookup request.
public enum MoreAppsError: Error, Equatable, Sendable {
  case invalidDeveloperID
  case invalidLanguageCode
  case invalidLookupURL
}

/// The App Store lookup endpoint answered with a non-success HTTP status.
///
/// This is surfaced as its own type so callers (and the built-in language fallback) can react to a
/// specific status such as `400` without depending on the transport that produced it.
public struct MoreAppsHTTPStatusError: Error, Equatable, Sendable {
  public let statusCode: Int

  public init(statusCode: Int) {
    self.statusCode = statusCode
  }
}

/// Stable, log-safe classification of a lookup failure. Callers map these to analytics or UI copy;
/// the raw values are kept identical to the originating app so existing dashboards keep working.
public enum MoreAppsFailureKind: String, Equatable, Sendable {
  case networkError = "network_error"
  case httpError = "http_error"
  case decodingError = "decoding_error"
  case requestError = "request_error"
  case invalidRequest = "invalid_request"
  case cancelled = "cancelled"
  case unknown = "unknown"
}
