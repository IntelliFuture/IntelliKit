import Foundation
import Testing
@testable import IntelliKitNetworking

@Test func rejectsInvalidLimitsAndNonGETRequests() throws {
  for maximum in [0, -1] { #expect(throws: HTTPDownloadError.invalidPolicy) { try HTTPDownloadPolicy(maximumBytes: maximum) } }
  for timeout in [0.0, -1, .infinity, .nan] {
    #expect(throws: HTTPDownloadError.invalidPolicy) { try HTTPDownloadPolicy(maximumBytes: 10, timeout: timeout) }
  }
  let policy = try HTTPDownloadPolicy(maximumBytes: 10)
  for url in ["file:///tmp/a", "http://example.test", "https://user:pass@example.test"] {
    #expect(throws: HTTPDownloadError.invalidRequest) { try policy.validate(URLRequest(url: URL(string: url)!)) }
  }
  var request = URLRequest(url: URL(string: "https://example.test")!)
  request.httpMethod = "POST"
  #expect(throws: HTTPDownloadError.invalidRequest) { try policy.validate(request) }
  request.httpMethod = "GET"; request.httpBody = Data([1])
  #expect(throws: HTTPDownloadError.invalidRequest) { try policy.validate(request) }
}

@Test func redirectPolicyChecksOriginDowngradeAndCount() throws {
  let source = URL(string: "https://example.test/a")!
  let policy = try HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true)
  let same = URLRequest(url: URL(string: "https://EXAMPLE.test:443/b")!)
  #expect(try policy.redirectedRequest(from: source, to: same, count: 1) == same)
  for url in ["https://other.test/b", "http://example.test/b", "https://example.test:444/b"] {
    #expect(throws: HTTPDownloadError.redirectRejected) {
      try policy.redirectedRequest(from: source, to: URLRequest(url: URL(string: url)!), count: 1)
    }
  }
  #expect(throws: HTTPDownloadError.tooManyRedirects) { try policy.redirectedRequest(from: source, to: same, count: 6) }
  let deny = try HTTPDownloadPolicy(maximumBytes: 64, redirects: .deny)
  #expect(throws: HTTPDownloadError.redirectRejected) { try deny.redirectedRequest(from: source, to: same, count: 1) }
}

@Test func crossOriginOptInDropsAllCallerHeaders() throws {
  let policy = try HTTPDownloadPolicy(maximumBytes: 64, redirects: .https)
  var request = URLRequest(url: URL(string: "https://other.test")!)
  request.setValue("secret", forHTTPHeaderField: "Authorization")
  request.setValue("session=secret", forHTTPHeaderField: "Cookie")
  request.setValue("private", forHTTPHeaderField: "X-API-Key")
  let forwarded = try policy.redirectedRequest(from: URL(string: "https://example.test")!, to: request, count: 1)
  #expect(forwarded.allHTTPHeaderFields?.isEmpty != false)
  #expect(forwarded.url == request.url)
}
