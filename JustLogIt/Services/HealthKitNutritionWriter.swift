import Foundation
import HealthKit
import JustLogItCore
import OSLog

enum HealthKitWriteError: LocalizedError {
  case unavailable
  case noAuthorizedNutrients
  case authorizationDisallowed(String)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Apple Health isn’t available on this device."
    case .noAuthorizedNutrients:
      return "Apple Health didn’t grant permission for these nutrients."
    case .authorizationDisallowed(let detail):
      if detail.localizedCaseInsensitiveContains("disallowed") {
        return
          "Apple Health couldn’t authorize nutrition write access for this build. Try again on a device, or review Health permissions in Settings."
      }
      if detail.isEmpty {
        return
          "Apple Health couldn’t open the permission sheet for this build. Check HealthKit signing and try again on a device."
      }
      return detail
    }
  }

  /// Privacy-safe fragment for local logs (closed labels, not free-form food text).
  var loggingDetail: String {
    switch self {
    case .unavailable: "unavailable"
    case .noAuthorizedNutrients: "no_authorized_nutrients"
    case .authorizationDisallowed(let detail):
      if detail.localizedCaseInsensitiveContains("disallowed") { "disallowed" }
      else if detail.isEmpty { "empty" }
      else { "other" }
    }
  }

  /// Maps HealthKit authorization failures (callback errors or ObjC exceptions) into a
  /// user-visible error without crashing. Disallowed-share failures become a recovery message.
  static func authorizationFailure(from detail: String) -> HealthKitWriteError {
    .authorizationDisallowed(detail)
  }

  static func authorizationFailure(from error: Error) -> HealthKitWriteError {
    if let writeError = error as? HealthKitWriteError { return writeError }
    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return .authorizationDisallowed(detail)
  }
}

private let healthKitWriterLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "JustLogIt",
  category: "HealthKitWriter"
)

struct HealthAuthorizationSummary: Sendable, Equatable {
  let authorizedNutrientCount: Int
  let requestedNutrientCount: Int

  var canWrite: Bool { authorizedNutrientCount > 0 }
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
  func delete(entryID: UUID, version: Int) async throws
}

extension HealthNutritionWriting {
  func delete(entryID: UUID, version: Int) async throws {
    throw HealthKitWriteError.unavailable
  }
}

