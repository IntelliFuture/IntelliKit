import Foundation

/// Maps an app's own language code (for example `"zh-Hans"`, `"en_GB"`, `"ja"`) to the `lang`
/// value accepted by the iTunes lookup endpoint (for example `"zh_cn"`, `"en_us"`, `"ja_jp"`).
///
/// Only markets that the originating apps actually ship to are mapped; anything else throws
/// ``MoreAppsError/invalidLanguageCode`` so callers can decide whether to retry without a language
/// (the storefront default) rather than silently sending an unsupported value.
public enum MoreAppsLanguage {
  public static func lookupCode(forAppLanguage appLanguageCode: String) throws -> String {
    let normalizedCode = appLanguageCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
    let subtags = normalizedCode.components(separatedBy: "_")

    guard
      let language = subtags.first,
      !language.isEmpty,
      subtags.allSatisfy({ !$0.isEmpty })
    else {
      throw MoreAppsError.invalidLanguageCode
    }

    switch language {
    case "en":
      return "en_us"
    case "zh":
      let variants = Set(subtags.dropFirst())
      let isSimplified = !variants.isDisjoint(with: ["hans", "cn", "sg"])
      let isTraditional = !variants.isDisjoint(with: ["hant", "tw", "hk", "mo"])
      guard !(isSimplified && isTraditional) else {
        throw MoreAppsError.invalidLanguageCode
      }
      return isTraditional ? "zh_tw" : "zh_cn"
    case "ko":
      return "ko_kr"
    case "vi":
      return "vi_vn"
    case "ja":
      return "ja_jp"
    default:
      throw MoreAppsError.invalidLanguageCode
    }
  }
}
