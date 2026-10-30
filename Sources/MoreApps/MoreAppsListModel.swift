#if canImport(SwiftUI)
import Foundation

/// Drives ``MoreAppsListView``. Loads the developer's other apps once, exposes a small state machine,
/// and reports the outcome through an optional callback so the host app can log analytics.
///
/// `ObservableObject` (not the iOS 17 `@Observable` macro) keeps this usable on the package's iOS 16
/// baseline.
@MainActor
public final class MoreAppsListModel: ObservableObject {
  public enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed
  }

  /// Reports a completed load. `result` is `"success"`, `"empty"` or `"failed"`; `failureKind` is set
  /// only when `result == "failed"`.
  public typealias ResultHandler = @MainActor (
    _ result: String,
    _ isRetry: Bool,
    _ failureKind: MoreAppsFailureKind?
  ) -> Void

  @Published public private(set) var apps: [MoreApp] = []
  @Published public private(set) var loadState: LoadState = .idle

  private let developerID: Int
  private let appLanguageCode: @Sendable () -> String
  private let excludedBundleIdentifiers: Set<String>
  private let lookup: MoreAppsLookup
  private let onResult: ResultHandler?

  /// - Parameters:
  ///   - developerID: The App Store artist/developer id whose other apps should be listed.
  ///   - appLanguageCode: Resolves the app's current language code at load time (for example
  ///     `"zh-Hans"`). Evaluated lazily so language changes are picked up on reload.
  ///   - excludedBundleIdentifiers: Bundle identifiers to hide (for example debug variants).
  ///   - includeMainBundleInExclusions: When `true`, the host app's own bundle id is excluded so it
  ///     never lists itself.
  ///   - lookup: The catalogue source; defaults to the bounded HTTPS transport.
  ///   - onResult: Optional completion reporter for analytics.
  public init(
    developerID: Int,
    appLanguageCode: @escaping @Sendable () -> String,
    excludedBundleIdentifiers: Set<String> = [],
    includeMainBundleInExclusions: Bool = true,
    lookup: MoreAppsLookup = MoreAppsLookup(),
    onResult: ResultHandler? = nil
  ) {
    self.developerID = developerID
    self.appLanguageCode = appLanguageCode
    var exclusions = excludedBundleIdentifiers
    if includeMainBundleInExclusions, let bundleIdentifier = Bundle.main.bundleIdentifier {
      exclusions.insert(bundleIdentifier)
    }
    self.excludedBundleIdentifiers = exclusions
    self.lookup = lookup
    self.onResult = onResult
  }

  /// Loads the list. Safe to call again as a retry; re-entrancy while loading is ignored.
  public func load() async {
    guard loadState != .loading else { return }

    let isRetry = loadState == .failed
    let languageCode = appLanguageCode()
    loadState = .loading

    do {
      let infos = try await resolvedApps(appLanguageCode: languageCode)
      guard !Task.isCancelled else {
        loadState = apps.isEmpty ? .idle : .loaded
        return
      }

      apps = infos
      loadState = infos.isEmpty ? .empty : .loaded
      onResult?(infos.isEmpty ? "empty" : "success", isRetry, nil)
    } catch is CancellationError {
      loadState = apps.isEmpty ? .idle : .loaded
    } catch {
      guard !Task.isCancelled else {
        loadState = apps.isEmpty ? .idle : .loaded
        return
      }

      apps = []
      loadState = .failed
      onResult?("failed", isRetry, MoreAppsLookup.failureKind(for: error))
    }
  }

  /// Falls back to the storefront default when the app's language code is not a supported market,
  /// so an unmapped language never turns into a hard failure.
  private func resolvedApps(appLanguageCode: String) async throws -> [MoreApp] {
    let lookupLanguageCode = try? MoreAppsLanguage.lookupCode(forAppLanguage: appLanguageCode)
    return try await lookup.fetchApps(
      developerID: developerID,
      lookupLanguageCode: lookupLanguageCode,
      excludingBundleIdentifiers: excludedBundleIdentifiers
    )
  }
}
#endif
