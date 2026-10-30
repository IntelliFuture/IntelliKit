import Foundation

/// One request per session. Response headers and every decoded chunk are checked before buffering.
public enum BoundedHTTPDownload {
  public struct Payload: Sendable {
    public let data: Data
    public let response: HTTPURLResponse
  }
  public static func read(_ request: URLRequest, policy: HTTPDownloadPolicy,
                          configuration: URLSessionConfiguration = .ephemeral) async throws -> Payload {
    try policy.validate(request)
    // Each transfer is isolated from ambient credentials, cookies and caches.
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpAdditionalHeaders = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = policy.timeout
    configuration.timeoutIntervalForResource = policy.timeout
    var request = request
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = policy.timeout
    request.httpShouldHandleCookies = false
    let transfer = Transfer(policy: policy)
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        transfer.start(request, configuration: configuration, continuation: continuation)
      }
    } onCancel: { transfer.cancel() }
  }

  // Delegate callbacks run on a serial queue; the lock also protects cancellation from the caller's task.
  private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let policy: HTTPDownloadPolicy
    private var redirectCount = 0
    private var buffer = Data()
    private var response: HTTPURLResponse?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Payload, Error>?
    private var finished = false
    private var terminalError: Error?

    init(policy: HTTPDownloadPolicy) { self.policy = policy }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
      lock.lock()
      let active = !finished
      redirectCount += 1
      let count = redirectCount
      lock.unlock()
      guard active else { completionHandler(nil); return }
      do {
        guard let source = response.url else { throw HTTPDownloadError.invalidResponse }
        let next = try policy.redirectedRequest(from: source, to: request, count: count)
        completionHandler(next)
      } catch {
        complete(.failure(error))
        completionHandler(nil)
      }
    }

    func start(_ request: URLRequest, configuration: URLSessionConfiguration,
               continuation: CheckedContinuation<Payload, Error>) {
      lock.lock()
      guard !finished else {
        let error = terminalError ?? CancellationError()
        lock.unlock()
        continuation.resume(throwing: error)
        return
      }
      let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
      self.session = session
      self.continuation = continuation
      let task = session.dataTask(with: request)
      lock.unlock()
      task.resume()
    }

    func cancel() { complete(.failure(CancellationError())) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
      guard let http = response as? HTTPURLResponse else {
        complete(.failure(HTTPDownloadError.invalidResponse)); completionHandler(.cancel); return
      }
      guard (200..<300).contains(http.statusCode) else {
        complete(.failure(HTTPDownloadError.statusCode(http.statusCode))); completionHandler(.cancel); return
      }
      if let allowedMIMETypes = policy.allowedMIMETypes, !allowedMIMETypes.contains((http.mimeType ?? "").lowercased()) {
        complete(.failure(HTTPDownloadError.unsupportedContent)); completionHandler(.cancel); return
      }
      guard http.expectedContentLength <= Int64(policy.maximumBytes) else {
        complete(.failure(HTTPDownloadError.tooLarge)); completionHandler(.cancel); return
      }
      lock.lock()
      let active = !finished
      if active { self.response = http }
      lock.unlock()
      completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
      lock.lock()
      guard !finished else { lock.unlock(); return }
      guard data.count <= policy.maximumBytes - buffer.count else {
        lock.unlock(); complete(.failure(HTTPDownloadError.tooLarge)); return
      }
      buffer.append(data)
      lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
      if let error { complete(.failure(error)); return }
      lock.lock()
      let response = self.response
      let data = buffer
      lock.unlock()
      guard let response else { complete(.failure(HTTPDownloadError.invalidResponse)); return }
      complete(.success(Payload(data: data, response: response)))
    }

    private func complete(_ result: Result<Payload, Error>) {
      lock.lock()
      guard !finished else { lock.unlock(); return }
      finished = true
      if case let .failure(error) = result { terminalError = error }
      let continuation = self.continuation; self.continuation = nil
      let session = self.session; self.session = nil
      buffer = Data()
      lock.unlock()
      switch result {
        case .success: session?.finishTasksAndInvalidate()
        case .failure: session?.invalidateAndCancel()
      }
      continuation?.resume(with: result)
    }
  }
}
