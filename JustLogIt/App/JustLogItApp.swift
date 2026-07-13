import SwiftData
import SwiftUI

@main
struct JustLogItApp: App {
  private let container: ModelContainer
  private let usesVolatileStore: Bool

  init() {
    do {
      let configuration = ModelConfiguration(
        isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
      container = try ModelContainer(for: FoodLogEntryRecord.self, configurations: configuration)
      usesVolatileStore = false
    } catch {
      do {
        // A volatile store keeps manual logging usable if the persistent store is damaged.
        container = try ModelContainer(
          for: FoodLogEntryRecord.self,
          configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        usesVolatileStore = true
      } catch {
        // SwiftData cannot construct even an in-memory schema only when the compiled model is invalid.
        preconditionFailure("The compiled SwiftData schema is invalid.")
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      RootTabView()
        .environment(\.usesVolatileStore, usesVolatileStore)
    }
    .modelContainer(container)
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
