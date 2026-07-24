import Foundation
import FoundationModels
import JustLogItCore
import XCTest

@testable import JustLogIt

final class ParserEvaluationCorpusTests: XCTestCase {
  func testCorpusVersionCategoriesAndIdentifiersAreComplete() {
    XCTAssertEqual(ParserEvaluationCorpus.version, "1.4.0")
    XCTAssertEqual(
      Set(ParserEvaluationCorpus.cases.map(\.category)),
      Set(ParserEvaluationCategory.allCases)
    )
    XCTAssertEqual(
      Set(ParserEvaluationCorpus.cases.map(\.id)).count,
      ParserEvaluationCorpus.cases.count
    )
    XCTAssertTrue(ParserEvaluationCorpus.cases.allSatisfy { !$0.input.isEmpty })
    XCTAssertEqual(
      Set(ParserEvaluationCorpus.cases.map(\.expectedRoute)),
      Set([
        FoodInterpretationRoute.deterministicSearch,
        .onDeviceSemantic,
        .clarification,
        .composite,
        .manualSearch,
      ])
    )
  }

  func testTypedRouteScoringDoesNotTreatAllBlockedRoutesAsEquivalent() {
    let evaluationCase = ParserEvaluationCorpus.cases.first { $0.id == "nonfood.weather" }!

    XCTAssertTrue(ParserEvaluationScorer.routeCorrect(.manualSearch, for: evaluationCase))
    XCTAssertFalse(ParserEvaluationScorer.routeCorrect(.clarification, for: evaluationCase))
    XCTAssertFalse(
      ParserEvaluationScorer.routeCorrect(.composite, for: evaluationCase)
    )
  }

  func testEvaluatedHybridRouteUsesTheSamePostPolicyTerminalOutcomeAsTheApp() async throws {
    let interpreter = HybridFoodInterpreter(proposer: InvalidEvaluatorSemanticProposer())
    let result = try await interpreter.interpret(
      semanticContext: "eggs and toast",
      groundingText: "eggs and toast"
    )

    XCTAssertEqual(result.finalDecision.route, .manualSearch)
    XCTAssertEqual(result.finalDecision.route, result.terminalResolution.route)
    guard case .requireEdit = result.terminalResolution.decision else {
      return XCTFail("Invalid grounded output must terminate in editable recovery")
    }
  }

  func testLeanPromptIsMateriallyShorterButProductionRemainsDefault() {
    let production = FoundationModelsPromptProfile.production.instructions
    let lean = FoundationModelsPromptProfile.leanCandidate.instructions

    XCTAssertLessThan(lean.count, Int(Double(production.count) * 0.65))
    XCTAssertTrue(production.contains("fractionOfWhole"))
    XCTAssertTrue(lean.contains("componentNames"))
    _ = FoundationModelsFoodParser()
  }

  func testParserModelUseCasesExposeGeneralAndContentTaggingForDeviceEvaluation() {
    XCTAssertEqual(
      FoundationModelsModelUseCase.allCases.map(\.rawValue),
      ["general", "contentTagging"]
    )
    XCTAssertEqual(FoundationModelsModelUseCase.general.systemUseCase, .general)
    XCTAssertEqual(FoundationModelsModelUseCase.contentTagging.systemUseCase, .contentTagging)

    // Construction must remain side-effect free; availability is checked only
    // when prewarming or parsing on an eligible device.
    _ = FoundationModelsFoodParser(modelUseCase: .contentTagging)
  }

  func testReasoningIsRequestedOnlyWhenTheSelectedModelSupportsIt() {
    XCTAssertNil(
      FoundationModelsFoodParser.contextOptions(supportsReasoning: false).reasoningLevel)
    XCTAssertEqual(
      FoundationModelsFoodParser.contextOptions(supportsReasoning: true).reasoningLevel,
      .light
    )
    XCTAssertNil(
      FoundationModelsFoodParser.contextOptions(
        supportsReasoning: true,
        reasoningPolicy: .disabled
      ).reasoningLevel
    )
    XCTAssertEqual(
      FoundationModelsReasoningPolicy.allCases.map(\.rawValue),
      ["capabilityAwareLight", "disabled"]
    )
  }

  func testEvaluationMetricsRecorderIsContentFreeBoundedAndOneShot() async throws {
    let recorder = FoundationModelsEvaluationMetricsRecorder()
    await recorder.recordPrewarm(.seconds(-2))
    await recorder.beginInvocation()
    await recorder.recordSessionAcquisition(.milliseconds(3))
    await recorder.recordResponse(
      .milliseconds(11),
      inputTokenCount: 20,
      cachedInputTokenCount: 4,
      outputTokenCount: 9,
      reasoningTokenCount: -7,
      totalTokenCount: 29
    )
    await recorder.recordMapping(.seconds(900))
    await recorder.finishInvocation()

    let completed = await recorder.takeCompletedInvocation()
    let captured = try XCTUnwrap(completed)
    XCTAssertEqual(captured.prewarmLatencyMilliseconds, 0)
    XCTAssertEqual(captured.sessionAcquisitionLatencyMilliseconds ?? -1, 3, accuracy: 0.001)
    XCTAssertEqual(captured.responseLatencyMilliseconds ?? -1, 11, accuracy: 0.001)
    XCTAssertEqual(captured.mappingLatencyMilliseconds, 600_000)
    XCTAssertEqual(captured.inputTokenCount, 20)
    XCTAssertEqual(captured.cachedInputTokenCount, 4)
    XCTAssertEqual(captured.outputTokenCount, 9)
    XCTAssertEqual(captured.reasoningTokenCount, 0)
    XCTAssertEqual(captured.totalTokenCount, 29)
    let consumedAgain = await recorder.takeCompletedInvocation()
    XCTAssertNil(consumedAgain)

    await recorder.beginInvocation()
    await recorder.recordResponse(.milliseconds(17))
    await recorder.finishInvocation()
    let nextCompleted = await recorder.takeCompletedInvocation()
    let next = try XCTUnwrap(nextCompleted)
    XCTAssertNil(next.prewarmLatencyMilliseconds, "Prewarm timing must not bleed into another run")
    XCTAssertEqual(next.responseLatencyMilliseconds ?? -1, 17, accuracy: 0.001)
    XCTAssertNil(next.inputTokenCount, "Usage must not bleed into another run")
  }

