import Foundation
import XCTest
@testable import IntelliKitNetworking

@MainActor final class BoundedHTTPDownloadTests: XCTestCase {
  private func fixture(headers: [String: String] = ["Content-Type": "text/html"], chunks: [Data] = [],
                       completes: Bool = false, status: Int = 200,
                       started: XCTestExpectation? = nil, stopped: XCTestExpectation? = nil) -> (URL, URLSessionConfiguration) {
    let url = URL(string: "https://capmemo.tests.invalid/" + UUID().uuidString)!
    DownloadScripts.shared.set(.init(headers: headers, chunks: chunks, completes: completes, status: status,
      onStart: { started?.fulfill() }, onStop: { stopped?.fulfill() }), for: url)
    addTeardownBlock { DownloadScripts.shared.remove(url) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DownloadURLProtocol.self]
    configuration.timeoutIntervalForRequest = 2
    configuration.timeoutIntervalForResource = 3
    return (url, configuration)
  }

  func testOversizedDeclaredResponseIsRejected() async throws {
    let (url, configuration) = fixture(headers: ["Content-Type": "text/html", "Content-Length": "65"], chunks: [Data([0])], completes: true)
    do {
      _ = try await BoundedHTTPDownload.read(URLRequest(url: url), policy: try HTTPDownloadPolicy(maximumBytes: 64), configuration: configuration)
      XCTFail("An oversized declared response must fail despite a tiny delivered body.")
    } catch let error as HTTPDownloadError {
      guard case .tooLarge = error else { return XCTFail("Unexpected rejection: \(error)") }
    }
  }

  func testUnknownAndInaccurateLengthsCannotBypassDeliveredByteLimit() async throws {
    for length in [nil, "1"] as [String?] {
      var headers = ["Content-Type": "text/html"]
      headers["Content-Length"] = length
      let (url, configuration) = fixture(headers: headers,
        chunks: [Data(repeating: 65, count: 60), Data(repeating: 66, count: 5)], completes: true)
      do {
        _ = try await BoundedHTTPDownload.read(URLRequest(url: url), policy: try HTTPDownloadPolicy(maximumBytes: 64), configuration: configuration)
        XCTFail("Unknown or inaccurate length must not bypass the actual received-byte limit.")
      } catch let error as HTTPDownloadError {
        guard case .tooLarge = error else { return XCTFail("Unexpected rejection: \(error)") }
      }
    }
  }

  func testExactLimitSucceedsAndInvalidResponseOrMimeIsRejected() async throws {
    let bytes = Data(repeating: 65, count: 64)
    let (url, configuration) = fixture(headers: ["Content-Type": "text/plain", "Content-Length": "64"],
      chunks: [bytes.prefix(31), bytes.dropFirst(31)], completes: true)
    let payload = try await BoundedHTTPDownload.read(URLRequest(url: url), policy: try HTTPDownloadPolicy(maximumBytes: 64,
      allowedMIMETypes: ["text/plain"]), configuration: configuration)
    XCTAssertEqual(payload.data, bytes); XCTAssertEqual(payload.response.url, url)
    for (status, mime) in [(404, "text/plain"), (200, "application/octet-stream")] {
      let (badURL, badConfiguration) = fixture(headers: ["Content-Type": mime], chunks: [Data([65])], completes: true, status: status)
      do {
        _ = try await BoundedHTTPDownload.read(URLRequest(url: badURL), policy: try HTTPDownloadPolicy(maximumBytes: 64,
          allowedMIMETypes: ["text/plain"]), configuration: badConfiguration)
        XCTFail("Invalid response must be rejected.")
      } catch let error as HTTPDownloadError {
        if status == 404 { guard case .statusCode(404) = error else { return XCTFail("Wrong status error") } }
        else { guard case .unsupportedContent = error else { return XCTFail("Wrong MIME error") } }
      }
    }
  }

  func testCancellationStopsAnUnfinishedTransferAndPreCanceledTaskDoesNotStartOne() async throws {
    let started = expectation(description: "Request began")
    let stopped = expectation(description: "Task cancellation reaches transport")
    let (url, configuration) = fixture(chunks: [Data([65])], started: started, stopped: stopped)
    let task = Task { try await BoundedHTTPDownload.read(URLRequest(url: url), policy: try HTTPDownloadPolicy(maximumBytes: 64), configuration: configuration) }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    do { _ = try await task.value; XCTFail("Canceled transfer must not publish data.") }
    catch is CancellationError {}
    await fulfillment(of: [stopped], timeout: 2)
    let notStarted = expectation(description: "No request after pre-cancel"); notStarted.isInverted = true
    let (secondURL, secondConfiguration) = fixture(started: notStarted)
    let second = Task { () throws -> BoundedHTTPDownload.Payload in
      withUnsafeCurrentTask { $0?.cancel() }
      return try await BoundedHTTPDownload.read(URLRequest(url: secondURL), policy: try HTTPDownloadPolicy(maximumBytes: 64), configuration: secondConfiguration)
    }
    do { _ = try await second.value; XCTFail("A pre-canceled task must fail.") } catch is CancellationError {}
    await fulfillment(of: [notStarted], timeout: 0.05)
  }

}

private struct DownloadScript: @unchecked Sendable {
  var headers: [String: String]
  var chunks: [Data] = []
  var completes = false
  var status = 200
  var onStart: @Sendable () -> Void = {}
  var onStop: @Sendable () -> Void = {}
}
private final class DownloadScripts: @unchecked Sendable {
  static let shared = DownloadScripts()
  private let lock = NSLock()
  private var scripts: [URL: DownloadScript] = [:]
  func set(_ script: DownloadScript, for url: URL) { lock.lock(); defer { lock.unlock() }; scripts[url] = script }
  func get(_ url: URL) -> DownloadScript? { lock.lock(); defer { lock.unlock() }; return scripts[url] }
  func remove(_ url: URL) { lock.lock(); defer { lock.unlock() }; scripts.removeValue(forKey: url) }
}
private final class DownloadURLProtocol: URLProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var script: DownloadScript?
  private var stopped = false
  private let queue = DispatchQueue(label: "CapMemo test response stream")
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "capmemo.tests.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url, let script = DownloadScripts.shared.get(url),
      let response = HTTPURLResponse(url: url, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: script.headers) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
    }
    lock.lock(); self.script = script; lock.unlock()
    script.onStart()
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    queue.asyncAfter(deadline: .now() + 0.01) { self.deliver(script, index: 0) }
  }
  private func deliver(_ script: DownloadScript, index: Int) {
    lock.lock(); let active = !stopped; lock.unlock()
    guard active else { return }
    if index < script.chunks.count {
      client?.urlProtocol(self, didLoad: script.chunks[index])
      queue.asyncAfter(deadline: .now() + 0.001) { self.deliver(script, index: index + 1) }
    } else if script.completes { client?.urlProtocolDidFinishLoading(self) }
    // Otherwise the server never completes: rejection/cancellation must end the request itself.
  }
  override func stopLoading() {
    lock.lock()
    guard !stopped else { lock.unlock(); return }
    stopped = true; let script = self.script
    lock.unlock()
    script?.onStop()
  }
}
