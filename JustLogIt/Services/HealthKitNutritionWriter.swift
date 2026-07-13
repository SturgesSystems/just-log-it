import Foundation
import HealthKit
import JustLogItCore

enum HealthKitWriteError: LocalizedError {
  case unavailable
  case foodAccessDenied
  case noAuthorizedNutrients

  var errorDescription: String? {
    switch self {
    case .unavailable: "Apple Health isn’t available on this device."
    case .foodAccessDenied: "Apple Health didn’t grant permission to save food entries."
    case .noAuthorizedNutrients: "Apple Health didn’t grant permission for these nutrients."
    }
  }
}

struct HealthAuthorizationSummary: Sendable, Equatable {
  let authorizedNutrientCount: Int
  let requestedNutrientCount: Int
  let canWriteFood: Bool

  var canWrite: Bool { canWriteFood && authorizedNutrientCount > 0 }
}

protocol HealthNutritionWriting: Sendable {
  var isAvailable: Bool { get }
  func requestAuthorization() async throws -> HealthAuthorizationSummary
  func save(
    entryID: UUID,
    version: Int,
    foodName: String,
    consumedAt: Date,
    source: EntrySource,
    fdcID: Int?,
    nutrients: [NutrientAmount]
  ) async throws
}

actor HealthKitNutritionWriter: HealthNutritionWriting {
  static let shared = HealthKitNutritionWriter()

  nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  private let store = HKHealthStore()

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    guard isAvailable else { throw HealthKitWriteError.unavailable }
    let nutrients = Set(HealthKitNutrientMapping.allQuantityTypes.map { $0 as HKSampleType })
    let shareTypes = nutrients.union([HealthKitNutrientMapping.foodType])
    try await store.requestAuthorization(toShare: shareTypes, read: [])
    return authorizationSummary()
  }

  func save(
    entryID: UUID,
    version: Int,
    foodName: String,
    consumedAt: Date,
    source: EntrySource,
    fdcID: Int?,
    nutrients: [NutrientAmount]
  ) async throws {
    guard isAvailable else { throw HealthKitWriteError.unavailable }
    guard store.authorizationStatus(for: HealthKitNutrientMapping.foodType) == .sharingAuthorized
    else { throw HealthKitWriteError.foodAccessDenied }

    var samples = Set<HKSample>()
    var seen = Set<NutrientKey>()
    for nutrient in nutrients where nutrient.amount.isFinite && nutrient.amount >= 0 {
      guard !seen.contains(nutrient.key),
        let mapping = HealthKitNutrientMapping(nutrient.key),
        store.authorizationStatus(for: mapping.quantityType) == .sharingAuthorized
      else { continue }
      seen.insert(nutrient.key)
      let metadata: [String: Any] = [
        HKMetadataKeySyncIdentifier: "\(entryID.uuidString).\(nutrient.key.rawValue)",
        HKMetadataKeySyncVersion: version,
      ]
      samples.insert(
        HKQuantitySample(
          type: mapping.quantityType,
          quantity: HKQuantity(unit: mapping.unit, doubleValue: nutrient.amount),
          start: consumedAt,
          end: consumedAt,
          metadata: metadata
        ))
    }
    guard !samples.isEmpty else { throw HealthKitWriteError.noAuthorizedNutrients }

    var metadata: [String: Any] = [
      HKMetadataKeyFoodType: foodName,
      HKMetadataKeySyncIdentifier: "\(entryID.uuidString).food",
      HKMetadataKeySyncVersion: version,
      "JustLogItSource": source.rawValue,
    ]
    if let fdcID { metadata["JustLogItFDCID"] = fdcID }
    let correlation = HKCorrelation(
      type: HealthKitNutrientMapping.foodType,
      start: consumedAt,
      end: consumedAt,
      objects: samples,
      metadata: metadata
    )
    try await store.save(correlation)
  }

  private func authorizationSummary() -> HealthAuthorizationSummary {
    let authorized = HealthKitNutrientMapping.allQuantityTypes.filter {
      store.authorizationStatus(for: $0) == .sharingAuthorized
    }.count
    return HealthAuthorizationSummary(
      authorizedNutrientCount: authorized,
      requestedNutrientCount: HealthKitNutrientMapping.allQuantityTypes.count,
      canWriteFood: store.authorizationStatus(for: HealthKitNutrientMapping.foodType)
        == .sharingAuthorized
    )
  }
}

struct HealthKitNutrientMapping: Sendable {
  let key: NutrientKey
  let quantityType: HKQuantityType
  let unit: HKUnit

  init?(_ key: NutrientKey) {
    guard key != .addedSugar, let identifier = Self.identifier(for: key),
      let type = HKObjectType.quantityType(forIdentifier: identifier)
    else { return nil }
    self.key = key
    quantityType = type
    unit = Self.unit(for: key)
  }

  static let foodType = HKObjectType.correlationType(forIdentifier: .food)!

  static var allQuantityTypes: [HKQuantityType] {
    NutrientKey.allCases.compactMap { HealthKitNutrientMapping($0)?.quantityType }
  }

  private static func identifier(for key: NutrientKey) -> HKQuantityTypeIdentifier? {
    switch key {
    case .energy: .dietaryEnergyConsumed
    case .protein: .dietaryProtein
    case .carbohydrate: .dietaryCarbohydrates
    case .totalFat: .dietaryFatTotal
    case .saturatedFat: .dietaryFatSaturated
    case .monounsaturatedFat: .dietaryFatMonounsaturated
    case .polyunsaturatedFat: .dietaryFatPolyunsaturated
    case .cholesterol: .dietaryCholesterol
    case .fiber: .dietaryFiber
    case .totalSugar: .dietarySugar
    case .addedSugar: nil
    case .sodium: .dietarySodium
    case .calcium: .dietaryCalcium
    case .iron: .dietaryIron
    case .potassium: .dietaryPotassium
    case .vitaminD: .dietaryVitaminD
    case .caffeine: .dietaryCaffeine
    case .water: .dietaryWater
    case .biotin: .dietaryBiotin
    case .chloride: .dietaryChloride
    case .chromium: .dietaryChromium
    case .copper: .dietaryCopper
    case .folate: .dietaryFolate
    case .iodine: .dietaryIodine
    case .magnesium: .dietaryMagnesium
    case .manganese: .dietaryManganese
    case .molybdenum: .dietaryMolybdenum
    case .niacin: .dietaryNiacin
    case .pantothenicAcid: .dietaryPantothenicAcid
    case .phosphorus: .dietaryPhosphorus
    case .riboflavin: .dietaryRiboflavin
    case .selenium: .dietarySelenium
    case .thiamin: .dietaryThiamin
    case .vitaminA: .dietaryVitaminA
    case .vitaminB12: .dietaryVitaminB12
    case .vitaminB6: .dietaryVitaminB6
    case .vitaminC: .dietaryVitaminC
    case .vitaminE: .dietaryVitaminE
    case .vitaminK: .dietaryVitaminK
    case .zinc: .dietaryZinc
    }
  }

  private static func unit(for key: NutrientKey) -> HKUnit {
    switch key.canonicalUnit {
    case "kcal": .kilocalorie()
    case "g": .gram()
    case "mg": .gramUnit(with: .milli)
    case "µg": .gramUnit(with: .micro)
    case "mL": .literUnit(with: .milli)
    default: preconditionFailure("Unsupported canonical nutrient unit")
    }
  }
}
