import JustLogItCore
import XCTest

@testable import LoggingEval

final class HybridCandidateSelectionTests: XCTestCase {
  func testHybridDeterministicRouteDoesNotInvokeSemanticModel() async {
    let proposer = EvaluatorSemanticSpy(
      proposal: .init(productName: "should not run")
    )
    let runner = EvalRunner(
      provider: CandidateNoopProvider(),
      parseMode: .foundationModelsOrFake,
      parserCandidate: .hybrid,
      semanticProposer: proposer
    )

    let report = await runner.run(cases: [
      .init(id: "apple", description: "apple", parsedOverride: nil)
    ])

    XCTAssertEqual(report.parserCandidate, "hybrid")
    XCTAssertEqual(report.cases[0].interpretationRoute, "deterministicSearch")
    XCTAssertEqual(report.cases[0].modelInvoked, false)
    XCTAssertNotNil(report.cases[0].deterministicExtractionLatencyMs)
    XCTAssertNotNil(report.cases[0].routeDecisionLatencyMs)
    XCTAssertNil(report.cases[0].semanticGroundingAndMergeLatencyMs)
    XCTAssertNotNil(report.cases[0].timeToUSDADispatchMs)
    let calls = await proposer.calls
    XCTAssertEqual(calls, 0)
  }

  func testHybridSemanticRouteInvokesOnlySemanticCandidateOnce() async {
    let proposer = EvaluatorSemanticSpy(
      proposal: .init(
        productName: "",
        containsMultipleFoods: true,
        componentNames: ["eggs", "toast"]
      )
    )
    let provider = CandidateNoopProvider()
    let runner = EvalRunner(
      provider: provider,
      parseMode: .foundationModelsOrFake,
      parserCandidate: .hybrid,
      semanticProposer: proposer
    )

    let report = await runner.run(cases: [
      .init(id: "meal", description: "eggs and toast", parsedOverride: nil)
    ])

    XCTAssertEqual(report.cases[0].interpretationRoute, "composite")
    XCTAssertEqual(report.cases[0].modelInvoked, true)
    XCTAssertEqual(report.cases[0].resolutionStatus, "composite")
    XCTAssertNotNil(report.cases[0].deterministicExtractionLatencyMs)
    XCTAssertNotNil(report.cases[0].routeDecisionLatencyMs)
    XCTAssertNotNil(report.cases[0].semanticGroundingAndMergeLatencyMs)
    XCTAssertNil(report.cases[0].timeToUSDADispatchMs)
    let calls = await proposer.calls
    let searchCalls = await provider.searchCalls
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(searchCalls, 0)
  }

  func testGroundedApproximationUsesSemanticIdentityAndPreservesDeterministicAmount() async {
    let proposer = EvaluatorSemanticSpy(proposal: .init(productName: "olive oil"))
    let runner = EvalRunner(
      provider: CandidateNoopProvider(),
      parseMode: .foundationModelsOrFake,
      parserCandidate: .hybrid,
      semanticProposer: proposer
    )

    let report = await runner.run(cases: [
      .init(
        id: "approximation",
        description: "Nearly two tablespoons olive oil",
        parsedOverride: nil
      )
    ])

    let result = report.cases[0]
    XCTAssertEqual(result.interpretationRoute, "onDeviceSemantic")
    XCTAssertEqual(result.routeReasons, ["groundedApproximation"])
    XCTAssertEqual(result.modelInvoked, true)
    XCTAssertEqual(result.productName, "olive oil")
    XCTAssertEqual(result.quantity, 2)
    XCTAssertEqual(UnitConversion.family(result.unit ?? ""), "tbsp")
    let calls = await proposer.calls
    XCTAssertEqual(calls, 1)
  }

  func testParsedOverrideIsNeverMislabelledAsHybrid() async {
    let proposer = EvaluatorSemanticSpy(proposal: .init(productName: "wrong"))
    let runner = EvalRunner(
      provider: CandidateNoopProvider(),
      parseMode: .foundationModelsOrFake,
      parserCandidate: .hybrid,
      semanticProposer: proposer
    )

    let report = await runner.run(cases: [
      .init(
        id: "override",
        description: "apple",
        parsedOverride: .init(productName: "apple", searchTerms: "apple")
      )
    ])

    XCTAssertEqual(report.cases[0].parserCandidate, "override")
    XCTAssertNil(report.cases[0].modelInvoked)
    let calls = await proposer.calls
    XCTAssertEqual(calls, 0)
  }

  func testHybridPrewarmedCandidateUsesMetricsCapabilityAndReportsUsage() async {
    let proposer = EvaluatorMetricsSemanticSpy()
    let runner = EvalRunner(
      provider: CandidateNoopProvider(),
      parseMode: .foundationModels,
      warmState: .prewarmed,
      parserCandidate: .hybrid,
      semanticProposer: proposer
    )

    let report = await runner.run(cases: [
      .init(id: "meal", description: "eggs and toast", parsedOverride: nil)
    ])

    let result = report.cases[0]
    let requestedWarmStates = await proposer.requestedWarmStates
    XCTAssertEqual(requestedWarmStates, [.prewarmed])
    XCTAssertEqual(result.warmState, "prewarmed")
    XCTAssertEqual(result.semanticResponseLatencyMs, 34)
    XCTAssertEqual(result.prewarmLatencyMs, 12)
    XCTAssertEqual(result.inputTokenCount, 21)
    XCTAssertEqual(result.cachedInputTokenCount, 8)
    XCTAssertEqual(result.outputTokenCount, 5)
    XCTAssertEqual(result.reasoningTokenCount, 3)
    XCTAssertEqual(result.totalTokenCount, 29)
    XCTAssertEqual(report.p50SemanticResponseLatencyMs, 34)
    XCTAssertEqual(report.p95SemanticResponseLatencyMs, 34)
  }
}

private actor EvaluatorMetricsSemanticSpy: EvaluatorSemanticFoodProposing {
  private(set) var requestedWarmStates: [ParserEvaluationWarmState] = []

  func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
    XCTFail("Metrics-capable evaluator proposer should use proposeWithMetrics")
    return .init(productName: "")
  }

  func proposeWithMetrics(
    _ input: SemanticFoodProposalInput,
    warmState: ParserEvaluationWarmState
  ) async throws -> EvaluatorSemanticProposalResult {
    requestedWarmStates.append(warmState)
    return .init(
      proposal: .init(
        productName: "",
        containsMultipleFoods: true,
        componentNames: ["eggs", "toast"]
      ),
      usage: .init(
        inputTokenCount: 21,
        cachedInputTokenCount: 8,
        outputTokenCount: 5,
        reasoningTokenCount: 3,
        totalTokenCount: 29
      ),
      generationLatencyMilliseconds: 34,
      prewarmLatencyMilliseconds: 12
    )
  }
}

private actor EvaluatorSemanticSpy: SemanticFoodProposing {
  let proposal: SemanticFoodProposal
  private(set) var calls = 0

  init(proposal: SemanticFoodProposal) {
    self.proposal = proposal
  }

  func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
    calls += 1
    return proposal
  }
}

private actor CandidateNoopProvider: FoodDataProviding {
  private(set) var searchCalls = 0

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    searchCalls += 1
    return .init(foods: [], totalHits: 0, currentPage: 1, totalPages: 0)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw CandidateProviderError.unexpectedDetails
  }
}

private enum CandidateProviderError: Error {
  case unexpectedDetails
}
