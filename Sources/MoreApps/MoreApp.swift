import Foundation

/// One App Store software result reduced to the fields a "more apps by this developer" list needs.
///
/// `id` is the App Store bundle identifier, which is stable and lets callers exclude their own app
/// and de-duplicate results.
public struct MoreApp: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let version: String
  public let iconURL: URL
  public let appStoreURL: URL

  public init(
    id: String,
    name: String,
    version: String,
    iconURL: URL,
    appStoreURL: URL
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.iconURL = iconURL
    self.appStoreURL = appStoreURL
  }
}
