import Foundation
import SwiftData

@MainActor
enum HealthSyncCoordinator {
  static let preferenceKey = "healthSyncEnabled"

  static func syncIfEnabled(
    _ entry: FoodLogEntryRecord,
    modelContext: ModelContext,
    writer: any HealthNutritionWriting = HealthKitNutritionWriter.shared
  ) async {
    guard UserDefaults.standard.bool(forKey: preferenceKey) else { return }
    entry.healthSyncStatus = .pending
    entry.healthSyncError = nil
    try? modelContext.save()

    do {
      try await writer.save(
        entryID: entry.id,
        version: entry.healthSyncVersion,
        foodName: entry.displayName,
        consumedAt: entry.consumedAt,
        source: entry.source,
        fdcID: entry.fdcID,
        nutrients: entry.nutrients
      )
      entry.healthSyncStatus = .synced
      entry.healthSyncedAt = .now
      entry.healthSyncError = nil
    } catch let error as HealthKitWriteError {
      switch error {
      case .foodAccessDenied, .noAuthorizedNutrients:
        entry.healthSyncStatus = .denied
      case .unavailable:
        entry.healthSyncStatus = .failed
      }
      entry.healthSyncError = error.localizedDescription
    } catch {
      entry.healthSyncStatus = .failed
      entry.healthSyncError = "Apple Health couldn’t be updated."
    }
    try? modelContext.save()
  }
}