  func testReportSummarizesObservableModelMetricsWithoutInventedLatencyLabels() throws {
    let first = promotionObservation(
      candidate: .hybrid,
      profile: FoundationModelsSemanticPromptProfile.minimal.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      modelInvoked: true,
      inputTokenCount: 20,
      cachedInputTokenCount: 5,
      outputTokenCount: 8,
      reasoningTokenCount: 2,
      totalTokenCount: 28,
      prewarmLatencyMilliseconds: 4,
      sessionAcquisitionLatencyMilliseconds: 2,
      responseLatencyMilliseconds: 30,
      deterministicExtractionLatencyMilliseconds: 1,
      routeDecisionLatencyMilliseconds: 3,
      groundingAndMergeLatencyMilliseconds: 5
    )
    let second = promotionObservation(
      candidate: .hybrid,
      profile: FoundationModelsSemanticPromptProfile.minimal.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      run: 2,
      modelInvoked: true,
      inputTokenCount: 30,
      cachedInputTokenCount: 7,
      outputTokenCount: 12,
      reasoningTokenCount: 4,
      totalTokenCount: 42,
      prewarmLatencyMilliseconds: 8,
      sessionAcquisitionLatencyMilliseconds: 4,
      responseLatencyMilliseconds: 50,
      deterministicExtractionLatencyMilliseconds: 2,
      routeDecisionLatencyMilliseconds: 4,
      groundingAndMergeLatencyMilliseconds: 7
    )

    let report = ParserEvaluationReport.make(observations: [first, second], repeats: 2)
    let summary = try XCTUnwrap(report.summaries.first)
    XCTAssertEqual(summary.averageInputTokenCount, 25)
    XCTAssertEqual(summary.averageCachedInputTokenCount, 6)
    XCTAssertEqual(summary.averageOutputTokenCount, 10)
    XCTAssertEqual(summary.averageReasoningTokenCount, 3)
    XCTAssertEqual(summary.averageTotalTokenCount, 35)
    XCTAssertEqual(summary.p50PrewarmLatencyMilliseconds, 4)
    XCTAssertEqual(summary.p95PrewarmLatencyMilliseconds, 8)
    XCTAssertEqual(summary.p50SessionAcquisitionLatencyMilliseconds, 2)
    XCTAssertEqual(summary.p95SessionAcquisitionLatencyMilliseconds, 4)
    XCTAssertEqual(summary.p50ResponseLatencyMilliseconds, 30)
    XCTAssertEqual(summary.p95ResponseLatencyMilliseconds, 50)
    XCTAssertEqual(summary.averageDeterministicExtractionLatencyMilliseconds, 1.5)
    XCTAssertEqual(summary.averageRouteDecisionLatencyMilliseconds, 3.5)
    XCTAssertEqual(summary.averageGroundingAndMergeLatencyMilliseconds, 6)

    let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
    XCTAssertTrue(json.contains("\"responseLatencyMilliseconds\""))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("modelLoad"))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("timeToFirstToken"))
  }

  func testBaselineParserUsesConversationForMeaningButOnlyCurrentUserTextForGrounding() throws {
    let inputs = try FoundationModelsFoodParser.normalizedInputs(
      semanticContext: "ASSISTANT: How many?\nUSER: two apples",
      groundingText: "apple\ntwo apples"
    )

    XCTAssertEqual(inputs.semanticContext, "ASSISTANT: How many?\nUSER: two apples")
    XCTAssertEqual(inputs.groundingText, "apple\ntwo apples")
    XCTAssertFalse(inputs.groundingText.contains("ASSISTANT"))
  }

  func testBaselineParserRejectsEmptyGroundingEvenWhenAssistantContextIsPresent() {
    XCTAssertThrowsError(
      try FoundationModelsFoodParser.normalizedInputs(
        semanticContext: "ASSISTANT: Say a food",
        groundingText: "  "
      )
    ) { error in
      guard case FoodParserError.emptyInput = error else {
        XCTFail("Expected emptyInput, got \(error)")
        return
      }
    }
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

  func testScorerTreatsIdentityFreeClarificationAsGroundedAndSafelyBlocked() {
    let evaluationCase = ParserEvaluationCorpus.cases.first { $0.id == "nonfood.weather" }!
    let parsed = ParsedFoodRequest(
      productName: "",
      searchTerms: "",
      clarificationPrompt: "What food would you like to log?"
    )

    let scores = ParserEvaluationScorer.score(parsed, for: evaluationCase)

    XCTAssertTrue(scores.sourceGrounded)
    XCTAssertFalse(scores.unsupportedInventedFacts)
    XCTAssertTrue(scores.behaviorCorrect == true)
    XCTAssertEqual(scores.usdaRouting, .blocked)
  }

  func testScorerRecognizesSafeCompositeHandoff() {
    let evaluationCase = ParserEvaluationCorpus.cases.first { $0.id == "multiple.eggs.toast" }!
    let parsed = ParsedFoodRequest(
      productName: "",
      searchTerms: "",
      containsMultipleFoods: true,
      componentNames: ["eggs", "toast"]
    )

    let scores = ParserEvaluationScorer.score(parsed, for: evaluationCase)

    XCTAssertTrue(scores.sourceGrounded)
    XCTAssertFalse(scores.unsupportedInventedFacts)
    XCTAssertTrue(scores.behaviorCorrect == true)
    XCTAssertEqual(scores.usdaRouting, .compositeHandoff)
  }

  func testScorerDoesNotCallSilentSearchAClarificationSuccess() {
    let evaluationCase = ParserEvaluationCorpus.cases.first { $0.id == "ambiguous.some.rice" }!
    let parsed = ParsedFoodRequest(productName: "rice", searchTerms: "rice")

    let scores = ParserEvaluationScorer.score(parsed, for: evaluationCase)

    XCTAssertEqual(scores.usdaRouting, .directSearch)
    XCTAssertFalse(scores.behaviorCorrect == true)
  }

  func testEggsRegressionRejectsOneServingSubstitution() {
    let evaluationCase = ParserEvaluationCorpus.cases.first { $0.id == "simple.eggs.written" }!
    let silentlyDefaulted = ParsedFoodRequest(
      productName: "eggs",
      searchTerms: "eggs",
      quantity: 1,
      unit: "serving",
      preparation: "scrambled",
      descriptors: ["large"]
    )

    let scores = ParserEvaluationScorer.score(silentlyDefaulted, for: evaluationCase)

    XCTAssertFalse(scores.requiredFieldsCorrect == true)
  }

  func testReportKeepsColdAndPrewarmedSummariesSeparate() {
    let observations = ParserEvaluationWarmState.allCases.flatMap { warmState in
      FoundationModelsPromptProfile.allCases.map { profile in
        ParserEvaluationObservation(
          corpusVersion: ParserEvaluationCorpus.version,
          promptProfile: profile.rawValue,
          modelUseCase: "general",
          reasoningPolicy: FoundationModelsReasoningPolicy.capabilityAwareLight.rawValue,
          warmState: warmState.rawValue,
          caseID: "report-probe",
          category: .simpleFood,
          run: 1,
          outcome: "parsed",
          errorKind: nil,
          latencyMilliseconds: warmState == .cold ? 20 : 10,
          sourceGrounded: true,
          requiredFieldsCorrect: true,
          unsupportedInventedFacts: false,
          behaviorCorrect: true,
          usdaRouting: "directSearch",
          stableWithFirstRun: true,
          inputTokenCount: nil,
          outputTokenCount: nil,
          reasoningTokenCount: nil,
          humanReviewRequired: false,
          input: nil,
          candidate: ParserEvaluationCandidate.baseline22Field.rawValue,
          expectedRoute: FoodInterpretationRoute.deterministicSearch.rawValue,
          routeCorrect: nil,
          interpretationRoute: nil,
          routeReasons: [],
          modelInvoked: true,
          deterministicFastPathUsed: nil,
          deterministicFastPathFamily: nil
        )
      }
    }

    let report = ParserEvaluationReport.make(observations: observations, repeats: 1)

    XCTAssertEqual(report.warmStates, ["cold", "prewarmed"])
    XCTAssertEqual(report.reasoningPolicies, ["capabilityAwareLight"])
    XCTAssertEqual(report.summaries.count, 4)
    XCTAssertEqual(
      Set(report.summaries.map { "\($0.promptProfile)|\($0.warmState)" }),
      Set([
        "production|cold", "production|prewarmed", "leanCandidate|cold", "leanCandidate|prewarmed",
      ])
    )
  }

  func testReportKeepsReasoningPolicyConfigurationsSeparate() throws {
    let enabled = promotionObservation(
      candidate: .baseline22Field,
      profile: FoundationModelsPromptProfile.production.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      reasoningPolicy: .capabilityAwareLight
    )
    let disabled = promotionObservation(
      candidate: .baseline22Field,
      profile: FoundationModelsPromptProfile.production.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      reasoningPolicy: .disabled
    )

    let report = ParserEvaluationReport.make(observations: [enabled, disabled], repeats: 1)

    XCTAssertEqual(report.reasoningPolicies, ["capabilityAwareLight", "disabled"])
    XCTAssertEqual(report.summaries.count, 2)
    XCTAssertEqual(Set(report.summaries.map(\.reasoningPolicy)), Set(report.reasoningPolicies))
  }

  func testHybridPromotionGateRejectsUnsafePerCaseDisagreement() {
    let baseline = promotionObservation(
      candidate: .baseline22Field,
      profile: FoundationModelsPromptProfile.production.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true
    )
    let hybrid = promotionObservation(
      candidate: .hybrid,
      profile: FoundationModelsSemanticPromptProfile.minimal.rawValue,
      sourceGrounded: true,
      behaviorCorrect: false
    )

    let report = ParserEvaluationReport.make(observations: [baseline, hybrid], repeats: 1)

    XCTAssertEqual(report.unsafeHybridDisagreementCount, 1)
    XCTAssertFalse(report.hybridCandidateEligible)
  }

  func testHybridPromotionGateRejectsTypedRouteMismatchEvenWhenBothRoutesAreBlocked() {
    let baseline = promotionObservation(
      candidate: .baseline22Field,
      profile: FoundationModelsPromptProfile.production.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true
    )
    let hybrid = promotionObservation(
      candidate: .hybrid,
      profile: FoundationModelsSemanticPromptProfile.minimal.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      routeCorrect: false
    )

    let report = ParserEvaluationReport.make(observations: [baseline, hybrid], repeats: 1)

    XCTAssertEqual(report.unsafeHybridDisagreementCount, 1)
    XCTAssertFalse(report.hybridCandidateEligible)
    XCTAssertEqual(
      report.summaries.first(where: { $0.candidate == ParserEvaluationCandidate.hybrid.rawValue })?
        .routeAccuracy,
      0
    )
  }

  func testDeterministicFirstSummaryReportsFastPathAndModelInvocationRates() throws {
    let fastPath = promotionObservation(
      candidate: .deterministicFirst,
      profile: FoundationModelsPromptProfile.production.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      deterministicFastPathUsed: true,
      modelInvoked: false
    )
    let fallback = promotionObservation(
      candidate: .deterministicFirst,
      profile: FoundationModelsPromptProfile.production.rawValue,
      sourceGrounded: true,
      behaviorCorrect: true,
      deterministicFastPathUsed: false,
      modelInvoked: true
    )

    let report = ParserEvaluationReport.make(observations: [fastPath, fallback], repeats: 1)
    let summary = try XCTUnwrap(report.summaries.first)

    XCTAssertEqual(summary.deterministicFastPathRate, 0.5)
    XCTAssertEqual(summary.modelInvocationRate, 0.5)
    XCTAssertEqual(summary.routeAccuracy, 1)
  }

  private func promotionObservation(
    candidate: ParserEvaluationCandidate,
    profile: String,
    sourceGrounded: Bool,
    behaviorCorrect: Bool,
    reasoningPolicy: FoundationModelsReasoningPolicy = .capabilityAwareLight,
    run: Int = 1,
    deterministicFastPathUsed: Bool? = nil,
    modelInvoked: Bool? = nil,
    routeCorrect: Bool? = nil,
    inputTokenCount: Int? = nil,
    cachedInputTokenCount: Int? = nil,
    outputTokenCount: Int? = nil,
    reasoningTokenCount: Int? = nil,
    totalTokenCount: Int? = nil,
    prewarmLatencyMilliseconds: Double? = nil,
    sessionAcquisitionLatencyMilliseconds: Double? = nil,
    responseLatencyMilliseconds: Double? = nil,
    deterministicExtractionLatencyMilliseconds: Double? = nil,
    routeDecisionLatencyMilliseconds: Double? = nil,
    groundingAndMergeLatencyMilliseconds: Double? = nil
  ) -> ParserEvaluationObservation {
    ParserEvaluationObservation(
      corpusVersion: ParserEvaluationCorpus.version,
      promptProfile: profile,
      modelUseCase: FoundationModelsModelUseCase.general.rawValue,
      reasoningPolicy: reasoningPolicy.rawValue,
      warmState: ParserEvaluationWarmState.prewarmed.rawValue,
      caseID: "promotion-probe",
      category: .simpleFood,
      run: run,
      outcome: "parsed",
      errorKind: nil,
      latencyMilliseconds: 10,
      sourceGrounded: sourceGrounded,
      requiredFieldsCorrect: true,
      unsupportedInventedFacts: false,
      behaviorCorrect: behaviorCorrect,
      usdaRouting: "directSearch",
      stableWithFirstRun: true,
      inputTokenCount: inputTokenCount,
      cachedInputTokenCount: cachedInputTokenCount,
      outputTokenCount: outputTokenCount,
      reasoningTokenCount: reasoningTokenCount,
      totalTokenCount: totalTokenCount,
      prewarmLatencyMilliseconds: prewarmLatencyMilliseconds,
      sessionAcquisitionLatencyMilliseconds: sessionAcquisitionLatencyMilliseconds,
      responseLatencyMilliseconds: responseLatencyMilliseconds,
      deterministicExtractionLatencyMilliseconds: deterministicExtractionLatencyMilliseconds,
      routeDecisionLatencyMilliseconds: routeDecisionLatencyMilliseconds,
      groundingAndMergeLatencyMilliseconds: groundingAndMergeLatencyMilliseconds,
      humanReviewRequired: false,
      input: nil,
      candidate: candidate.rawValue,
      expectedRoute: FoodInterpretationRoute.deterministicSearch.rawValue,
      routeCorrect: candidate == .baseline22Field ? nil : (routeCorrect ?? true),
      interpretationRoute: nil,
      routeReasons: [],
      modelInvoked: modelInvoked ?? (candidate == .hybrid),
      deterministicFastPathUsed: deterministicFastPathUsed,
      deterministicFastPathFamily: deterministicFastPathUsed == true ? "countedItem" : nil
    )
  }

}

