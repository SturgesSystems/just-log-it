import Foundation
import JustLogItCore
import SwiftData

/// Reusable food identity derived from a confirmed log. Independent of entry history:
/// deleting an entry does not remove the recognized food, and forgetting a food does not erase entries.
@Model
final class RecognizedFoodRecord {
  @Attribute(.unique) var id: UUID
  var displayName: String
  var brand: String?
  var fdcID: Int?
  var usdaDataType: String?
  var lastUsedAt: Date
  var useCount: Int
  var servingHint: String?
  /// Optional nutrition snapshot from the most recent confirmed log (not authoritative for new logs).
  var nutrientsData: Data?
  /// Normalized lookup key for name-based upsert when no FDC ID is available.
  var normalizedName: String

  init(
    id: UUID = UUID(),
    displayName: String,
    brand: String? = nil,
    fdcID: Int? = nil,
    usdaDataType: String? = nil,
    lastUsedAt: Date = .now,
    useCount: Int = 1,
    servingHint: String? = nil,
    nutrients: [NutrientAmount]? = nil,
    normalizedName: String? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.brand = brand
    self.fdcID = fdcID
    self.usdaDataType = usdaDataType
    self.lastUsedAt = lastUsedAt
    self.useCount = max(1, useCount)
    self.servingHint = servingHint
    if let nutrients {
      nutrientsData = try? JSONEncoder().encode(nutrients)
    } else {
      nutrientsData = nil
    }
    let resolved =
      normalizedName
      ?? FoodLookupSignature.normalize(displayName)
    self.normalizedName = resolved
  }

  var nutrients: [NutrientAmount]? {
    get {
      guard let nutrientsData else { return nil }
      return try? JSONDecoder().decode([NutrientAmount].self, from: nutrientsData)
    }
    set {
      if let newValue {
        nutrientsData = try? JSONEncoder().encode(newValue)
      } else {
        nutrientsData = nil
      }
    }
  }

  /// Upserts a recognized food by FDC ID when present, otherwise by normalized display name.
  /// Returns the record that should be linked from the saved entry.
  @discardableResult
  static func upsert(
    from entry: FoodLogEntryRecord,
    in context: ModelContext,
    at date: Date = .now
  ) throws -> RecognizedFoodRecord {
    let displayName = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !displayName.isEmpty else {
      throw RecognizedFoodStoreError.emptyDisplayName
    }

    let existing = try findExisting(
      fdcID: entry.fdcID,
      displayName: displayName,
      in: context
    )

    if let existing {
      existing.displayName = displayName
      existing.brand = entry.brand
      if let fdcID = entry.fdcID, fdcID > 0 {
        existing.fdcID = fdcID
      }
      existing.usdaDataType = entry.usdaDataType
      existing.servingHint = entry.quantityDisplay
      existing.nutrients = entry.nutrients
      existing.lastUsedAt = date
      existing.useCount += 1
      existing.normalizedName = FoodLookupSignature.normalize(displayName)
      return existing
    }

    let record = RecognizedFoodRecord(
      displayName: displayName,
      brand: entry.brand,
      fdcID: (entry.fdcID).flatMap { $0 > 0 ? $0 : nil },
      usdaDataType: entry.usdaDataType,
      lastUsedAt: date,
      useCount: 1,
      servingHint: entry.quantityDisplay,
      nutrients: entry.nutrients
    )
    context.insert(record)
    return record
  }

  static func findExisting(
    fdcID: Int?,
    displayName: String,
    in context: ModelContext
  ) throws -> RecognizedFoodRecord? {
    if let fdcID, fdcID > 0 {
      var descriptor = FetchDescriptor<RecognizedFoodRecord>(
        predicate: #Predicate { $0.fdcID == fdcID }
      )
      descriptor.fetchLimit = 1
      if let match = try context.fetch(descriptor).first {
        return match
      }
    }

    let normalized = FoodLookupSignature.normalize(displayName)
    guard !normalized.isEmpty else { return nil }
    var byName = FetchDescriptor<RecognizedFoodRecord>(
      predicate: #Predicate { $0.normalizedName == normalized }
    )
    byName.fetchLimit = 1
    return try context.fetch(byName).first
  }
}

enum RecognizedFoodStoreError: Error {
  case emptyDisplayName
}

// FoodLogSaveTransaction lives in FoodLogRepository.swift (shared UI + Siri save path).
