import JustLogItCore
import XCTest

@testable import LoggingEval

final class DeterministicFirstCandidateSelectionTests: XCTestCase {
  func testPromotedInputSkipsBaselineAndReportsFastPathFamily() async {
    let baseline = EvaluatorBaselineSpy()
    let runner = EvalRunner(
      provider: DeterministicCandidateNoopProvider(),
      parseMode: .foundationModels,
      reasoningPolicy: .disabled,
      parserCandidate: .deterministicFirst,
      baselineParser: baseline
    )

    let report = await runner.run(cases: [
      .init(id: "apple", description: "apple", parsedOverride: nil)
    ])

    let result = report.cases[0]
    XCTAssertEqual(report.parserCandidate, "deterministic-first")
    XCTAssertEqual(report.reasoningPolicy, "disabled")
    XCTAssertEqual(result.parserCandidate, "deterministic-first")
    XCTAssertEqual(result.parseSource, "deterministicFirst.fastPath")
    XCTAssertEqual(result.interpretationRoute, "deterministicSearch")
    XCTAssertEqual(result.modelInvoked, false)
    XCTAssertEqual(result.deterministicFastPathUsed, true)
    XCTAssertEqual(result.deterministicFastPathFamily, "identityOnly")
    XCTAssertEqual(result.warmState, "notApplicable")
    XCTAssertNil(result.inputTokenCount)
    XCTAssertNil(result.prewarmLatencyMs)
    XCTAssertNotNil(result.deterministicExtractionLatencyMs)
    XCTAssertNotNil(result.routeDecisionLatencyMs)
    XCTAssertNil(result.semanticGroundingAndMergeLatencyMs)
    XCTAssertNotNil(result.timeToUSDADispatchMs)
    let calls = await baseline.calls
    XCTAssertEqual(calls, 0)
  }

  func testExcludedSemanticInputCallsBaselineOnceAndRetainsMetrics() async {
    let baseline = EvaluatorBaselineSpy()
    let runner = EvalRunner(
      provider: DeterministicCandidateNoopProvider(),
      parseMode: .foundationModels,
      warmState: .prewarmed,
      parserCandidate: .deterministicFirst,
      baselineParser: baseline
    )

    let report = await runner.run(cases: [
      .init(id: "meal", description: "eggs and toast", parsedOverride: nil)
    ])

    let result = report.cases[0]
    XCTAssertEqual(report.reasoningPolicy, "capabilityAwareLight")
    XCTAssertEqual(result.parseSource, "deterministicFirst.baselineFallback")
    XCTAssertEqual(result.interpretationRoute, "onDeviceSemantic")
    XCTAssertEqual(result.modelInvoked, true)
    XCTAssertEqual(result.deterministicFastPathUsed, false)
    XCTAssertNil(result.deterministicFastPathFamily)
    XCTAssertEqual(result.warmState, "prewarmed")
    XCTAssertEqual(result.prewarmLatencyMs, 11)
    XCTAssertEqual(result.inputTokenCount, 31)
    XCTAssertEqual(result.cachedInputTokenCount, 13)
    XCTAssertEqual(result.outputTokenCount, 7)
    XCTAssertEqual(result.reasoningTokenCount, 2)
    XCTAssertEqual(result.totalTokenCount, 40)
    XCTAssertNotNil(result.deterministicExtractionLatencyMs)
    XCTAssertNotNil(result.routeDecisionLatencyMs)
    XCTAssertNil(result.semanticGroundingAndMergeLatencyMs)
    XCTAssertNotNil(result.timeToUSDADispatchMs)
    let calls = await baseline.calls
    let warmStates = await baseline.requestedWarmStates
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(warmStates, [.prewarmed])
  }
}

private actor EvaluatorBaselineSpy: EvaluatorBaselineFoodParsing {
  private(set) var calls = 0
  private(set) var requestedWarmStates: [ParserEvaluationWarmState] = []

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    XCTFail("Evaluator candidate must use the metrics-capable baseline entry point")
    return .init(productName: "unexpected")
  }

  func parseWithMetrics(
    _ input: String,
    warmState: ParserEvaluationWarmState
  ) async throws -> MacFoundationModelsFoodParser.ParseResult {
    calls += 1
    requestedWarmStates.append(warmState)
    return .init(
      parsed: .init(productName: "eggs", searchTerms: "eggs"),
      usage: .init(
        inputTokenCount: 31,
        cachedInputTokenCount: 13,
        outputTokenCount: 7,
        reasoningTokenCount: 2,
        totalTokenCount: 40
      ),
      generationLatencyMilliseconds: 29,
      prewarmLatencyMilliseconds: 11
    )
  }
}

private actor DeterministicCandidateNoopProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    .init(foods: [], totalHits: 0, currentPage: 1, totalPages: 0)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw DeterministicCandidateProviderError.unexpectedDetails
  }
}

private enum DeterministicCandidateProviderError: Error {
  case unexpectedDetails
}