private enum ParserEvaluationWarmState: String, CaseIterable, Sendable {
  case cold
  case prewarmed
}

private enum ParserEvaluationCandidate: String, CaseIterable, Sendable {
  case baseline22Field
  case deterministicFirst
  case hybrid
}

private actor ModelInvocationTrackingFoodParser: FoodDescriptionParsing {
  private let wrapped: any FoodDescriptionParsing
  private(set) var invocationCount = 0

  init(wrapped: any FoodDescriptionParsing) {
    self.wrapped = wrapped
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    invocationCount += 1
    return try await wrapped.parse(input)
  }

  func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    invocationCount += 1
    return try await wrapped.parse(
      semanticContext: semanticContext,
      groundingText: groundingText
    )
  }
}

private actor EvaluationFallbackSpy: FoodDescriptionParsing {
  struct Call: Sendable, Equatable {
    let semanticContext: String
    let groundingText: String
  }

  private let response: ParsedFoodRequest
  private(set) var calls: [Call] = []

  init(response: ParsedFoodRequest) {
    self.response = response
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    calls.append(.init(semanticContext: input, groundingText: input))
    return response
  }

  func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    calls.append(.init(semanticContext: semanticContext, groundingText: groundingText))
    return response
  }
}

final class OnDeviceParserEvaluationTests: XCTestCase {
  private let environment = ProcessInfo.processInfo.environment

  func testWarmStateConfigurationDefaultsColdAndSupportsExplicitComparison() throws {
    XCTAssertEqual(try Self.warmStates(from: nil), [.cold])
    XCTAssertEqual(try Self.warmStates(from: "cold,prewarmed"), [.cold, .prewarmed])
    XCTAssertThrowsError(try Self.warmStates(from: "warm"))
  }

  func testCandidateConfigurationDefaultsBaselineAndSupportsAllComparisons() throws {
    XCTAssertEqual(try Self.candidates(from: nil), [.baseline22Field])
    XCTAssertEqual(
      try Self.candidates(from: "baseline22Field,deterministicFirst,hybrid"),
      [.baseline22Field, .deterministicFirst, .hybrid]
    )
    XCTAssertEqual(try Self.candidates(from: "deterministicFirst"), [.deterministicFirst])
    XCTAssertThrowsError(try Self.candidates(from: "both"))
  }

  func testReasoningPolicyConfigurationDefaultsToProductionAndSupportsEvaluationComparison()
    throws
  {
    XCTAssertEqual(try Self.reasoningPolicies(from: nil), [.capabilityAwareLight])
    XCTAssertEqual(
      try Self.reasoningPolicies(from: "capabilityAwareLight,disabled"),
      [.capabilityAwareLight, .disabled]
    )
    XCTAssertThrowsError(try Self.reasoningPolicies(from: "heavy"))
  }

  func testFocusedCaseSelectionSupportsIDsFamiliesAndStableSeededOrder() throws {
    let byID = try Self.evaluationCases(
      caseIDs: "simple.apple.article,nonfood.weather",
      families: nil,
      orderSeed: "42"
    )
    XCTAssertEqual(Set(byID.map(\.id)), ["simple.apple.article", "nonfood.weather"])

    let byFamily = try Self.evaluationCases(
      caseIDs: nil,
      families: "promptInjection",
      orderSeed: "42"
    )
    XCTAssertFalse(byFamily.isEmpty)
    XCTAssertTrue(byFamily.allSatisfy { $0.category == .promptInjection })

    let first = try Self.evaluationCases(caseIDs: nil, families: nil, orderSeed: "123")
    let second = try Self.evaluationCases(caseIDs: nil, families: nil, orderSeed: "123")
    let changed = try Self.evaluationCases(caseIDs: nil, families: nil, orderSeed: "124")
    XCTAssertEqual(first.map(\.id), second.map(\.id))
    XCTAssertNotEqual(first.map(\.id), changed.map(\.id))
  }

  func testFocusedCaseSelectionRejectsUnknownValuesAndEmptyResolution() {
    XCTAssertThrowsError(
      try Self.evaluationCases(caseIDs: "missing.case", families: nil, orderSeed: "1")
    )
    XCTAssertThrowsError(
      try Self.evaluationCases(caseIDs: nil, families: "missingFamily", orderSeed: "1")
    )
    XCTAssertThrowsError(
      try Self.evaluationCases(caseIDs: nil, families: nil, orderSeed: "not-a-number")
    )
  }

