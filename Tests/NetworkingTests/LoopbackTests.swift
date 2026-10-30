import Foundation
import Network
import XCTest
import IntelliKitNetworking

/// Exercises real URLSession redirect/decompression/timeout behavior without external services.
@MainActor final class LoopbackTests: XCTestCase {
  func testActualRedirectAndRedirectLimit() async throws {
    let server = try LoopbackServer(); defer { server.stop() }
    let port = try await server.start()
    let url = URL(string: "http://127.0.0.1:\(port)/redirect")!
    let policy = try HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true)
    let payload = try await BoundedHTTPDownload.read(URLRequest(url: url), policy: policy)
    XCTAssertEqual(payload.data, Data("ok".utf8)); XCTAssertEqual(payload.response.url?.path, "/ok")
    do {
      _ = try await BoundedHTTPDownload.read(URLRequest(url: url),
        policy: HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true, redirects: .deny))
      XCTFail("Expected rejected redirect")
    } catch { XCTAssertEqual(error as? HTTPDownloadError, .redirectRejected) }
    do {
      _ = try await BoundedHTTPDownload.read(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/loop")!),
        policy: HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true, maximumRedirects: 2))
      XCTFail("Expected redirect limit")
    } catch { XCTAssertEqual(error as? HTTPDownloadError, .tooManyRedirects) }
  }

  func testHeaderOnlyStallIsBoundedByResourceTimeout() async throws {
    let server = try LoopbackServer(); defer { server.stop() }
    let port = try await server.start()
    let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/oversized-header")!)
    do {
      _ = try await BoundedHTTPDownload.read(request,
        policy: HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true, timeout: 2))
      XCTFail("A header-only stalled response must not succeed")
    } catch {
      // CFNetwork may withhold a short response until body bytes arrive. Either early size rejection
      // or the configured real-resource timeout is valid; no successful or unbounded wait is valid.
      if let error = error as? HTTPDownloadError { XCTAssertEqual(error, .tooLarge) }
      else { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }
  }

  func testChunkedStreamAbortsBeforeServerFinishes() async throws {
    let server = try LoopbackServer(); defer { server.stop() }
    let port = try await server.start()
    do {
      _ = try await BoundedHTTPDownload.read(
        URLRequest(url: URL(string: "http://127.0.0.1:\(port)/chunked")!),
        policy: HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true, timeout: 2))
      XCTFail("Expected streaming byte limit without terminal chunk")
    } catch { XCTAssertEqual(error as? HTTPDownloadError, .tooLarge) }
  }

  func testGzipLimitAppliesToDecodedBytes() async throws {
    let server = try LoopbackServer(); defer { server.stop() }
    let port = try await server.start()
    let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/gzip")!)
    do {
      _ = try await BoundedHTTPDownload.read(request, policy: HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true))
      XCTFail("Compressed bytes must not bypass decoded size limit")
    } catch { XCTAssertEqual(error as? HTTPDownloadError, .tooLarge) }
    let payload = try await BoundedHTTPDownload.read(request,
      policy: HTTPDownloadPolicy(maximumBytes: 4096, allowsHTTP: true))
    XCTAssertEqual(payload.data, Data(repeating: 65, count: 4096))
  }

  func testResourceTimeoutAndRequestHeaderIsolation() async throws {
    let server = try LoopbackServer(); defer { server.stop() }
    let port = try await server.start()
    let config = URLSessionConfiguration.default
    config.httpAdditionalHeaders = ["X-Private-Global": "must-not-leak"]
    let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/headers")!)
    let payload = try await BoundedHTTPDownload.read(request,
      policy: HTTPDownloadPolicy(maximumBytes: 4096, allowsHTTP: true), configuration: config)
    XCTAssertFalse(String(decoding: payload.data, as: UTF8.self).lowercased().contains("must-not-leak"))
    XCTAssertEqual(config.httpAdditionalHeaders?["X-Private-Global"] as? String, "must-not-leak")
    do {
      _ = try await BoundedHTTPDownload.read(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/stall")!),
        policy: HTTPDownloadPolicy(maximumBytes: 64, allowsHTTP: true, timeout: 0.2))
      XCTFail("Expected resource timeout")
    } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
  }
}

private final class LoopbackServer: @unchecked Sendable {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "IntelliKit-loopback-tests")
  private let lock = NSLock()
  private var connections: [NWConnection] = []
  init() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { connection.cancel(); return }
      self.lock.lock(); self.connections.append(connection); self.lock.unlock()
      connection.start(queue: self.queue)
      self.receive(connection, accumulated: Data())
    }
  }
  func start() async throws -> UInt16 {
    try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.listener.stateUpdateHandler = nil
          continuation.resume(returning: self.listener.port!.rawValue)
        case .failed(let error):
          self.listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)
        default: break
        }
      }
      listener.start(queue: queue)
    }
  }
  func stop() {
    listener.cancel()
    lock.lock(); let pending = connections; connections = []; lock.unlock()
    pending.forEach { $0.cancel() }
  }
  private func receive(_ connection: NWConnection, accumulated: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
      guard let self else { return }
      var bytes = accumulated; bytes.append(data ?? Data())
      if bytes.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(connection, bytes: bytes) }
      else if error == nil, !complete, bytes.count < 16384 { self.receive(connection, accumulated: bytes) }
      else { connection.cancel() }
    }
  }
  private func respond(_ connection: NWConnection, bytes: Data) {
    let request = String(decoding: bytes, as: UTF8.self)
    let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
    if path == "/stall" { return }
    if path == "/chunked" {
      let chunked = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\n\r\n41\r\n" + String(repeating: "A", count: 65) + "\r\n"
      // Intentionally no terminal zero-sized chunk and no connection close.
      connection.send(content: Data(chunked.utf8), completion: .contentProcessed { _ in })
      return
    }
    if path == "/oversized-header" {
      let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 65\r\n\r\n".utf8)
      // Keep the TCP connection open, without ever delivering a body.
      connection.send(content: header, completion: .contentProcessed { _ in })
      return
    }
    var status = "200 OK"; var headers = "Content-Type: text/plain\r\n"
    var body = Data("ok".utf8)
    if path == "/redirect" || path == "/loop" {
      status = "302 Found"; headers += "Location: \(path == "/loop" ? "/loop" : "/ok")\r\n"; body = Data()
    } else if path == "/headers" { body = bytes }
    else if path == "/gzip" {
      // gzip.compress(b'A' * 4096, mtime=0); small wire body expands to 4096 delivered bytes.
      body = Data(base64Encoded: "H4sIAAAAAAACE+3BAQ0AAADCoGzvX8oeDigAAADg3QBANKb+ABAAAA==")!
      headers += "Content-Encoding: gzip\r\n"
    }
    var response = Data("HTTP/1.1 \(status)\r\n\(headers)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
    response.append(body)
    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
  }
}
