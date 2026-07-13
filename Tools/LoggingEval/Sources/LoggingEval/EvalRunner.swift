import Foundation
import JustLogItCore

struct EvalCaseInput: Sendable {
  let id: String
  let description: String
  let parsedOverride: ParsedFoodRequest?
}

struct EvalCaseReport: Codable, Sendable {
  var id: String
  var input: String
  var parseSource: String
  var modelAvailability: String?
  var parseLatencyMs: Double?
  var brand: String?
  var productName: String?
  var quantity: Double?
  var unit: String?
  var fractionOfWhole: Double?
  var containerSize: Double?
  var containerSizeUnit: String?
  var containsMultipleFoods: Bool?
  var searchQuery: String?
  var topFdcID: Int?
  var topDescription: String?
  var topDataType: String?
  var resolutionStatus: String
  var resolutionDisplay: String?
  var consumedGrams: Double?
  var hasEnergy: Bool
  var energyKcal: Double?
  var checks: [String: Bool]
  var error: String?
}

struct EvalReport: Codable, Sendable {
  var generatedAt: String
  var foundationModelsAvailability: String
  var caseCount: Int
  var passCount: Int
  var failCount: Int
  var cases: [EvalCaseReport]
}

enum ParseMode: String, Sendable {
  /// Use Foundation Models when available; error if unavailable unless fallback allowed.
  case foundationModels
  /// Force the crude deterministic fake (debug only).
  case fake
  /// Prefer Foundation Models; fall back to fake if unavailable.
  case foundationModelsOrFake
}

@available(macOS 26.4, *)
struct EvalRunner {
  private let provider: any FoodDataProviding
  private let parseMode: ParseMode
  private let parser = MacFoundationModelsFoodParser()
  private let queryBuilder = FoodSearchQueryBuilder()
  private let ranker = FoodSearchResultRanker()
  private let resolver = ServingResolutionService()
  private let calculator = NutritionCalculator()

  init(provider: any FoodDataProviding, parseMode: ParseMode = .foundationModels) {
    self.provider = provider
    self.parseMode = parseMode
  }

  func run(cases: [EvalCaseInput]) async -> EvalReport {
    var reports: [EvalCaseReport] = []
    for item in cases {
      reports.append(await evaluate(item))
    }
    let passCount = reports.filter(\.passed).count
    return EvalReport(
      generatedAt: ISO8601DateFormatter().string(from: Date()),
      foundationModelsAvailability: MacFoundationModelsFoodParser.availabilityDescription,
      caseCount: reports.count,
      passCount: passCount,
      failCount: reports.count - passCount,
      cases: reports
    )
  }

