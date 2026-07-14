import SwiftData
import SwiftUI

@main
struct JustLogItApp: App {
  var body: some Scene {
    // Never open SwiftData inside `App.init` — a slow/stuck store open keeps the
    // system launch screen up forever. Bootstrap paints first, then loads the container.
    WindowGroup {
      BootstrapRootView()
        .background(Color(.systemBackground))
    }
  }
}

/// First real frame after the launch screen. Builds the ModelContainer off the
/// critical path so a migration hiccup cannot pin the splash.
private struct BootstrapRootView: View {
  @State private var container: ModelContainer?
  @State private var usesVolatileStore = false
  @State private var bootError: String?

  var body: some View {
    Group {
      if let container {
        RootTabView()
          .environment(\.usesVolatileStore, usesVolatileStore)
          .modelContainer(container)
      } else if let bootError {
        ContentUnavailableView {
          Label("Couldn’t Start", systemImage: "exclamationmark.triangle")
        } description: {
          Text(bootError)
        } actions: {
          Button("Try Again") {
            self.bootError = nil
            boot()
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        ZStack {
          Color(.systemBackground)
          ProgressView("Starting…")
        }
        .task { boot() }
      }
    }
  }

  private func boot() {
    let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    if isUITesting {
      // UI tests reuse the simulator; start from a clean remembered-food store so
      // a pick saved by a prior run doesn't auto-select and skip the USDA picker.
      UserDefaultsRememberedFoodStore().clear()
    }
    do {
      let built = try ModelContainerFactory.make(isUITesting: isUITesting)
      container = built.container
      usesVolatileStore = built.usesVolatileStore
    } catch {
      // Absolute last resort in-process: in-memory empty store.
      do {
        let schema = ModelContainerFactory.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        usesVolatileStore = true
      } catch {
        bootError =
          "Local storage couldn’t open. Delete and reinstall JustLogIt, or free some space and try again."
      }
    }
  }
}

private struct UsesVolatileStoreKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var usesVolatileStore: Bool {
    get { self[UsesVolatileStoreKey.self] }
    set { self[UsesVolatileStoreKey.self] = newValue }
  }
}