  /// Cheap physical-device probe for the generated `.xctestrun` launch-environment boundary.
  /// This deliberately does not create a Foundation Models session or evaluate the corpus.
  func testParserEvaluationLaunchConfigurationProbe() throws {
    // The normal app scheme may discover this operational probe in broad unit-test runs. Only the
    // dedicated physical evaluation scheme requires the marker; an explicitly selected probe in
    // that scheme must fail rather than silently passing when launch propagation is broken.
    guard environment["XCODE_SCHEME_NAME"] == "JustLogItParserEvaluation" else { return }
    XCTAssertEqual(environment["PARSER_EVAL_CONFIGURATION_PROBE"], "1")
    guard environment["PARSER_EVAL_CONFIGURATION_PROBE"] == "1" else { return }

    XCTAssertEqual(environment["RUN_ON_DEVICE_PARSER_EVAL"], "1")
    let repeats = try XCTUnwrap(Int(environment["PARSER_EVAL_REPEATS"] ?? ""))
    XCTAssertTrue((2...5).contains(repeats))
    XCTAssertNoThrow(try Self.modelUseCases(from: environment["PARSER_EVAL_MODEL_USE_CASES"]))
    XCTAssertNoThrow(
      try Self.reasoningPolicies(from: environment["PARSER_EVAL_REASONING_POLICIES"])
    )
    XCTAssertNoThrow(try Self.warmStates(from: environment["PARSER_EVAL_WARM_STATES"]))
    XCTAssertNoThrow(try Self.candidates(from: environment["PARSER_EVAL_CANDIDATES"]))
    XCTAssertNoThrow(
      try Self.evaluationCases(
        caseIDs: environment["PARSER_EVAL_CASE_IDS"],
        families: environment["PARSER_EVAL_FAMILIES"],
        orderSeed: environment["PARSER_EVAL_ORDER_SEED"]
      )
    )
    XCTAssertTrue(["0", "1"].contains(environment["PARSER_EVAL_INCLUDE_INPUT"] ?? ""))
  }

  func testDeterministicFirstCandidateUsesProductionFastPathWithoutInvokingModel() async throws {
    let fallback = EvaluationFallbackSpy(
      response: ParsedFoodRequest(productName: "unexpected", searchTerms: "unexpected"))
    let trackedFallback = ModelInvocationTrackingFoodParser(wrapped: fallback)
    let parser = DeterministicFirstFoodParser(fallback: trackedFallback)

    let result = try await parser.interpret(
      semanticContext: "assistant text that must not become evidence",
      groundingText: "2 apples"
    )

    XCTAssertTrue(result.usedDeterministicFastPath)
    XCTAssertEqual(result.promotedFamily, .countedItem)
    XCTAssertEqual(result.request.productName, "apples")
    XCTAssertEqual(result.request.quantity, 2)
    let invocationCount = await trackedFallback.invocationCount
    let calls = await fallback.calls
    XCTAssertEqual(invocationCount, 0)
    XCTAssertEqual(calls, [])
  }

  func testDeterministicFirstCandidateFallsBackExactlyOnceAndPreservesContextBoundary()
    async throws
  {
    let expected = ParsedFoodRequest(
      productName: "eggs and toast",
      searchTerms: "eggs and toast",
      containsMultipleFoods: true,
      componentNames: ["eggs", "toast"]
    )
    let fallback = EvaluationFallbackSpy(response: expected)
    let trackedFallback = ModelInvocationTrackingFoodParser(wrapped: fallback)
    let parser = DeterministicFirstFoodParser(fallback: trackedFallback)
    let semanticContext =
      "PRIOR USER FACTS:\nI ate breakfast\n\nCURRENT USER FACTS:\neggs and toast"

    let result = try await parser.interpret(
      semanticContext: semanticContext,
      groundingText: "eggs and toast"
    )

    XCTAssertFalse(result.usedDeterministicFastPath)
    XCTAssertNil(result.promotedFamily)
    XCTAssertEqual(result.request, expected)
    let invocationCount = await trackedFallback.invocationCount
    let calls = await fallback.calls
    XCTAssertEqual(invocationCount, 1)
    XCTAssertEqual(
      calls,
      [.init(semanticContext: semanticContext, groundingText: "eggs and toast")]
    )
  }

  func testHybridSemanticContextIncludesPreludeButKeepsCurrentInputDistinct() {
    let evaluationCase = ParserEvaluationCase(
      id: "context.probe",
      category: .contextChange,
      input: "the other half",
      prelude: "I ate a burrito",
      productTokens: ["burrito"],
      brand: .ignore,
      amount: .ignore,
      disposition: .humanReview
    )

    XCTAssertEqual(
      Self.semanticContext(for: evaluationCase),
      "PRIOR USER FACTS:\nI ate a burrito\n\nCURRENT USER FACTS:\nthe other half"
    )
  }

