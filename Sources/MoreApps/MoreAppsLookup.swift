import Foundation
import IntelliKitNetworking

/// Fetches the public App Store catalogue for a single developer and reduces it to ``MoreApp``
/// values suitable for a "more apps by this developer" list.
///
/// The default transport is ``IntelliKitNetworking/BoundedHTTPDownload`` — one isolated, size-capped
/// HTTPS GET with no ambient cookies, credentials or cache. Tests and alternate transports can inject
/// a ``DataLoader``. Nothing app-specific (developer id, bundle exclusions, language) is baked in;
/// the caller supplies all of it.
public struct MoreAppsLookup: Sendable {
  public typealias DataLoader = @Sendable (URL) async throws -> Data

  private let dataLoader: DataLoader

  /// Uses the bounded HTTPS transport. `maximumResponseBytes` caps the decoded response; the
  /// iTunes lookup payload for a single developer is small, so a few megabytes is generous.
  public init(maximumResponseBytes: Int = 4 * 1024 * 1024, timeout: TimeInterval = 30) {
    self.dataLoader = { url in
      let policy = try HTTPDownloadPolicy(
        maximumBytes: maximumResponseBytes,
        allowedMIMETypes: nil,
        allowsHTTP: false,
        redirects: .https,
        maximumRedirects: 5,
        timeout: timeout
      )
      do {
        let payload = try await BoundedHTTPDownload.read(URLRequest(url: url), policy: policy)
        return payload.data
      } catch let HTTPDownloadError.statusCode(statusCode) {
        throw MoreAppsHTTPStatusError(statusCode: statusCode)
      }
    }
  }

  /// Injects a custom transport. Signal a non-success HTTP status by throwing
  /// ``MoreAppsHTTPStatusError`` so the language fallback below can react to `400`.
  public init(dataLoader: @escaping DataLoader) {
    self.dataLoader = dataLoader
  }

  /// Looks up `developerID` using an already-resolved `lookupLanguageCode` (for example `"zh_cn"`),
  /// or `nil` for the storefront default. On an HTTP `400` from a specific language the request is
  /// retried once without a language, matching the App Store's behaviour for unsupported `lang`
  /// values.
  public func fetchApps(
    developerID: Int,
    lookupLanguageCode: String?,
    excludingBundleIdentifiers: Set<String>
  ) async throws -> [MoreApp] {
    let url = try Self.lookupURL(
      developerID: developerID,
      lookupLanguageCode: lookupLanguageCode
    )
    let data: Data
    do {
      data = try await dataLoader(url)
    } catch let error as MoreAppsHTTPStatusError
      where error.statusCode == 400 && lookupLanguageCode != nil {
      let fallbackURL = try Self.lookupURL(
        developerID: developerID,
        lookupLanguageCode: nil
      )
      data = try await dataLoader(fallbackURL)
    }
    let response = try JSONDecoder().decode(LookupResponse.self, from: data)
    return Self.validatedApps(
      from: response,
      excludingBundleIdentifiers: excludingBundleIdentifiers
    )
  }

  /// Convenience that maps the app's own language code to a lookup language with
  /// ``MoreAppsLanguage`` before fetching.
  public func fetchApps(
    developerID: Int,
    appLanguageCode: String,
    excludingBundleIdentifiers: Set<String>
  ) async throws -> [MoreApp] {
    let lookupLanguageCode = try MoreAppsLanguage.lookupCode(forAppLanguage: appLanguageCode)
    return try await fetchApps(
      developerID: developerID,
      lookupLanguageCode: lookupLanguageCode,
      excludingBundleIdentifiers: excludingBundleIdentifiers
    )
  }

  static func lookupURL(developerID: Int, lookupLanguageCode: String?) throws -> URL {
    guard developerID > 0 else {
      throw MoreAppsError.invalidDeveloperID
    }
    guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else {
      throw MoreAppsError.invalidLookupURL
    }
    components.queryItems = [
      URLQueryItem(name: "id", value: String(developerID)),
      URLQueryItem(name: "entity", value: "software"),
    ]
    if let lookupLanguageCode {
      components.queryItems?.append(
        URLQueryItem(name: "lang", value: lookupLanguageCode)
      )
    }
    guard let url = components.url else {
      throw MoreAppsError.invalidLookupURL
    }
    return url
  }

  static func validatedApps(
    from response: LookupResponse,
    excludingBundleIdentifiers: Set<String>
  ) -> [MoreApp] {
    var seenBundleIdentifiers = Set<String>()

    return response.results.compactMap { item in
      guard
        item.wrapperType == "software",
        let bundleIdentifier = nonEmpty(item.bundleId),
        !excludingBundleIdentifiers.contains(bundleIdentifier),
        !seenBundleIdentifiers.contains(bundleIdentifier),
        let name = nonEmpty(item.trackName),
        let version = nonEmpty(item.version),
        let iconURL = artworkURL(item.artworkUrl100),
        let appStoreURL = httpsURL(item.trackViewUrl)
      else {
        return nil
      }

      seenBundleIdentifiers.insert(bundleIdentifier)
      return MoreApp(
        id: bundleIdentifier,
        name: name,
        version: version,
        iconURL: iconURL,
        appStoreURL: appStoreURL
      )
    }
  }

  /// Best-effort, log-safe classification of a lookup failure for analytics or UI copy.
  public static func failureKind(for error: Error) -> MoreAppsFailureKind {
    if error is DecodingError {
      return .decodingError
    }
    if error is MoreAppsHTTPStatusError {
      return .httpError
    }
    if let downloadError = error as? HTTPDownloadError {
      switch downloadError {
      case .statusCode, .invalidResponse, .unsupportedContent, .tooLarge,
        .redirectRejected, .tooManyRedirects:
        return .httpError
      case .invalidPolicy, .invalidRequest:
        return .invalidRequest
      }
    }
    if error is URLError {
      return .networkError
    }
    if error is CancellationError {
      return .cancelled
    }
    if error is MoreAppsError {
      return .invalidRequest
    }
    return .unknown
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func httpsURL(_ value: String?) -> URL? {
    guard
      let value = nonEmpty(value),
      let url = URL(string: value),
      url.scheme?.lowercased() == "https",
      url.host != nil
    else {
      return nil
    }
    return url
  }

  private static func artworkURL(_ value: String?) -> URL? {
    guard
      let value = nonEmpty(value),
      var components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      components.host != nil
    else {
      return nil
    }

    components.scheme = "https"
    return components.url
  }
}

/// Decoded shape of the iTunes lookup response. Internal: callers consume ``MoreApp`` instead.
struct LookupResponse: Decodable, Sendable {
  let resultCount: Int
  let results: [LookupItem]
}

struct LookupItem: Decodable, Sendable {
  let wrapperType: String?
  let trackName: String?
  let bundleId: String?
  let version: String?
  let trackViewUrl: String?
  let artworkUrl100: String?
}
