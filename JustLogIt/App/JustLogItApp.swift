import SwiftData
import SwiftUI

@main
struct JustLogItApp: App {
  private let container: ModelContainer

  init() {
    do {
      let configuration = ModelConfiguration(
        isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
      container = try ModelContainer(for: FoodLogEntryRecord.self, configurations: configuration)
    } catch {
      do {
        // A volatile store keeps manual logging usable if the persistent store is damaged.
        container = try ModelContainer(
          for: FoodLogEntryRecord.self,
          configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
      } catch {
        // SwiftData cannot construct even an in-memory schema only when the compiled model is invalid.
        preconditionFailure("The compiled SwiftData schema is invalid.")
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      RootTabView()
    }
    .modelContainer(container)
  }
}