  private func evaluate(_ item: EvalCaseInput) async -> EvalCaseReport {
    var report = EvalCaseReport(
      id: item.id,
      input: item.description,
      parseSource: "pending",
      modelAvailability: MacFoundationModelsFoodParser.availabilityDescription,
      parseLatencyMs: nil,
      brand: nil,
      productName: nil,
      quantity: nil,
      unit: nil,
      fractionOfWhole: nil,
      containerSize: nil,
      containerSizeUnit: nil,
      containsMultipleFoods: nil,
      searchQuery: nil,
      topFdcID: nil,
      topDescription: nil,
      topDataType: nil,
      resolutionStatus: "notRun",
      resolutionDisplay: nil,
      consumedGrams: nil,
      hasEnergy: false,
      energyKcal: nil,
      checks: [:],
      error: nil
    )

    let parsed: ParsedFoodRequest
    if let override = item.parsedOverride {
      parsed = override
      report.parseSource = "parsedJSON"
    } else {
      do {
        let started = ContinuousClock.now
        let (value, source) = try await parseDescription(item.description)
        parsed = value
        report.parseSource = source
        let elapsed = started.duration(to: .now)
        let components = elapsed.components
        report.parseLatencyMs =
          Double(components.seconds) * 1_000
          + Double(components.attoseconds) / 1_000_000_000_000_000
      } catch {
        report.parseSource = "parseFailed"
        report.error = String(describing: error)
        report.resolutionStatus = "error"
        report.checks = Self.checks(
          hasEnergy: false, gramsOK: false, resolved: false, hadQuantity: false)
        return report
      }
    }

    report.productName = parsed.productName
    report.brand = parsed.brand
    report.quantity = parsed.quantity
    report.unit = parsed.unit
    report.fractionOfWhole = parsed.fractionOfWhole
    report.containerSize = parsed.containerSize
    report.containerSizeUnit = parsed.containerSizeUnit
    report.containsMultipleFoods = parsed.containsMultipleFoods

    let searchRequest = queryBuilder.build(from: parsed)
    report.searchQuery = searchRequest.query

    do {
      let response = try await provider.search(searchRequest)
      let ranked = ranker.rank(response.foods, for: parsed)
      guard let top = ranked.first else {
        report.resolutionStatus = "noResults"
        report.error = "No USDA foods matched"
        report.checks = Self.checks(
          hasEnergy: false,
          gramsOK: false,
          resolved: false,
          hadQuantity: parsed.quantity != nil
        )
        return report
      }

      report.topFdcID = top.fdcID
      report.topDescription = top.description
      report.topDataType = top.dataType

      let details = try await provider.foodDetails(fdcID: top.fdcID)
      let hasEnergyInRecord =
        details.nutrientsPer100Grams.contains { $0.key == .energy }
        || details.nutrientsPerServing.contains { $0.key == .energy }

      switch resolver.resolve(parsed, against: details) {
      case .needsClarification(let explanation):
        report.resolutionStatus = "needsClarification"
        report.resolutionDisplay = explanation
        report.hasEnergy = hasEnergyInRecord
        report.checks = Self.checks(
          hasEnergy: hasEnergyInRecord,
          gramsOK: true,  // N/A when no quantity path — not a hard fail
          resolved: false,
          hadQuantity: parsed.quantity != nil || parsed.fractionOfWhole != nil
        )
        // When quantity was present, needing clarification is a soft failure for grams check.
        if parsed.quantity != nil || parsed.fractionOfWhole != nil {
          report.checks["consumedGramsFinitePositiveWhenQuantityPresent"] = false
        }
      case .resolved(let resolution):
        report.resolutionStatus = "resolved"
        report.resolutionDisplay = resolution.displayText
        report.consumedGrams = resolution.consumedGrams
        do {
          let nutrients = try calculator.calculate(food: details, resolution: resolution)
          if let energy = nutrients.first(where: { $0.key == .energy }) {
            report.hasEnergy = true
            report.energyKcal = energy.amount
          } else {
            report.hasEnergy = hasEnergyInRecord
          }
        } catch {
          report.hasEnergy = hasEnergyInRecord
        }

        let quantityPresent = parsed.quantity != nil || parsed.fractionOfWhole != nil
        let grams = resolution.consumedGrams
        let gramsOK: Bool
        if quantityPresent {
          // Prefer grams when mass-resolvable; serving-only resolutions may leave grams nil.
          if let grams {
            gramsOK = grams.isFinite && grams > 0
          } else if resolution.servingMultiplier != nil {
            gramsOK = true
          } else {
            gramsOK = false
          }
        } else {
          gramsOK = true
        }

        report.checks = Self.checks(
          hasEnergy: report.hasEnergy,
          gramsOK: gramsOK,
          resolved: true,
          hadQuantity: quantityPresent
        )
      }
    } catch {
      report.error = String(describing: error)
      report.resolutionStatus = "error"
      report.checks = Self.checks(
        hasEnergy: false,
        gramsOK: false,
        resolved: false,
        hadQuantity: false
      )
    }

    return report
  }

  private func parseDescription(_ description: String) async throws -> (
    ParsedFoodRequest, String
  ) {
    switch parseMode {
    case .foundationModels:
      return (try await parser.parse(description), "foundationModels")
    case .fake:
      return (Self.deterministicFakeParse(description), "deterministicFake")
    case .foundationModelsOrFake:
      if MacFoundationModelsFoodParser.isAvailable {
        return (try await parser.parse(description), "foundationModels")
      }
      return (Self.deterministicFakeParse(description), "deterministicFake")
    }
  }

  /// Deterministic stand-in when Foundation Models / --parsed-json is unavailable.
  /// Treats the whole string as product name; extracts a leading number + unit when present.
  static func deterministicFakeParse(_ input: String) -> ParsedFoodRequest {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^(\d+(?:\.\d+)?)\s*([a-zA-Z]+)\s+(.+)$"#
    if let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
      let qtyRange = Range(match.range(at: 1), in: trimmed),
      let unitRange = Range(match.range(at: 2), in: trimmed),
      let nameRange = Range(match.range(at: 3), in: trimmed),
      let quantity = Double(trimmed[qtyRange])
    {
      let unit = String(trimmed[unitRange])
      let name = String(trimmed[nameRange])
      return ParsedFoodRequest(
        productName: name,
        searchTerms: name,
        quantity: quantity,
        unit: unit,
        quantityText: "\(quantity) \(unit)"
      )
    }
    return ParsedFoodRequest(productName: trimmed, searchTerms: trimmed)
  }

  private static func checks(
    hasEnergy: Bool,
    gramsOK: Bool,
    resolved: Bool,
    hadQuantity: Bool
  ) -> [String: Bool] {
    [
      "energyNutrientPresent": hasEnergy,
      "consumedGramsFinitePositiveWhenQuantityPresent": gramsOK,
      "servingResolved": resolved,
      "inputHadQuantity": hadQuantity,
    ]
  }
}

extension EvalCaseReport {
  var passed: Bool {
    if error != nil { return false }
    guard checks["energyNutrientPresent"] == true else { return false }
    guard checks["consumedGramsFinitePositiveWhenQuantityPresent"] == true else { return false }
    // Accept either full resolution or clarification when no quantity was supplied.
    if checks["servingResolved"] == true { return true }
    if checks["inputHadQuantity"] == false && resolutionStatus == "needsClarification" {
      return true
    }
    return false
  }
}
