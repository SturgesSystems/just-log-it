import Foundation
import JustLogItCore
import SwiftData

@Model
final class FoodLogEntryRecord {
  @Attribute(.unique) var id: UUID
  var createdAt: Date
  var consumedAt: Date
  var modifiedAt: Date
  var originalText: String
  var displayName: String
  var brand: String?
  var quantityDisplay: String
  var isApproximate: Bool
  var sourceRawValue: String
  var fdcID: Int?
  var usdaDescription: String?
  var usdaDataType: String?
  var calculationBasisRawValue: String
  var servingMultiplier: Double?
  var consumedGrams: Double?
  var nutrientsData: Data
  var healthSyncStatusRawValue: String = HealthSyncStatus.notRequested.rawValue
  var healthSyncVersion: Int = 1
  var healthSyncedAt: Date?
  var healthSyncError: String?
  var healthSyncRetryCount: Int = 0
  var healthSyncNextRetryAt: Date?
  /// Link to the recognized food identity created/updated when this entry was saved.
  var recognizedFoodID: UUID?
  /// True when this entry is an aggregated multi-component meal.
  /// Optional for lightweight migration from stores that predate composites.
  var isComposite: Bool?
  /// Encoded `[CompositeComponentSnapshot]` when composite is true.
  var componentPayload: Data?

  init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    consumedAt: Date = .now,
    modifiedAt: Date = .now,
    originalText: String,
    displayName: String,
    brand: String? = nil,
    quantityDisplay: String,
    isApproximate: Bool,
    source: EntrySource,
    fdcID: Int? = nil,
    usdaDescription: String? = nil,
    usdaDataType: String? = nil,
    calculationBasis: CalculationBasis,
    servingMultiplier: Double? = nil,
    consumedGrams: Double? = nil,
    nutrients: [NutrientAmount],
    recognizedFoodID: UUID? = nil,
    isComposite: Bool = false,
    components: [CompositeComponentSnapshot]? = nil
  ) throws {
    self.id = id
    self.createdAt = createdAt
    self.consumedAt = consumedAt
    self.modifiedAt = modifiedAt
    self.originalText = originalText
    self.displayName = displayName
    self.brand = brand
    self.quantityDisplay = quantityDisplay
    self.isApproximate = isApproximate
    sourceRawValue = source.rawValue
    self.fdcID = fdcID
    self.usdaDescription = usdaDescription
    self.usdaDataType = usdaDataType
    calculationBasisRawValue = calculationBasis.rawValue
    self.servingMultiplier = servingMultiplier
    self.consumedGrams = consumedGrams
    nutrientsData = try JSONEncoder().encode(nutrients)
    self.recognizedFoodID = recognizedFoodID
    if let components, !components.isEmpty {
      componentPayload = try JSONEncoder().encode(components)
      self.isComposite = true
    } else {
      componentPayload = nil
      self.isComposite = isComposite ? true : false
    }
  }

  var isCompositeEntry: Bool {
    isComposite == true || !components.isEmpty
  }

  var source: EntrySource {
    EntrySource(rawValue: sourceRawValue) ?? .manual
  }

  var calculationBasis: CalculationBasis {
    CalculationBasis(rawValue: calculationBasisRawValue) ?? .manual
  }

  var nutrients: [NutrientAmount] {
    (try? JSONDecoder().decode([NutrientAmount].self, from: nutrientsData)) ?? []
  }

  /// Decoded composite components; empty when not a composite or payload is corrupt.
  var components: [CompositeComponentSnapshot] {
    get {
      guard let componentPayload else { return [] }
      return (try? JSONDecoder().decode([CompositeComponentSnapshot].self, from: componentPayload))
        ?? []
    }
    set {
      if newValue.isEmpty {
        componentPayload = nil
        isComposite = false
      } else {
        componentPayload = try? JSONEncoder().encode(newValue)
        isComposite = true
      }
    }
  }

  var calories: Double? {
    nutrients.first(where: { $0.key == .energy })?.amount
  }

  var protein: Double? {
    nutrients.first(where: { $0.key == .protein })?.amount
  }

  var healthSyncStatus: HealthSyncStatus {
    get { HealthSyncStatus(rawValue: healthSyncStatusRawValue) ?? .notRequested }
    set { healthSyncStatusRawValue = newValue.rawValue }
  }
}

enum HealthSyncStatus: String, Codable {
  case notRequested
  case pending
  case synced
  case denied
  case failed
  case deletionPending
}

@Model
final class HealthDeletionTombstone {
  @Attribute(.unique) var entryID: UUID
  var healthSyncVersion: Int
  var createdAt: Date
  var retryCount: Int
  var nextRetryAt: Date?
  var lastError: String?

  init(
    entryID: UUID,
    healthSyncVersion: Int,
    createdAt: Date = .now,
    retryCount: Int = 0,
    nextRetryAt: Date? = nil,
    lastError: String? = nil
  ) {
    self.entryID = entryID
    self.healthSyncVersion = healthSyncVersion
    self.createdAt = createdAt
    self.retryCount = retryCount
    self.nextRetryAt = nextRetryAt
    self.lastError = lastError
  }
}

enum EntrySource: String, Codable, Sendable {
  case usda = "USDA"
  case manual = "Manual"
}
