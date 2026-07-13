import Foundation
import SwiftData

/// Builds the app ModelContainer with resilient recovery when the on-disk store
/// cannot open after a schema change (common cause of a stuck launch screen).
enum ModelContainerFactory {
  private static let appSupportSubdirectory = "JustLogIt"
  private static let storeFileName = "default.store"
  /// Bump when adding models that cannot lightweight-migrate in place.
  private static let schemaEpochKey = "justlogit.swiftdata.schemaEpoch"
  private static let schemaEpoch = 2  // RecognizedFoodRecord + composite fields

  static var schema: Schema {
    Schema([
      FoodLogEntryRecord.self,
      HealthDeletionTombstone.self,
      RecognizedFoodRecord.self,
    ])
  }

  static func make(isUITesting: Bool) throws -> (container: ModelContainer, usesVolatileStore: Bool) {
    if isUITesting {
      let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return (container, false)
    }

    // One-time wipe when the schema epoch advances. Avoids silent hang/black screen
    // on devices whose on-disk store cannot open with the new models.
    migrateSchemaEpochIfNeeded()

    // 1) Prefer the normal on-disk store at an explicit URL (create parent dirs first).
    do {
      let storeURL = try prepareStoreURL()
      let configuration = ModelConfiguration(
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
      )
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return (container, false)
    } catch {
      // 2) Schema migration failure: wipe the local store once and retry.
      destroyApplicationSupportStore()
      do {
        let storeURL = try prepareStoreURL()
        let configuration = ModelConfiguration(
          schema: schema,
          url: storeURL,
          cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, false)
      } catch {
        // 3) Last resort: volatile in-memory store so the app still launches.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, true)
      }
    }
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

  private static func migrateSchemaEpochIfNeeded() {
    let defaults = UserDefaults.standard
    let current = defaults.integer(forKey: schemaEpochKey)
    guard current < schemaEpoch else { return }
    destroyApplicationSupportStore()
    defaults.set(schemaEpoch, forKey: schemaEpochKey)
  }

  /// Removes the default SwiftData/application-support store files if present.
  static func destroyApplicationSupportStore() {
    let fileManager = FileManager.default
    guard
      let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else { return }

    // Our store + any legacy locations SwiftData may have used.
    let candidates = [
      appSupport.appending(path: storeFileName),
      appSupport.appending(path: appSupportSubdirectory, directoryHint: .isDirectory),
      appSupport.appending(
        path: Bundle.main.bundleIdentifier ?? "JustLogIt", directoryHint: .isDirectory),
    ]

    for url in candidates {
      try? fileManager.removeItem(at: url)
      // SQLite sidecars next to a file store.
      if url.pathExtension == "store" {
        try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
      }
    }

    // Also clear Default.store variants SwiftData uses.
    if let contents = try? fileManager.contentsOfDirectory(
      at: appSupport, includingPropertiesForKeys: nil)
    {
      for item in contents {
        let name = item.lastPathComponent.lowercased()
        if name.contains("default")
          && (name.hasSuffix(".store") || name.contains("swiftdata") || name.hasSuffix("-shm")
            || name.hasSuffix("-wal"))
        {
          try? fileManager.removeItem(at: item)
        }
      }
    }
  }
}