  func testConfiguredCandidatesOnDevice() async throws {
    guard environment["RUN_ON_DEVICE_PARSER_EVAL"] == "1" else {
      throw XCTSkip("Set RUN_ON_DEVICE_PARSER_EVAL=1 for the manual on-device parser evaluation.")
    }
    let repeats = min(max(Int(environment["PARSER_EVAL_REPEATS"] ?? "2") ?? 2, 2), 5)
    let includeInput = environment["PARSER_EVAL_INCLUDE_INPUT"] == "1"
    let modelUseCases = try Self.modelUseCases(from: environment["PARSER_EVAL_MODEL_USE_CASES"])
    let reasoningPolicies = try Self.reasoningPolicies(
      from: environment["PARSER_EVAL_REASONING_POLICIES"])
    let warmStates = try Self.warmStates(from: environment["PARSER_EVAL_WARM_STATES"])
    let candidates = try Self.candidates(from: environment["PARSER_EVAL_CANDIDATES"])
    let evaluationCases = try Self.evaluationCases(
      caseIDs: environment["PARSER_EVAL_CASE_IDS"],
      families: environment["PARSER_EVAL_FAMILIES"],
      orderSeed: environment["PARSER_EVAL_ORDER_SEED"]
    )
    for useCase in modelUseCases {
      guard
        case .available = SystemLanguageModel(useCase: useCase.systemUseCase).availability
      else {
        throw XCTSkip(
          "The \(useCase.rawValue) Foundation Models use case is unavailable on this destination."
        )
      }
    }
    var observations: [ParserEvaluationObservation] = []

    for candidate in candidates {
      for modelUseCase in modelUseCases {
        for reasoningPolicy in reasoningPolicies {
          let profiles: [String] =
            switch candidate {
            case .baseline22Field: FoundationModelsPromptProfile.allCases.map(\.rawValue)
            case .deterministicFirst: [FoundationModelsPromptProfile.production.rawValue]
            case .hybrid: [FoundationModelsSemanticPromptProfile.minimal.rawValue]
            }
          for profileName in profiles {
            for warmState in warmStates {
              let evaluationMetricsRecorder = FoundationModelsEvaluationMetricsRecorder()
              let baselineParser =
                candidate != .hybrid
                ? FoundationModelsFoodParser(
                  promptProfile: FoundationModelsPromptProfile(rawValue: profileName)!,
                  modelUseCase: modelUseCase,
                  reasoningPolicy: reasoningPolicy,
                  evaluationMetricsRecorder: evaluationMetricsRecorder
                ) : nil
              let trackedFallback =
                baselineParser.map { baselineParser in
                  candidate == .deterministicFirst
                    ? ModelInvocationTrackingFoodParser(wrapped: baselineParser) : nil
                } ?? nil
              let deterministicParser = trackedFallback.map {
                DeterministicFirstFoodParser(fallback: $0)
              }
              let semanticProposer =
                candidate == .hybrid
                ? FoundationModelsSemanticFoodProposer(
                  modelUseCase: modelUseCase,
                  reasoningPolicy: reasoningPolicy,
                  evaluationMetricsRecorder: evaluationMetricsRecorder
                ) : nil
              let hybridParser = semanticProposer.map { HybridFoodInterpreter(proposer: $0) }
              for evaluationCase in evaluationCases {
                var firstResult: ParsedFoodRequest?
                for run in 1...repeats {
                  if candidate == .baseline22Field, let prelude = evaluationCase.prelude {
                    _ = try? await baselineParser?.parse(prelude)
                  }
                  if warmState == .prewarmed {
                    if let baselineParser { await baselineParser.prewarm() }
                    if let semanticProposer { await semanticProposer.prewarm() }
                  }
                  let fallbackInvocationsBefore =
                    if let trackedFallback {
                      await trackedFallback.invocationCount
                    } else {
                      0
                    }
                  let started = ContinuousClock.now
                  do {
                    let parsed: ParsedFoodRequest
                    let route: String?
                    let routeReasons: [String]
                    let modelInvoked: Bool
                    let deterministicFastPathUsed: Bool?
                    let deterministicFastPathFamily: String?
                    let phaseDurations: FoodInterpretationPhaseDurations?
                    if let hybridParser {
                      let result = try await hybridParser.interpret(
                        semanticContext: Self.semanticContext(for: evaluationCase),
                        groundingText: evaluationCase.input
                      )
                      parsed = result.request
                      route = result.finalDecision.route.rawValue
                      routeReasons = result.finalDecision.reasons.map { $0.rawValue }
                      modelInvoked = result.modelInvoked
                      deterministicFastPathUsed = nil
                      deterministicFastPathFamily = nil
                      phaseDurations = result.phaseDurations
                    } else if let deterministicParser, let trackedFallback {
                      let result = try await deterministicParser.interpret(
                        semanticContext: Self.semanticContext(for: evaluationCase),
                        groundingText: evaluationCase.input
                      )
                      parsed = result.request
                      route = Self.terminalRoute(for: result).rawValue
                      routeReasons = result.routingDecision.reasons.map { $0.rawValue }
                      modelInvoked =
                        await trackedFallback.invocationCount > fallbackInvocationsBefore
                      deterministicFastPathUsed = result.usedDeterministicFastPath
                      deterministicFastPathFamily = result.promotedFamily?.rawValue
                      phaseDurations = result.phaseDurations
                    } else {
                      parsed = try await baselineParser!.parse(evaluationCase.input)
                      route = nil
                      routeReasons = []
                      modelInvoked = true
                      deterministicFastPathUsed = nil
                      deterministicFastPathFamily = nil
                      phaseDurations = nil
                    }
                    let modelMetrics = await evaluationMetricsRecorder.takeCompletedInvocation()
                    let elapsed = started.duration(to: .now)
                    let scores = ParserEvaluationScorer.score(parsed, for: evaluationCase)
                    let stable = firstResult.map { $0 == parsed }
                    if firstResult == nil { firstResult = parsed }
                    let observation = ParserEvaluationObservation(
                      corpusVersion: ParserEvaluationCorpus.version,
                      promptProfile: profileName,
                      modelUseCase: modelUseCase.rawValue,
                      reasoningPolicy: reasoningPolicy.rawValue,
                      warmState: warmState.rawValue,
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
                      usdaRouting: scores.usdaRouting.rawValue,
                      stableWithFirstRun: stable,
                      inputTokenCount: modelMetrics?.inputTokenCount,
                      cachedInputTokenCount: modelMetrics?.cachedInputTokenCount,
                      outputTokenCount: modelMetrics?.outputTokenCount,
                      reasoningTokenCount: modelMetrics?.reasoningTokenCount,
                      totalTokenCount: modelMetrics?.totalTokenCount,
                      prewarmLatencyMilliseconds: modelMetrics?.prewarmLatencyMilliseconds,
                      sessionAcquisitionLatencyMilliseconds:
                        modelMetrics?.sessionAcquisitionLatencyMilliseconds,
                      responseLatencyMilliseconds: modelMetrics?.responseLatencyMilliseconds,
                      mappingLatencyMilliseconds: modelMetrics?.mappingLatencyMilliseconds,
                      deterministicExtractionLatencyMilliseconds:
                        phaseDurations?.deterministicExtraction.milliseconds,
                      routeDecisionLatencyMilliseconds:
                        phaseDurations?.routeDecision.milliseconds,
                      groundingAndMergeLatencyMilliseconds:
                        phaseDurations?.semanticGroundingAndMerge?.milliseconds,
                      humanReviewRequired: evaluationCase.disposition == .humanReview,
                      input: includeInput ? evaluationCase.input : nil,
                      candidate: candidate.rawValue,
                      expectedRoute: evaluationCase.expectedRoute.rawValue,
                      routeCorrect: route.flatMap(FoodInterpretationRoute.init(rawValue:)).map {
                        ParserEvaluationScorer.routeCorrect($0, for: evaluationCase)
                      },
                      interpretationRoute: route,
                      routeReasons: routeReasons,
                      modelInvoked: modelInvoked,
                      deterministicFastPathUsed: deterministicFastPathUsed,
                      deterministicFastPathFamily: deterministicFastPathFamily
                    )
                    observations.append(observation)
                  } catch {
                    let modelMetrics = await evaluationMetricsRecorder.takeCompletedInvocation()
                    let elapsed = started.duration(to: .now)
                    let modelInvoked: Bool =
                      if let trackedFallback {
                        await trackedFallback.invocationCount > fallbackInvocationsBefore
                      } else {
                        candidate == .baseline22Field
                      }
                    let observation = ParserEvaluationObservation(
                      corpusVersion: ParserEvaluationCorpus.version,
                      promptProfile: profileName,
                      modelUseCase: modelUseCase.rawValue,
                      reasoningPolicy: reasoningPolicy.rawValue,
                      warmState: warmState.rawValue,
                      caseID: evaluationCase.id,
                      category: evaluationCase.category,
                      run: run,
                      outcome: "error",
                      errorKind: Self.errorKind(error),
                      latencyMilliseconds: elapsed.milliseconds,
                      sourceGrounded: nil,
                      requiredFieldsCorrect: nil,
                      unsupportedInventedFacts: false,
                      behaviorCorrect: ParserEvaluationScorer.errorBehaviorCorrect(
                        for: evaluationCase),
                      usdaRouting: "blockedByParserError",
                      stableWithFirstRun: nil,
                      inputTokenCount: modelMetrics?.inputTokenCount,
                      cachedInputTokenCount: modelMetrics?.cachedInputTokenCount,
                      outputTokenCount: modelMetrics?.outputTokenCount,
                      reasoningTokenCount: modelMetrics?.reasoningTokenCount,
                      totalTokenCount: modelMetrics?.totalTokenCount,
                      prewarmLatencyMilliseconds: modelMetrics?.prewarmLatencyMilliseconds,
                      sessionAcquisitionLatencyMilliseconds:
                        modelMetrics?.sessionAcquisitionLatencyMilliseconds,
                      responseLatencyMilliseconds: modelMetrics?.responseLatencyMilliseconds,
                      mappingLatencyMilliseconds: modelMetrics?.mappingLatencyMilliseconds,
                      deterministicExtractionLatencyMilliseconds: nil,
                      routeDecisionLatencyMilliseconds: nil,
                      groundingAndMergeLatencyMilliseconds: nil,
                      humanReviewRequired: evaluationCase.disposition == .humanReview,
                      input: includeInput ? evaluationCase.input : nil,
                      candidate: candidate.rawValue,
                      expectedRoute: evaluationCase.expectedRoute.rawValue,
                      routeCorrect: candidate == .baseline22Field
                        ? nil
                        : ParserEvaluationScorer.routeCorrect(
                          .manualSearch,
                          for: evaluationCase
                        ),
                      interpretationRoute: candidate == .baseline22Field
                        ? nil : FoodInterpretationRoute.manualSearch.rawValue,
                      routeReasons: [],
                      modelInvoked: modelInvoked,
                      deterministicFastPathUsed:
                        candidate == .deterministicFirst && modelInvoked ? false : nil,
                      deterministicFastPathFamily: nil
                    )
                    observations.append(observation)
                  }
                }
              }
            }
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

    if candidates.contains(.baseline22Field) {
      guard
        let production = report.summaries.first(where: {
          $0.candidate == ParserEvaluationCandidate.baseline22Field.rawValue
            && $0.promptProfile == "production" && $0.modelUseCase == "general"
            && $0.reasoningPolicy
              == FoundationModelsReasoningPolicy.capabilityAwareLight.rawValue
            && $0.warmState
              == (warmStates.contains(.prewarmed) ? "prewarmed" : warmStates[0].rawValue)
        })
          ?? report.summaries.first(where: {
            $0.candidate == ParserEvaluationCandidate.baseline22Field.rawValue
              && $0.promptProfile == "production"
              && $0.reasoningPolicy
                == FoundationModelsReasoningPolicy.capabilityAwareLight.rawValue
          })
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
  }

  private static func errorKind(_ error: any Error) -> String {
    guard let parserError = error as? FoodParserError else { return "other" }
    return switch parserError {
    case .emptyInput: "empty_input"
    case .invalidResponse: "invalid_response"
    case .unavailable: "unavailable"
    }
  }

  private static func semanticContext(for evaluationCase: ParserEvaluationCase) -> String {
    guard let prelude = evaluationCase.prelude?.trimmingCharacters(in: .whitespacesAndNewlines),
      !prelude.isEmpty
    else { return evaluationCase.input }
    return """
      PRIOR USER FACTS:
      \(prelude)

      CURRENT USER FACTS:
      \(evaluationCase.input)
      """
  }

  private static func terminalRoute(
    for result: DeterministicFirstFoodParsingResult
  ) -> FoodInterpretationRoute {
    if result.usedDeterministicFastPath { return .deterministicSearch }
    if result.request.containsMultipleFoods, result.request.componentNames.count >= 2 {
      return .composite
    }
    if result.request.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || result.request.clarificationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty == false
    {
      return .clarification
    }
    return .onDeviceSemantic
  }

  private static func modelUseCases(
    from environmentValue: String?
  ) throws -> [FoundationModelsModelUseCase] {
    let rawValues = (environmentValue ?? "general")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let parsed = rawValues.compactMap(FoundationModelsModelUseCase.init(rawValue:))
    guard !parsed.isEmpty, parsed.count == rawValues.count else {
      throw NSError(
        domain: "ParserEvaluationConfiguration",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "PARSER_EVAL_MODEL_USE_CASES must contain general and/or contentTagging."
        ]
      )
    }
    return parsed
  }

  private static func reasoningPolicies(
    from environmentValue: String?
  ) throws -> [FoundationModelsReasoningPolicy] {
    let rawValues =
      (environmentValue ?? FoundationModelsReasoningPolicy.capabilityAwareLight.rawValue)
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let parsed = rawValues.compactMap(FoundationModelsReasoningPolicy.init(rawValue:))
    guard !parsed.isEmpty, parsed.count == rawValues.count else {
      throw configurationError(
        8,
        "PARSER_EVAL_REASONING_POLICIES must contain capabilityAwareLight and/or disabled."
      )
    }
    return parsed
  }

  private static func warmStates(
    from environmentValue: String?
  ) throws -> [ParserEvaluationWarmState] {
    let rawValues = (environmentValue ?? "cold")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let parsed = rawValues.compactMap(ParserEvaluationWarmState.init(rawValue:))
    guard !parsed.isEmpty, parsed.count == rawValues.count else {
      throw NSError(
        domain: "ParserEvaluationConfiguration",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "PARSER_EVAL_WARM_STATES must contain cold and/or prewarmed."
        ]
      )
    }
    return parsed
  }

  private static func candidates(
    from environmentValue: String?
  ) throws -> [ParserEvaluationCandidate] {
    let rawValues = (environmentValue ?? ParserEvaluationCandidate.baseline22Field.rawValue)
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let parsed = rawValues.compactMap(ParserEvaluationCandidate.init(rawValue:))
    guard !parsed.isEmpty, parsed.count == rawValues.count else {
      throw NSError(
        domain: "ParserEvaluationConfiguration",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey:
            "PARSER_EVAL_CANDIDATES must contain baseline22Field, deterministicFirst, and/or hybrid."
        ]
      )
    }
    return parsed
  }

  private static func evaluationCases(
    caseIDs: String?,
    families: String?,
    orderSeed: String?
  ) throws -> [ParserEvaluationCase] {
    let requestedIDs = csvValues(caseIDs)
    let requestedFamilies = csvValues(families)
    let knownIDs = Set(ParserEvaluationCorpus.cases.map(\.id))
    let knownFamilies = Set(ParserEvaluationCategory.allCases.map(\.rawValue))
    guard requestedIDs.allSatisfy(knownIDs.contains) else {
      throw configurationError(4, "PARSER_EVAL_CASE_IDS contains an unknown case identifier.")
    }
    guard requestedFamilies.allSatisfy(knownFamilies.contains) else {
      throw configurationError(5, "PARSER_EVAL_FAMILIES contains an unknown category.")
    }
    let selected = ParserEvaluationCorpus.cases.filter { evaluationCase in
      (requestedIDs.isEmpty && requestedFamilies.isEmpty)
        || requestedIDs.contains(evaluationCase.id)
        || requestedFamilies.contains(evaluationCase.category.rawValue)
    }
    guard !selected.isEmpty else {
      throw configurationError(6, "The parser evaluation filters selected no cases.")
    }
    let seedText = orderSeed ?? "0"
    guard let seed = UInt64(seedText) else {
      throw configurationError(7, "PARSER_EVAL_ORDER_SEED must be an unsigned integer.")
    }
    return selected.sorted {
      let left = seededOrderKey(seed: seed, value: $0.id)
      let right = seededOrderKey(seed: seed, value: $1.id)
      return left == right ? $0.id < $1.id : left < right
    }
  }

  private static func csvValues(_ value: String?) -> Set<String> {
    Set(
      (value ?? "").split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
  }

  private static func seededOrderKey(seed: UInt64, value: String) -> UInt64 {
    var hash = 1_469_598_103_934_665_603 ^ seed
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return hash
  }

  private static func configurationError(_ code: Int, _ description: String) -> NSError {
    NSError(
      domain: "ParserEvaluationConfiguration",
      code: code,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
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
  enum USDARouting: String, Codable {
    case directSearch
    case compositeHandoff
    case blocked
  }

  struct Scores {
    let sourceGrounded: Bool
    let requiredFieldsCorrect: Bool?
    let unsupportedInventedFacts: Bool
    let behaviorCorrect: Bool?
    let usdaRouting: USDARouting
  }

  static func score(_ parsed: ParsedFoodRequest, for evaluationCase: ParserEvaluationCase) -> Scores
  {
    let regrounded = ParsedFoodRequestGrounder().ground(parsed, in: evaluationCase.input)
    let routing = usdaRouting(for: parsed, sourceText: evaluationCase.input)
    let hasIdentity = !parsed.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasClarification =
      parsed.clarificationPrompt?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty == false
    let hasComposite = parsed.containsMultipleFoods && parsed.componentNames.count >= 2
    let structurallyUsable = hasIdentity || hasClarification || hasComposite
    let sourceGrounded = regrounded == parsed && structurallyUsable
    return Scores(
      sourceGrounded: sourceGrounded,
      requiredFieldsCorrect: requiredFieldsCorrect(parsed, for: evaluationCase),
      unsupportedInventedFacts: regrounded != parsed,
      behaviorCorrect: parsedBehaviorCorrect(routing, for: evaluationCase),
      usdaRouting: routing
    )
  }

  static func errorBehaviorCorrect(for evaluationCase: ParserEvaluationCase) -> Bool? {
    switch evaluationCase.disposition {
    case .reject, .clarifyOrReject, .multipleOrReject: true
    case .accept, .clarify: false
    case .humanReview: nil
    }
  }

  static func routeCorrect(
    _ actualRoute: FoodInterpretationRoute,
    for evaluationCase: ParserEvaluationCase
  ) -> Bool {
    actualRoute == evaluationCase.expectedRoute
  }

  private static func requiredFieldsCorrect(
    _ parsed: ParsedFoodRequest,
    for evaluationCase: ParserEvaluationCase
  ) -> Bool? {
    switch evaluationCase.disposition {
    case .humanReview, .reject, .multipleOrReject:
      return nil
    case .accept, .clarify, .clarifyOrReject:
      break
    }
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
    _ routing: USDARouting,
    for evaluationCase: ParserEvaluationCase
  ) -> Bool? {
    switch evaluationCase.disposition {
    case .accept:
      routing == .directSearch
    case .clarify, .clarifyOrReject, .reject:
      routing == .blocked
    case .multipleOrReject:
      routing == .compositeHandoff || routing == .blocked
    case .humanReview: nil
    }
  }

  private static func usdaRouting(
    for parsed: ParsedFoodRequest,
    sourceText: String
  ) -> USDARouting {
    let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: sourceText)
    switch ClarificationPolicy().decide(draft) {
    case .proceed:
      return .directSearch
    case .beginComposite:
      return .compositeHandoff
    case .clarify, .requireEdit, .fallbackManual:
      return .blocked
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
  let modelUseCase: String
  let reasoningPolicy: String
  let warmState: String
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
  let usdaRouting: String
  let stableWithFirstRun: Bool?
  let inputTokenCount: Int?
  let cachedInputTokenCount: Int?
  let outputTokenCount: Int?
  let reasoningTokenCount: Int?
  let totalTokenCount: Int?
  /// Observable intervals only. These must never be relabeled as model load or TTFT.
  let prewarmLatencyMilliseconds: Double?
  let sessionAcquisitionLatencyMilliseconds: Double?
  let responseLatencyMilliseconds: Double?
  let mappingLatencyMilliseconds: Double?
  let deterministicExtractionLatencyMilliseconds: Double?
  let routeDecisionLatencyMilliseconds: Double?
  let groundingAndMergeLatencyMilliseconds: Double?
  let humanReviewRequired: Bool
  let input: String?
  let candidate: String
  let expectedRoute: String
  let routeCorrect: Bool?
  let interpretationRoute: String?
  let routeReasons: [String]
  let modelInvoked: Bool?
  let deterministicFastPathUsed: Bool?
  let deterministicFastPathFamily: String?

  init(
    corpusVersion: String,
    promptProfile: String,
    modelUseCase: String,
    reasoningPolicy: String,
    warmState: String,
    caseID: String,
    category: ParserEvaluationCategory,
    run: Int,
    outcome: String,
    errorKind: String?,
    latencyMilliseconds: Double,
    sourceGrounded: Bool?,
    requiredFieldsCorrect: Bool?,
    unsupportedInventedFacts: Bool,
    behaviorCorrect: Bool?,
    usdaRouting: String,
    stableWithFirstRun: Bool?,
    inputTokenCount: Int?,
    cachedInputTokenCount: Int? = nil,
    outputTokenCount: Int?,
    reasoningTokenCount: Int?,
    totalTokenCount: Int? = nil,
    prewarmLatencyMilliseconds: Double? = nil,
    sessionAcquisitionLatencyMilliseconds: Double? = nil,
    responseLatencyMilliseconds: Double? = nil,
    mappingLatencyMilliseconds: Double? = nil,
    deterministicExtractionLatencyMilliseconds: Double? = nil,
    routeDecisionLatencyMilliseconds: Double? = nil,
    groundingAndMergeLatencyMilliseconds: Double? = nil,
    humanReviewRequired: Bool,
    input: String?,
    candidate: String,
    expectedRoute: String,
    routeCorrect: Bool?,
    interpretationRoute: String?,
    routeReasons: [String],
    modelInvoked: Bool?,
    deterministicFastPathUsed: Bool?,
    deterministicFastPathFamily: String?
  ) {
    self.corpusVersion = corpusVersion
    self.promptProfile = promptProfile
    self.modelUseCase = modelUseCase
    self.reasoningPolicy = reasoningPolicy
    self.warmState = warmState
    self.caseID = caseID
    self.category = category
    self.run = run
    self.outcome = outcome
    self.errorKind = errorKind
    self.latencyMilliseconds = latencyMilliseconds
    self.sourceGrounded = sourceGrounded
    self.requiredFieldsCorrect = requiredFieldsCorrect
    self.unsupportedInventedFacts = unsupportedInventedFacts
    self.behaviorCorrect = behaviorCorrect
    self.usdaRouting = usdaRouting
    self.stableWithFirstRun = stableWithFirstRun
    self.inputTokenCount = inputTokenCount
    self.cachedInputTokenCount = cachedInputTokenCount
    self.outputTokenCount = outputTokenCount
    self.reasoningTokenCount = reasoningTokenCount
    self.totalTokenCount = totalTokenCount
    self.prewarmLatencyMilliseconds = prewarmLatencyMilliseconds
    self.sessionAcquisitionLatencyMilliseconds = sessionAcquisitionLatencyMilliseconds
    self.responseLatencyMilliseconds = responseLatencyMilliseconds
    self.mappingLatencyMilliseconds = mappingLatencyMilliseconds
    self.deterministicExtractionLatencyMilliseconds =
      deterministicExtractionLatencyMilliseconds
    self.routeDecisionLatencyMilliseconds = routeDecisionLatencyMilliseconds
    self.groundingAndMergeLatencyMilliseconds = groundingAndMergeLatencyMilliseconds
    self.humanReviewRequired = humanReviewRequired
    self.input = input
    self.candidate = candidate
    self.expectedRoute = expectedRoute
    self.routeCorrect = routeCorrect
    self.interpretationRoute = interpretationRoute
    self.routeReasons = routeReasons
    self.modelInvoked = modelInvoked
    self.deterministicFastPathUsed = deterministicFastPathUsed
    self.deterministicFastPathFamily = deterministicFastPathFamily
  }
}

private struct ParserEvaluationSummary: Codable {
  let promptProfile: String
  let modelUseCase: String
  let reasoningPolicy: String
  let warmState: String
  let sourceGroundingRate: Double
  let requiredFieldRate: Double
  let behaviorRate: Double
  let routeAccuracy: Double?
  let stabilityRate: Double
  let unsupportedInventedFactCount: Int
  let p50LatencyMilliseconds: Double
  let p95LatencyMilliseconds: Double
  let averageInputTokenCount: Double?
  let averageCachedInputTokenCount: Double?
  let averageOutputTokenCount: Double?
  let averageReasoningTokenCount: Double?
  let averageTotalTokenCount: Double?
  let p50PrewarmLatencyMilliseconds: Double?
  let p95PrewarmLatencyMilliseconds: Double?
  let p50SessionAcquisitionLatencyMilliseconds: Double?
  let p95SessionAcquisitionLatencyMilliseconds: Double?
  let p50ResponseLatencyMilliseconds: Double?
  let p95ResponseLatencyMilliseconds: Double?
  let averageMappingLatencyMilliseconds: Double?
  let averageDeterministicExtractionLatencyMilliseconds: Double?
  let averageRouteDecisionLatencyMilliseconds: Double?
  let averageGroundingAndMergeLatencyMilliseconds: Double?
  let candidate: String
  let deterministicFastPathRate: Double?
  let modelInvocationRate: Double
}

private struct ParserEvaluationReport: Codable {
  let corpusVersion: String
  let generatedAt: Date
  let destinationOS: String
  let repeats: Int
  let includesInputText: Bool
  let warmStates: [String]
  let reasoningPolicies: [String]
  let summaries: [ParserEvaluationSummary]
  let leanCandidateEligible: Bool
  let hybridCandidateEligible: Bool
  let unsafeHybridDisagreementCount: Int
  let observations: [ParserEvaluationObservation]

  static func make(
    observations: [ParserEvaluationObservation],
    repeats: Int
  ) -> ParserEvaluationReport {
    let configurations = Set(
      observations.map {
        "\($0.candidate)|\($0.modelUseCase)|\($0.promptProfile)|\($0.reasoningPolicy)|\($0.warmState)"
      }
    ).sorted()
    let summaries = configurations.map { configuration in
      let parts = configuration.split(separator: "|", maxSplits: 4).map(String.init)
      let candidate = parts[0]
      let modelUseCase = parts[1]
      let profile = parts[2]
      let reasoningPolicy = parts[3]
      let warmState = parts[4]
      return summarize(
        observations.filter {
          $0.candidate == candidate && $0.promptProfile == profile
            && $0.modelUseCase == modelUseCase && $0.reasoningPolicy == reasoningPolicy
            && $0.warmState == warmState
        },
        profile: profile,
        modelUseCase: modelUseCase,
        reasoningPolicy: reasoningPolicy,
        warmState: warmState,
        candidate: candidate
      )
    }
    let baselineUseCase =
      summaries.contains { $0.modelUseCase == "general" }
      ? "general" : summaries[0].modelUseCase
    let baselineWarmState =
      summaries.contains { $0.warmState == "prewarmed" }
      ? "prewarmed" : summaries[0].warmState
    let baselineReasoningPolicy = FoundationModelsReasoningPolicy.capabilityAwareLight.rawValue
    let production = summaries.first {
      $0.candidate == ParserEvaluationCandidate.baseline22Field.rawValue
        && $0.promptProfile == "production" && $0.modelUseCase == baselineUseCase
        && $0.reasoningPolicy == baselineReasoningPolicy
        && $0.warmState == baselineWarmState
    }
    let lean = summaries.first {
      $0.candidate == ParserEvaluationCandidate.baseline22Field.rawValue
        && $0.promptProfile == "leanCandidate" && $0.modelUseCase == baselineUseCase
        && $0.reasoningPolicy == baselineReasoningPolicy
        && $0.warmState == baselineWarmState
    }
    let leanEligible =
      if let production, let lean {
        lean.sourceGroundingRate == 1
          && lean.unsupportedInventedFactCount == 0
          && lean.requiredFieldRate >= max(0.90, production.requiredFieldRate)
          && lean.behaviorRate >= max(0.85, production.behaviorRate)
          && lean.stabilityRate >= max(0.90, production.stabilityRate - 0.02)
          && lean.p95LatencyMilliseconds <= production.p95LatencyMilliseconds * 1.10
      } else {
        false
      }
    let hybrid = summaries.first {
      $0.candidate == ParserEvaluationCandidate.hybrid.rawValue
        && $0.modelUseCase == baselineUseCase
        && $0.reasoningPolicy == baselineReasoningPolicy && $0.warmState == baselineWarmState
    }
    let unsafeHybridDisagreementCount = unsafeHybridDisagreements(
      in: observations,
      modelUseCase: baselineUseCase,
      reasoningPolicy: baselineReasoningPolicy,
      warmState: baselineWarmState
    )
    let hybridEligible =
      if let production, let hybrid {
        hybrid.sourceGroundingRate == 1
          && hybrid.unsupportedInventedFactCount == 0
          && unsafeHybridDisagreementCount == 0
          && hybrid.routeAccuracy == 1
          && hybrid.requiredFieldRate >= max(0.90, production.requiredFieldRate)
          && hybrid.behaviorRate >= max(0.85, production.behaviorRate)
          && hybrid.stabilityRate >= max(0.90, production.stabilityRate - 0.02)
          && hybrid.p95LatencyMilliseconds <= production.p95LatencyMilliseconds
      } else {
        false
      }
    return ParserEvaluationReport(
      corpusVersion: ParserEvaluationCorpus.version,
      generatedAt: .now,
      destinationOS: ProcessInfo.processInfo.operatingSystemVersionString,
      repeats: repeats,
      includesInputText: observations.contains { $0.input != nil },
      warmStates: Array(Set(observations.map(\.warmState))).sorted(),
      reasoningPolicies: Array(Set(observations.map(\.reasoningPolicy))).sorted(),
      summaries: summaries,
      leanCandidateEligible: leanEligible,
      hybridCandidateEligible: hybridEligible,
      unsafeHybridDisagreementCount: unsafeHybridDisagreementCount,
      observations: observations
    )
  }

  /// A candidate cannot hide a safety regression inside an acceptable aggregate rate.
  /// Compare the same corpus case/run against the production parser and reject promotion when
  /// the baseline was safe but hybrid loses grounding, invents a fact, or takes a wrong route.
  private static func unsafeHybridDisagreements(
    in observations: [ParserEvaluationObservation],
    modelUseCase: String,
    reasoningPolicy: String,
    warmState: String
  ) -> Int {
    let hybridPairs: [(String, ParserEvaluationObservation)] = observations.compactMap {
      observation -> (String, ParserEvaluationObservation)? in
      guard observation.candidate == ParserEvaluationCandidate.hybrid.rawValue,
        observation.modelUseCase == modelUseCase,
        observation.reasoningPolicy == reasoningPolicy,
        observation.warmState == warmState
      else { return nil }
      return ("\(observation.caseID)|\(observation.run)", observation)
    }
    let hybridByCaseRun: [String: ParserEvaluationObservation] = Dictionary(
      uniqueKeysWithValues: hybridPairs
    )
    return observations.filter { (baseline: ParserEvaluationObservation) -> Bool in
      guard baseline.candidate == ParserEvaluationCandidate.baseline22Field.rawValue,
        baseline.promptProfile == FoundationModelsPromptProfile.production.rawValue,
        baseline.modelUseCase == modelUseCase,
        baseline.reasoningPolicy == reasoningPolicy,
        baseline.warmState == warmState,
        baseline.sourceGrounded == true,
        !baseline.unsupportedInventedFacts,
        baseline.behaviorCorrect != false,
        let hybrid = hybridByCaseRun["\(baseline.caseID)|\(baseline.run)"]
      else { return false }
      return hybrid.sourceGrounded != true
        || hybrid.unsupportedInventedFacts
        || hybrid.routeCorrect == false
        || (baseline.behaviorCorrect == true && hybrid.behaviorCorrect != true)
    }.count
  }

  private static func summarize(
    _ observations: [ParserEvaluationObservation],
    profile: String,
    modelUseCase: String,
    reasoningPolicy: String,
    warmState: String,
    candidate: String
  ) -> ParserEvaluationSummary {
    ParserEvaluationSummary(
      promptProfile: profile,
      modelUseCase: modelUseCase,
      reasoningPolicy: reasoningPolicy,
      warmState: warmState,
      sourceGroundingRate: rate(observations.compactMap(\.sourceGrounded)),
      requiredFieldRate: rate(observations.compactMap(\.requiredFieldsCorrect)),
      behaviorRate: rate(observations.compactMap(\.behaviorCorrect)),
      routeAccuracy: optionalRate(observations.compactMap(\.routeCorrect)),
      stabilityRate: rate(observations.compactMap(\.stableWithFirstRun)),
      unsupportedInventedFactCount: observations.filter(\.unsupportedInventedFacts).count,
      p50LatencyMilliseconds: percentile(observations.map(\.latencyMilliseconds), fraction: 0.50),
      p95LatencyMilliseconds: percentile(observations.map(\.latencyMilliseconds), fraction: 0.95),
      averageInputTokenCount: average(observations.compactMap(\.inputTokenCount)),
      averageCachedInputTokenCount: average(observations.compactMap(\.cachedInputTokenCount)),
      averageOutputTokenCount: average(observations.compactMap(\.outputTokenCount)),
      averageReasoningTokenCount: average(observations.compactMap(\.reasoningTokenCount)),
      averageTotalTokenCount: average(observations.compactMap(\.totalTokenCount)),
      p50PrewarmLatencyMilliseconds: optionalPercentile(
        observations.compactMap(\.prewarmLatencyMilliseconds), fraction: 0.50),
      p95PrewarmLatencyMilliseconds: optionalPercentile(
        observations.compactMap(\.prewarmLatencyMilliseconds), fraction: 0.95),
      p50SessionAcquisitionLatencyMilliseconds: optionalPercentile(
        observations.compactMap(\.sessionAcquisitionLatencyMilliseconds), fraction: 0.50),
      p95SessionAcquisitionLatencyMilliseconds: optionalPercentile(
        observations.compactMap(\.sessionAcquisitionLatencyMilliseconds), fraction: 0.95),
      p50ResponseLatencyMilliseconds: optionalPercentile(
        observations.compactMap(\.responseLatencyMilliseconds), fraction: 0.50),
      p95ResponseLatencyMilliseconds: optionalPercentile(
        observations.compactMap(\.responseLatencyMilliseconds), fraction: 0.95),
      averageMappingLatencyMilliseconds: average(
        observations.compactMap(\.mappingLatencyMilliseconds)),
      averageDeterministicExtractionLatencyMilliseconds: average(
        observations.compactMap(\.deterministicExtractionLatencyMilliseconds)),
      averageRouteDecisionLatencyMilliseconds: average(
        observations.compactMap(\.routeDecisionLatencyMilliseconds)),
      averageGroundingAndMergeLatencyMilliseconds: average(
        observations.compactMap(\.groundingAndMergeLatencyMilliseconds)),
      candidate: candidate,
      deterministicFastPathRate: optionalRate(
        observations.compactMap(\.deterministicFastPathUsed)),
      modelInvocationRate: rate(observations.compactMap(\.modelInvoked))
    )
  }

  private static func rate(_ values: [Bool]) -> Double {
    guard !values.isEmpty else { return 1 }
    return Double(values.filter { $0 }.count) / Double(values.count)
  }

  private static func optionalRate(_ values: [Bool]) -> Double? {
    guard !values.isEmpty else { return nil }
    return rate(values)
  }

  private static func percentile(_ values: [Double], fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(Int(ceil(Double(sorted.count) * fraction)) - 1, sorted.count - 1)
    return sorted[max(0, index)]
  }

  private static func optionalPercentile(_ values: [Double], fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    return percentile(values, fraction: fraction)
  }

  private static func average(_ values: [Int]) -> Double? {
    guard !values.isEmpty else { return nil }
    return Double(values.reduce(0, +)) / Double(values.count)
  }

  private static func average(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}

extension Duration {
  fileprivate var milliseconds: Double {
    let components = self.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

private struct InvalidEvaluatorSemanticProposer: SemanticFoodProposing {
  func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
    SemanticFoodProposal(productName: "banana")
  }
}
