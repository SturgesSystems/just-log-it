import SwiftUI

struct RootTabView: View {
  private enum AppTab: Hashable {
    case log
    case entries
    case settings
  }

  @State private var selection: AppTab = .log
  @Environment(\.usesVolatileStore) private var usesVolatileStore

  var body: some View {
    TabView(selection: $selection) {
      Tab("Log", systemImage: "plus.circle.fill", value: .log) {
        NavigationStack {
          LogView()
        }
      }

      Tab("Entries", systemImage: "list.bullet.rectangle", value: .entries) {
        NavigationStack {
          EntriesView { selection = .log }
        }
      }

      Tab("Settings", systemImage: "gearshape", value: .settings) {
        NavigationStack {
          SettingsView()
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if usesVolatileStore {
        Label(
          "Entries can’t be stored permanently right now.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange)
      }
    }
  }
}
