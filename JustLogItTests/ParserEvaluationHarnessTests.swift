import Foundation
import FoundationModels
import JustLogItCore
import XCTest

@testable import JustLogIt

final class ParserEvaluationCorpusTests: XCTestCase {
  func testCorpusVersionCategoriesAndIdentifiersAreComplete() {
    XCTAssertEqual(ParserEvaluationCorpus.version, "1.0.0")
    XCTAssertEqual(
      Set(ParserEvaluationCorpus.cases.map(\.category)),
      Set(ParserEvaluationCategory.allCases)
    )
    XCTAssertEqual(
      Set(ParserEvaluationCorpus.cases.map(\.id)).count,
      ParserEvaluationCorpus.cases.count
    )
    XCTAssertTrue(ParserEvaluationCorpus.cases.allSatisfy { !$0.input.isEmpty })
  }

  func testLeanPromptIsMateriallyShorterButProductionRemainsDefault() {
    let production = FoundationModelsPromptProfile.production.instructions
    let lean = FoundationModelsPromptProfile.leanCandidate.instructions

    XCTAssertLessThan(lean.count, Int(Double(production.count) * 0.65))
    XCTAssertTrue(production.contains("fractionOfWhole"))
    XCTAssertTrue(lean.contains("componentNames"))
    _ = FoundationModelsFoodParser()
  }

  func testCorpusExpectedProductsAreSourceGrounded() {
    for evaluationCase in ParserEvaluationCorpus.cases where !evaluationCase.productTokens.isEmpty {
      let product = evaluationCase.productTokens.joined(separator: " ")
      let candidate = ParsedFoodRequest(productName: product, searchTerms: "untrusted query")
      let grounded = ParsedFoodRequestGrounder().ground(candidate, in: evaluationCase.input)
      XCTAssertFalse(
        grounded.productName.isEmpty,
        "Corpus expectation is not grounded for case \(evaluationCase.id)"
      )
      XCTAssertEqual(grounded.searchTerms, grounded.productName)
    }
  }
}

final class OnDeviceParserEvaluationTests: XCTestCase {
  private let environment = ProcessInfo.processInfo.environment

  func testProductionAndLeanCandidateOnDevice() async throws {
    guard environment["RUN_ON_DEVICE_PARSER_EVAL"] == "1" else {
      throw XCTSkip("Set RUN_ON_DEVICE_PARSER_EVAL=1 for the manual on-device parser evaluation.")
    }
    guard case .available = SystemLanguageModel.default.availability else {
      throw XCTSkip("The on-device Foundation Model is not available on this destination.")
    }

    let repeats = min(max(Int(environment["PARSER_EVAL_REPEATS"] ?? "2") ?? 2, 2), 5)
    let includeInput = environment["PARSER_EVAL_INCLUDE_INPUT"] == "1"
    var observations: [ParserEvaluationObservation] = []

    for profile in FoundationModelsPromptProfile.allCases {
      let parser = FoundationModelsFoodParser(promptProfile: profile)
      for evaluationCase in ParserEvaluationCorpus.cases {
        var firstResult: ParsedFoodRequest?
        for run in 1...repeats {
          if let prelude = evaluationCase.prelude {
            _ = try? await parser.parse(prelude)
          }
          let started = ContinuousClock.now
          do {
            let parsed = try await parser.parse(evaluationCase.input)
            let elapsed = started.duration(to: .now)
            let scores = ParserEvaluationScorer.score(parsed, for: evaluationCase)
            let stable = firstResult.map { $0 == parsed }
            if firstResult == nil { firstResult = parsed }
            observations.append(
              ParserEvaluationObservation(
                corpusVersion: ParserEvaluationCorpus.version,
                promptProfile: profile.rawValue,
                caseID: evaluationCase.id,
                category: evaluationCase.category,
                run: run,
                outcome: "parsed",
                errorKind: nil,
                latencyMilliseconds: elapsed.milliseconds,
                sourceGrounded: scores.sourceGrounded,
                requiredFieldsCorrect: scores.requiredFieldsCorrect,
                unsupportedInventedFacts: scores.unsupportedInventedFacts,
                behaviorCorrect: scores.behaviorCorrect,
                stableWithFirstRun: stable,
                humanReviewRequired: evaluationCase.disposition == .humanReview,
                input: includeInput ? evaluationCase.input : nil
              ))
          } catch {
            let elapsed = started.duration(to: .now)
            observations.append(
              ParserEvaluationObservation(
                corpusVersion: ParserEvaluationCorpus.version,
                promptProfile: profile.rawValue,
                caseID: evaluationCase.id,
                category: evaluationCase.category,
                run: run,
                outcome: "error",
                errorKind: Self.errorKind(error),
                latencyMilliseconds: elapsed.milliseconds,
                sourceGrounded: nil,
                requiredFieldsCorrect: nil,
                unsupportedInventedFacts: false,
                behaviorCorrect: ParserEvaluationScorer.errorBehaviorCorrect(for: evaluationCase),
                stableWithFirstRun: nil,
                humanReviewRequired: evaluationCase.disposition == .humanReview,
                input: includeInput ? evaluationCase.input : nil
              ))
          }
        }
      }
    }

    let report = ParserEvaluationReport.make(observations: observations, repeats: repeats)
    let reportURL = try Self.writeReport(report)
    let attachment = XCTAttachment(contentsOfFile: reportURL)
    attachment.name = "JustLogIt parser evaluation \(ParserEvaluationCorpus.version)"
    attachment.lifetime = .keepAlways
    add(attachment)

    guard let production = report.summaries.first(where: { $0.promptProfile == "production" })
    else {
      XCTFail("Production summary is missing")
      return
    }
    XCTAssertEqual(production.sourceGroundingRate, 1, accuracy: 0.000_1)
    XCTAssertEqual(production.unsupportedInventedFactCount, 0)
    XCTAssertGreaterThanOrEqual(production.requiredFieldRate, 0.90)
    XCTAssertGreaterThanOrEqual(production.behaviorRate, 0.85)
    XCTAssertGreaterThanOrEqual(production.stabilityRate, 0.90)
    XCTAssertLessThanOrEqual(production.p95LatencyMilliseconds, 15_000)
  }