actor HealthKitNutritionWriter: HealthNutritionWriting {
  static let shared = HealthKitNutritionWriter()

  nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  private let store = HKHealthStore()

  func requestAuthorization() async throws -> HealthAuthorizationSummary {
    guard isAvailable else { throw HealthKitWriteError.unavailable }
    // Correlations are not authorized as types. Apple requires permission for the
    // *constituent* quantity samples only (dietary energy, protein, …). Requesting
    // HKCorrelationType.food in toShare raises:
    //   "Authorization to share … HKCorrelationTypeIdentifierFood is disallowed"
    // We still *save* a Food correlation after those nutrients are authorized.
    let shareTypes = Set(
      HealthKitNutrientMapping.requestableShareTypes.map { $0 as HKSampleType })
    guard !shareTypes.isEmpty else { throw HealthKitWriteError.unavailable }

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      final class Once: @unchecked Sendable {
        private var finished = false
        private let lock = NSLock()
        let continuation: CheckedContinuation<Void, Error>
        init(_ continuation: CheckedContinuation<Void, Error>) {
          self.continuation = continuation
        }
        func resume(_ result: Result<Void, Error>) {
          lock.lock()
          defer { lock.unlock() }
          guard !finished else { return }
          finished = true
          continuation.resume(with: result)
        }
      }
      let once = Once(continuation)
      // HealthKit may throw NSException synchronously when the signed product is not
      // allowed to request write access (missing entitlement / simulator provisioning).
      // Catch that ObjC exception so Settings/retry can show a recovery message instead of SIGABRT.
      let exception = JustLogItCatchException {
        self.store.requestAuthorization(toShare: shareTypes, read: []) { success, error in
          if let error {
            let mapped = HealthKitWriteError.authorizationFailure(from: error)
            healthKitWriterLogger.error(
              "authorization_callback_failure detail=\(mapped.loggingDetail, privacy: .public)"
            )
            once.resume(.failure(mapped))
          } else if success {
            once.resume(.success(()))
          } else {
            once.resume(
              .failure(
                HealthKitWriteError.authorizationDisallowed(
                  "Apple Health did not complete the permission request."
                )))
          }
        }
      }
      if let exception {
        let reason = exception.reason ?? exception.name.rawValue
        let mapped = HealthKitWriteError.authorizationFailure(from: reason)
        healthKitWriterLogger.error(
          "authorization_exception detail=\(mapped.loggingDetail, privacy: .public)"
        )
        once.resume(.failure(mapped))
      }
    }
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
    guard let foodType = HealthKitNutrientMapping.foodCorrelationType else {
      throw HealthKitWriteError.unavailable
    }

    var objects = Set<HKSample>()
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
      objects.insert(
        HKQuantitySample(
          type: mapping.quantityType,
          quantity: HKQuantity(unit: mapping.unit, doubleValue: nutrient.amount),
          start: consumedAt,
          end: consumedAt,
          metadata: metadata
        ))
    }
    guard !objects.isEmpty else { throw HealthKitWriteError.noAuthorizedNutrients }

    // One Food correlation groups the authorized nutrient samples (Health’s “meal” unit).
    // Auth is on those samples — not on the correlation type itself.
    var metadata: [String: Any] = [
      HKMetadataKeyFoodType: foodName,
      HKMetadataKeySyncIdentifier: "\(entryID.uuidString).food",
      HKMetadataKeySyncVersion: version,
      "JustLogItSource": source.rawValue,
    ]
    if let fdcID { metadata["JustLogItFDCID"] = fdcID }
    let correlation = HKCorrelation(
      type: foodType,
      start: consumedAt,
      end: consumedAt,
      objects: objects,
      metadata: metadata
    )
    try await store.save(correlation)
  }

  func delete(entryID: UUID, version _: Int) async throws {
    guard isAvailable else { throw HealthKitWriteError.unavailable }

    for target in HealthKitNutrientMapping.deletionTargets(entryID: entryID) {
      let predicate = HKQuery.predicateForObjects(
        withMetadataKey: HKMetadataKeySyncIdentifier,
        operatorType: .equalTo,
        value: target.syncIdentifier
      )
      _ = try await store.deleteObjects(of: target.type, predicate: predicate)
    }
  }

  private func authorizationSummary() -> HealthAuthorizationSummary {
    let authorized = HealthKitNutrientMapping.requestableShareTypes.filter {
      store.authorizationStatus(for: $0) == .sharingAuthorized
    }.count
    return HealthAuthorizationSummary(
      authorizedNutrientCount: authorized,
      requestedNutrientCount: HealthKitNutrientMapping.requestableShareTypes.count
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
    unit = Self.unit(forCanonicalUnit: key.canonicalUnit)
  }

  static var foodCorrelationType: HKCorrelationType? {
    HKObjectType.correlationType(forIdentifier: .food)
  }

  /// Every modeled USDA nutrient that HealthKit can represent. The writer already
  /// filters individual samples by the person's authorization status, so the
  /// initial request must include the same complete set the save path supports.
  /// Food correlations are intentionally excluded — they are save-only, not share-auth.
  static var requestableShareTypes: [HKQuantityType] {
    allQuantityTypes
  }

  static var allQuantityTypes: [HKQuantityType] {
    allMappings.map(\.quantityType)
  }

  static var allMappings: [HealthKitNutrientMapping] {
    NutrientKey.allCases.compactMap(HealthKitNutrientMapping.init)
  }

  static func deletionTargets(entryID: UUID) -> [(type: HKObjectType, syncIdentifier: String)] {
    var targets: [(type: HKObjectType, syncIdentifier: String)] = []
    if let food = foodCorrelationType {
      targets.append((food, "\(entryID.uuidString).food"))
    }
    targets += allMappings.map {
      ($0.quantityType, "\(entryID.uuidString).\($0.key.rawValue)")
    }
    return targets
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

  /// Resolves a canonical nutrient unit string to an `HKUnit`. Unknown units fall back
  /// to grams and log — never `preconditionFailure` / crash the save path.
  static func unit(forCanonicalUnit unitString: String) -> HKUnit {
    switch unitString {
    case "kcal":
      return HKUnit.kilocalorie()
    case "g":
      return HKUnit.gram()
    case "mg":
      return HKUnit.gramUnit(with: .milli)
    case "µg":
      return HKUnit.gramUnit(with: .micro)
    case "mL":
      return HKUnit.literUnit(with: .milli)
    default:
      healthKitWriterLogger.error(
        "unexpected_nutrient_unit unit=\(unitString, privacy: .public) fallback=gram"
      )
      return HKUnit.gram()
    }
  }
}
