import Foundation
import Testing
@testable import IntelliKitMoreApps

@Test func lookupURLCarriesRequiredParametersAndLanguage() throws {
  let url = try MoreAppsLookup.lookupURL(developerID: 1841278819, lookupLanguageCode: "zh_cn")
  let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
  let query = Dictionary(
    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
  )

  #expect(components.scheme == "https")
  #expect(components.host == "itunes.apple.com")
  #expect(components.path == "/lookup")
  #expect(query["id"] == "1841278819")
  #expect(query["entity"] == "software")
  #expect(query["lang"] == "zh_cn")
}

@Test func lookupURLOmitsLanguageWhenNil() throws {
  let url = try MoreAppsLookup.lookupURL(developerID: 42, lookupLanguageCode: nil)
  let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
  #expect(components.queryItems?.contains { $0.name == "lang" } == false)
}

@Test func lookupURLRejectsNonPositiveDeveloperID() {
  for developerID in [0, -1] {
    #expect(throws: MoreAppsError.invalidDeveloperID) {
      try MoreAppsLookup.lookupURL(developerID: developerID, lookupLanguageCode: nil)
    }
  }
}

@Test func languageMappingCoversSupportedMarkets() throws {
  let mappings = [
    "en": "en_us",
    "en-GB": "en_us",
    "en_CA": "en_us",
    "zh": "zh_cn",
    "zh-CN": "zh_cn",
    "zh-Hans": "zh_cn",
    "zh-HK": "zh_tw",
    "zh-Hant": "zh_tw",
    "ko": "ko_kr",
    "ko-KR": "ko_kr",
    "vi": "vi_vn",
    "vi-VN": "vi_vn",
    "ja": "ja_jp",
    "ja-JP": "ja_jp",
  ]
  for (appLanguageCode, expected) in mappings {
    #expect(try MoreAppsLanguage.lookupCode(forAppLanguage: appLanguageCode) == expected)
  }
}

@Test func languageMappingRejectsUnsupportedCodes() {
  for code in ["", "unsupported", "english", "fr-FR", "zh-Hans-TW"] {
    #expect(throws: MoreAppsError.invalidLanguageCode) {
      try MoreAppsLanguage.lookupCode(forAppLanguage: code)
    }
  }
}

@Test func fetchRetriesWithoutLanguageAfterHTTP400() async throws {
  let recorder = RequestRecorder()
  let lookup = MoreAppsLookup { url in
    await recorder.record(url)
    let hasLanguage = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
      .contains { $0.name == "lang" }
    if hasLanguage {
      throw MoreAppsHTTPStatusError(statusCode: 400)
    }
    return MoreAppsLookup.singleAppPayload
  }

  let apps = try await lookup.fetchApps(
    developerID: 1841278819,
    lookupLanguageCode: "zh_cn",
    excludingBundleIdentifiers: []
  )

  #expect(apps.count == 1)
  let urls = await recorder.urls
  #expect(urls.count == 2)
  #expect((URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems ?? [])
    .contains { $0.name == "lang" })
  #expect((URLComponents(url: urls[1], resolvingAgainstBaseURL: false)?.queryItems ?? [])
    .contains { $0.name == "lang" } == false)
}

@Test func fetchDoesNotRetryWhenNoLanguageWasRequested() async {
  let lookup = MoreAppsLookup { _ in throw MoreAppsHTTPStatusError(statusCode: 400) }
  await #expect(throws: MoreAppsHTTPStatusError(statusCode: 400)) {
    try await lookup.fetchApps(
      developerID: 7,
      lookupLanguageCode: nil,
      excludingBundleIdentifiers: []
    )
  }
}

@Test func validationFiltersDeduplicatesExcludesAndUpgradesArtworkScheme() {
  let response = LookupResponse(
    resultCount: 5,
    results: [
      // Developer wrapper, not software.
      LookupItem(wrapperType: "artist", trackName: "Dev", bundleId: "dev", version: "1", trackViewUrl: "https://apps.apple.com/dev", artworkUrl100: "https://example.test/a.png"),
      // Valid; http artwork is upgraded to https.
      LookupItem(wrapperType: "software", trackName: "Alpha", bundleId: "com.example.alpha", version: "1.0", trackViewUrl: "https://apps.apple.com/alpha", artworkUrl100: "http://example.test/alpha.png"),
      // Duplicate bundle id is dropped.
      LookupItem(wrapperType: "software", trackName: "Alpha Copy", bundleId: "com.example.alpha", version: "1.1", trackViewUrl: "https://apps.apple.com/alpha2", artworkUrl100: "https://example.test/alpha2.png"),
      // Excluded bundle id.
      LookupItem(wrapperType: "software", trackName: "Beta", bundleId: "com.example.beta", version: "2.0", trackViewUrl: "https://apps.apple.com/beta", artworkUrl100: "https://example.test/beta.png"),
      // Missing version is dropped.
      LookupItem(wrapperType: "software", trackName: "Gamma", bundleId: "com.example.gamma", version: nil, trackViewUrl: "https://apps.apple.com/gamma", artworkUrl100: "https://example.test/gamma.png"),
    ]
  )

  let apps = MoreAppsLookup.validatedApps(
    from: response,
    excludingBundleIdentifiers: ["com.example.beta"]
  )

  #expect(apps.map(\.id) == ["com.example.alpha"])
  #expect(apps.first?.iconURL.scheme == "https")
  #expect(apps.first?.appStoreURL.absoluteString == "https://apps.apple.com/alpha")
}

@Test func failureKindClassifiesCommonErrors() {
  #expect(MoreAppsLookup.failureKind(for: MoreAppsHTTPStatusError(statusCode: 500)) == .httpError)
  #expect(MoreAppsLookup.failureKind(for: URLError(.notConnectedToInternet)) == .networkError)
  #expect(MoreAppsLookup.failureKind(for: MoreAppsError.invalidDeveloperID) == .invalidRequest)
  #expect(MoreAppsLookup.failureKind(for: CancellationError()) == .cancelled)
  let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))
  #expect(MoreAppsLookup.failureKind(for: decodingError) == .decodingError)
}

private extension MoreAppsLookup {
  static var singleAppPayload: Data {
    let json = """
    {
      "resultCount": 2,
      "results": [
        { "wrapperType": "artist", "artistName": "Dev" },
        {
          "wrapperType": "software",
          "trackName": "Alpha",
          "bundleId": "com.example.alpha",
          "version": "1.0",
          "trackViewUrl": "https://apps.apple.com/alpha",
          "artworkUrl100": "https://example.test/alpha.png"
        }
      ]
    }
    """
    return Data(json.utf8)
  }
}

private actor RequestRecorder {
  private(set) var urls: [URL] = []
  func record(_ url: URL) { urls.append(url) }
}