  private static func errorKind(_ error: any Error) -> String {
    guard let parserError = error as? FoodParserError else { return "other" }
    return switch parserError {
    case .emptyInput: "empty_input"
    case .invalidResponse: "invalid_response"
    case .unavailable: "unavailable"
    }
  }

  private static func writeReport(_ report: ParserEvaluationReport) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "JustLogItParserEvaluation", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "parser-evaluation-\(report.corpusVersion).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: url, options: .atomic)
    return url
  }
}

private enum ParserEvaluationScorer {
  struct Scores {
    let sourceGrounded: Bool
    let requiredFieldsCorrect: Bool?
    let unsupportedInventedFacts: Bool
    let behaviorCorrect: Bool?
  }

  static func score(_ parsed: ParsedFoodRequest, for evaluationCase: ParserEvaluationCase) -> Scores
  {
    let regrounded = ParsedFoodRequestGrounder().ground(parsed, in: evaluationCase.input)
    let sourceGrounded = regrounded == parsed && !parsed.productName.isEmpty
    return Scores(
      sourceGrounded: sourceGrounded,
      requiredFieldsCorrect: requiredFieldsCorrect(parsed, for: evaluationCase),
      unsupportedInventedFacts: !sourceGrounded,
      behaviorCorrect: parsedBehaviorCorrect(parsed, for: evaluationCase)
    )
  }

  static func errorBehaviorCorrect(for evaluationCase: ParserEvaluationCase) -> Bool? {
    switch evaluationCase.disposition {
    case .reject, .clarifyOrReject, .multipleOrReject: true
    case .accept, .clarify: false
    case .humanReview: nil
    }
  }

  private static func requiredFieldsCorrect(
    _ parsed: ParsedFoodRequest,
    for evaluationCase: ParserEvaluationCase
  ) -> Bool? {
    guard evaluationCase.disposition != .humanReview else { return nil }
    let productTokens = normalizedTokens(parsed.productName)
    guard
      evaluationCase.productTokens.allSatisfy({ expected in
        productTokens.contains(where: { tokenMatches($0, expected.lowercased()) })
      })
    else { return false }

    switch evaluationCase.brand {
    case .ignore:
      break
    case .absent:
      guard parsed.brand == nil else { return false }
    case .exact(let expected):
      guard normalizedTokens(parsed.brand ?? "") == normalizedTokens(expected) else { return false }
    }

    switch evaluationCase.amount {
    case .ignore:
      break
    case .absent:
      guard !hasSafeAmount(parsed) else { return false }
    case .quantity(let expected, let units):
      guard approximatelyEqual(parsed.quantity, expected),
        units.contains(where: { unitMatches(parsed.unit, $0) })
      else { return false }
    case .fraction(let expected, let wholeUnits, let containerSize, let containerUnits):
      guard approximatelyEqual(parsed.fractionOfWhole, expected),
        wholeUnits.contains(where: { unitMatches(parsed.wholeUnit, $0) })
      else { return false }
      if let containerSize {
        guard approximatelyEqual(parsed.containerSize, containerSize),
          containerUnits.contains(where: { unitMatches(parsed.containerSizeUnit, $0) })
        else { return false }
      }
    }

    if let expectedApproximation = evaluationCase.expectsApproximation,
      parsed.isApproximate != expectedApproximation
    {
      return false
    }
    return true
  }

  private static func parsedBehaviorCorrect(
    _ parsed: ParsedFoodRequest,
    for evaluationCase: ParserEvaluationCase
  ) -> Bool? {
    switch evaluationCase.disposition {
    case .accept: true
    case .clarify, .clarifyOrReject: !hasSafeAmount(parsed)
    case .multipleOrReject: parsed.containsMultipleFoods
    case .reject: false
    case .humanReview: nil
    }
  }

