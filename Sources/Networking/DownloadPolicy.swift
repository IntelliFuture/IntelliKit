import Foundation

public enum HTTPDownloadError: Error, Equatable {
  case invalidPolicy, invalidRequest, invalidResponse
  case statusCode(Int)
  case unsupportedContent, tooLarge, redirectRejected, tooManyRedirects
}

/// Limits one in-memory GET. The limit applies to delivered (decoded) bytes, not total process memory.
public struct HTTPDownloadPolicy: Sendable {
  public enum Redirects: Sendable { case deny, sameOrigin, https }
  public let maximumBytes: Int
  public let allowedMIMETypes: Set<String>?
  public let allowsHTTP: Bool
  public let redirects: Redirects
  public let maximumRedirects: Int
  public let timeout: TimeInterval

  public init(maximumBytes: Int, allowedMIMETypes: Set<String>? = nil,
              allowsHTTP: Bool = false, redirects: Redirects = .sameOrigin,
              maximumRedirects: Int = 5, timeout: TimeInterval = 60) throws {
    guard maximumBytes > 0, maximumRedirects >= 0, timeout.isFinite, timeout > 0 else {
      throw HTTPDownloadError.invalidPolicy
    }
    self.maximumBytes = maximumBytes
    self.allowedMIMETypes = allowedMIMETypes.map { Set($0.map { $0.lowercased() }) }
    self.allowsHTTP = allowsHTTP
    self.redirects = redirects
    self.maximumRedirects = maximumRedirects
    self.timeout = timeout
  }

  func validate(_ request: URLRequest) throws {
    guard let url = request.url, let scheme = url.scheme?.lowercased(),
      scheme == "https" || (allowsHTTP && scheme == "http"),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
      (request.httpMethod ?? "GET").uppercased() == "GET",
      request.httpBody == nil, request.httpBodyStream == nil else { throw HTTPDownloadError.invalidRequest }
  }

  func redirectedRequest(from source: URL, to request: URLRequest, count: Int) throws -> URLRequest {
    try validate(request)
    guard count <= maximumRedirects else { throw HTTPDownloadError.tooManyRedirects }
    guard let target = request.url else { throw HTTPDownloadError.invalidRequest }
    let sameOrigin = Self.origin(source) == Self.origin(target)
    // Even an HTTP-enabled policy never permits HTTPS to HTTP downgrades.
    guard !(source.scheme?.lowercased() == "https" && target.scheme?.lowercased() != "https") else {
      throw HTTPDownloadError.redirectRejected
    }
    switch redirects {
    case .deny: throw HTTPDownloadError.redirectRejected
    case .sameOrigin: guard sameOrigin else { throw HTTPDownloadError.redirectRejected }
    case .https: guard target.scheme?.lowercased() == "https" else { throw HTTPDownloadError.redirectRejected }
    }
    if sameOrigin { return request }
    // Cross-origin opt-in carries no caller headers, cookies or authorization to the next origin.
    return URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
  }

  private static func origin(_ url: URL) -> String {
    let scheme = url.scheme?.lowercased() ?? ""
    return "\(scheme)://\(url.host?.lowercased() ?? ""):\(url.port ?? (scheme == "https" ? 443 : 80))"
  }
}
