import Foundation
import SwiftData

/// Builds the app ModelContainer without destroying an unreadable on-disk store.
/// A migration or transient open failure falls back to a visibly volatile store;
/// the original database remains available for a future migration or recovery.
enum ModelContainerFactory {
  private static let appSupportSubdirectory = "JustLogIt"
  private static let storeFileName = "default.store"

  static var schema: Schema {
    Schema([
      FoodLogEntryRecord.self,
      HealthDeletionTombstone.self,
      RecognizedFoodRecord.self,
    ])
  }

  static func make(
    isUITesting: Bool,
    persistentStoreURL: URL? = nil,
    forceVolatileStore: Bool = false
  ) throws -> (container: ModelContainer, usesVolatileStore: Bool) {
    if forceVolatileStore {
      let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return (container, true)
    }

    if isUITesting {
      let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return (container, false)
    }

    // Prefer the normal on-disk store at an explicit URL (create parent dirs first).
    do {
      let storeURL = try persistentStoreURL ?? prepareStoreURL()
      let configuration = ModelConfiguration(
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return (container, false)
    } catch {
      // Preserve the failed store. Destructive recovery is never an acceptable
      // response to an unidentified migration, file-protection, disk, or framework
      // error. The persistent warning explains that new entries are temporary.
      let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return (container, true)
    }
  }

  /// Last-resort construction used only when both the requested persistent store
  /// and `make`'s ordinary in-memory fallback could not be opened.
  static func makeEmergencyVolatile() throws -> ModelContainer {
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  /// Ensures Application Support / JustLogIt exists and returns the store file URL.
  /// SwiftData/Core Data can fail at launch if the parent directory is missing.
  private static func prepareStoreURL() throws -> URL {
    let fileManager = FileManager.default
    guard
      let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else {
      throw CocoaError(.fileNoSuchFile)
    }

    let directory = appSupport.appending(
      path: appSupportSubdirectory, directoryHint: .isDirectory)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: storeFileName)
  }

}

/// The complete value transferred from the background bootstrap worker to the
/// main actor. SwiftData's SDK declaration makes `ModelContainer` itself
/// `@unchecked Sendable`; this app does not add or broaden that conformance.
struct ModelContainerBootstrapResult: Sendable {
  let container: ModelContainer
  let usesVolatileStore: Bool
  let category: AppObservability.BootstrapStoreCategory
}

/// Runs every potentially blocking SwiftData open on a detached executor. The
/// synchronous operation is injectable so scheduling and stale-result behavior
/// can be tested without timing-dependent store migrations.
struct ModelContainerBootstrapBuilder: Sendable {
  typealias Operation =
    @Sendable (AppLaunchArgumentPolicy.Mode) throws -> ModelContainerBootstrapResult

  private let operation: Operation

  init(operation: @escaping Operation = Self.liveOperation) {
    self.operation = operation
  }

  func build(for mode: AppLaunchArgumentPolicy.Mode) async throws
    -> ModelContainerBootstrapResult
  {
    let operation = self.operation
    let worker = Task.detached(priority: .userInitiated) {
      try operation(mode)
    }

    return try await withTaskCancellationHandler {
      let result = try await worker.value
      try Task.checkCancellation()
      return result
    } onCancel: {
      worker.cancel()
    }
  }

  private static func liveOperation(
    _ mode: AppLaunchArgumentPolicy.Mode
  ) throws -> ModelContainerBootstrapResult {
    do {
      let built = try ModelContainerFactory.make(
        isUITesting: mode.isUITesting,
        forceVolatileStore: mode.forcesVolatileStore
      )
      let category: AppObservability.BootstrapStoreCategory
      if mode.forcesVolatileStore {
        category = .forcedVolatile
      } else if mode.isUITesting {
        category = .testingMemory
      } else if built.usesVolatileStore {
        category = .fallbackVolatile
      } else {
        category = .persistent
      }
      return ModelContainerBootstrapResult(
        container: built.container,
        usesVolatileStore: built.usesVolatileStore,
        category: category
      )
    } catch {
      return ModelContainerBootstrapResult(
        container: try ModelContainerFactory.makeEmergencyVolatile(),
        usesVolatileStore: true,
        category: .emergencyVolatile
      )
    }
  }
}