  private static func hasSafeAmount(_ parsed: ParsedFoodRequest) -> Bool {
    (parsed.quantity != nil && parsed.unit != nil)
      || (parsed.fractionOfWhole != nil && parsed.wholeUnit != nil)
      || (parsed.alternateQuantity != nil && parsed.alternateUnit != nil)
  }

  private static func approximatelyEqual(_ actual: Double?, _ expected: Double) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) <= max(0.000_001, abs(expected) * 0.000_001)
  }

  private static func unitMatches(_ actual: String?, _ expected: String) -> Bool {
    guard let actual else { return false }
    return tokenMatches(
      normalizedTokens(actual).joined(),
      normalizedTokens(expected).joined()
    )
  }

  private static func normalizedTokens(_ value: String) -> [String] {
    value.lowercased()
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
  }

  private static func tokenMatches(_ lhs: String, _ rhs: String) -> Bool {
    lhs == rhs || singular(lhs) == singular(rhs)
  }

  private static func singular(_ value: String) -> String {
    value.count > 3 && value.hasSuffix("s") ? String(value.dropLast()) : value
  }
}

private struct ParserEvaluationObservation: Codable {
  let corpusVersion: String
  let promptProfile: String
  let caseID: String
  let category: ParserEvaluationCategory
  let run: Int
  let outcome: String
  let errorKind: String?
  let latencyMilliseconds: Double
  let sourceGrounded: Bool?
  let requiredFieldsCorrect: Bool?
  let unsupportedInventedFacts: Bool
  let behaviorCorrect: Bool?
  let stableWithFirstRun: Bool?
  let humanReviewRequired: Bool
  let input: String?
}

private struct ParserEvaluationSummary: Codable {
  let promptProfile: String
  let sourceGroundingRate: Double
  let requiredFieldRate: Double
  let behaviorRate: Double
  let stabilityRate: Double
  let unsupportedInventedFactCount: Int
  let p95LatencyMilliseconds: Double
}

private struct ParserEvaluationReport: Codable {
  let corpusVersion: String
  let generatedAt: Date
  let destinationOS: String
  let repeats: Int
  let includesInputText: Bool
  let summaries: [ParserEvaluationSummary]
  let leanCandidateEligible: Bool
  let observations: [ParserEvaluationObservation]

  static func make(
    observations: [ParserEvaluationObservation],
    repeats: Int
  ) -> ParserEvaluationReport {
    let summaries = FoundationModelsPromptProfile.allCases.map { profile in
      summarize(observations.filter { $0.promptProfile == profile.rawValue }, profile: profile)
    }
    let production = summaries.first { $0.promptProfile == "production" }!
    let lean = summaries.first { $0.promptProfile == "leanCandidate" }!
    let leanEligible =
      lean.sourceGroundingRate == 1
      && lean.unsupportedInventedFactCount == 0
      && lean.requiredFieldRate >= max(0.90, production.requiredFieldRate)
      && lean.behaviorRate >= max(0.85, production.behaviorRate)
      && lean.stabilityRate >= max(0.90, production.stabilityRate - 0.02)
      && lean.p95LatencyMilliseconds <= production.p95LatencyMilliseconds * 1.10
    return ParserEvaluationReport(
      corpusVersion: ParserEvaluationCorpus.version,
      generatedAt: .now,
      destinationOS: ProcessInfo.processInfo.operatingSystemVersionString,
      repeats: repeats,
      includesInputText: observations.contains { $0.input != nil },
      summaries: summaries,
      leanCandidateEligible: leanEligible,
      observations: observations
    )
  }

  private static func summarize(
    _ observations: [ParserEvaluationObservation],
    profile: FoundationModelsPromptProfile
  ) -> ParserEvaluationSummary {
    ParserEvaluationSummary(
      promptProfile: profile.rawValue,
      sourceGroundingRate: rate(observations.compactMap(\.sourceGrounded)),
      requiredFieldRate: rate(observations.compactMap(\.requiredFieldsCorrect)),
      behaviorRate: rate(observations.compactMap(\.behaviorCorrect)),
      stabilityRate: rate(observations.compactMap(\.stableWithFirstRun)),
      unsupportedInventedFactCount: observations.filter(\.unsupportedInventedFacts).count,
      p95LatencyMilliseconds: percentile95(observations.map(\.latencyMilliseconds))
    )
  }

  private static func rate(_ values: [Bool]) -> Double {
    guard !values.isEmpty else { return 1 }
    return Double(values.filter { $0 }.count) / Double(values.count)
  }

  private static func percentile95(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(Int(ceil(Double(sorted.count) * 0.95)) - 1, sorted.count - 1)
    return sorted[max(0, index)]
  }
}

extension Duration {
  fileprivate var milliseconds: Double {
    let components = self.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
