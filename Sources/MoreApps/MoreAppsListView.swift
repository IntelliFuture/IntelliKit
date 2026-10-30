#if canImport(SwiftUI)
import SwiftUI

/// User-facing copy for ``MoreAppsListView``. Defaults are English; hosts pass localized strings.
public struct MoreAppsListStrings: Sendable {
  public var loading: String
  public var empty: String
  public var failedTitle: String
  public var failedMessage: String
  public var retry: String

  public init(
    loading: String = "Loading…",
    empty: String = "No other apps yet",
    failedTitle: String = "Couldn't load apps",
    failedMessage: String = "Please try again later.",
    retry: String = "Retry"
  ) {
    self.loading = loading
    self.empty = empty
    self.failedTitle = failedTitle
    self.failedMessage = failedMessage
    self.retry = retry
  }
}

/// A ready-made list of a developer's other App Store apps. Each row opens the App Store.
///
/// Icons load with `AsyncImage` so the view carries no third-party image dependency. Hosts that want
/// their own styling can skip this view and use ``MoreAppsLookup`` / ``MoreAppsListModel`` directly.
public struct MoreAppsListView: View {
  @StateObject private var model: MoreAppsListModel
  private let strings: MoreAppsListStrings

  public init(
    model: @autoclosure @escaping () -> MoreAppsListModel,
    strings: MoreAppsListStrings = MoreAppsListStrings()
  ) {
    _model = StateObject(wrappedValue: model())
    self.strings = strings
  }

  public var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .task { await model.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch model.loadState {
    case .idle, .loading:
      ProgressView(strings.loading)

    case .loaded:
      appList

    case .empty:
      message(
        systemImage: "square.grid.2x2",
        title: strings.empty,
        description: nil,
        showsRetry: false
      )

    case .failed:
      message(
        systemImage: "wifi.exclamationmark",
        title: strings.failedTitle,
        description: strings.failedMessage,
        showsRetry: true
      )
    }
  }

  private var appList: some View {
    ScrollView {
      VStack(spacing: 16) {
        ForEach(model.apps) { app in
          MoreAppRow(app: app)
        }
      }
      .padding(16)
    }
  }

  private func message(
    systemImage: String,
    title: String,
    description: String?,
    showsRetry: Bool
  ) -> some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(title)
        .font(.headline)
        .multilineTextAlignment(.center)
      if let description {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      if showsRetry {
        Button(strings.retry) {
          Task { await model.load() }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(32)
  }
}

private struct MoreAppRow: View {
  @Environment(\.openURL) private var openURL
  let app: MoreApp

  var body: some View {
    Button {
      openURL(app.appStoreURL)
    } label: {
      HStack(spacing: 16) {
        AsyncImage(url: app.iconURL) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.15))
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 4) {
          Text(app.name)
            .font(.body)
            .foregroundStyle(.primary)
          Text(app.version)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        Image(systemName: "chevron.forward")
          .foregroundStyle(.tertiary)
      }
      .padding(16)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
#endif
