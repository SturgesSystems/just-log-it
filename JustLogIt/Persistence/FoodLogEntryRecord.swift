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
    nutrients: [NutrientAmount]
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
}

enum EntrySource: String, Codable, Sendable {
  case usda = "USDA"
  case manual = "Manual"
}
