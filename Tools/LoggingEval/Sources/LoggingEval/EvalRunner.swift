import Foundation
import JustLogItCore

enum ParserEvaluationWarmState: String, Codable, CaseIterable, Sendable {
  case cold
  case prewarmed
}

enum ParserCandidate: String, Codable, CaseIterable, Sendable {
  case baseline
  case deterministicFirst = "deterministic-first"
  case hybrid
}

@available(macOS 27.0, *)
protocol EvaluatorBaselineFoodParsing: FoodDescriptionParsing {
  func parseWithMetrics(
    _ input: String,
    warmState: ParserEvaluationWarmState
  ) async throws -> MacFoundationModelsFoodParser.ParseResult
}

struct EvalCaseInput: Sendable {
  let id: String
  let description: String
  let parsedOverride: ParsedFoodRequest?
}

struct EvalCaseReport: Codable, Sendable {
  var id: String
  /// Raw user text is omitted unless the local evaluator explicitly opts in.
  var input: String?
  var parseSource: String
  var modelAvailability: String?
  var warmState: String
  var parseLatencyMs: Double?
  var semanticResponseLatencyMs: Double?
  var prewarmLatencyMs: Double?
  var inputTokenCount: Int?
  var cachedInputTokenCount: Int?
  var outputTokenCount: Int?
  var reasoningTokenCount: Int?
  var totalTokenCount: Int?
  var brand: String?
  var productName: String?
  /// Raw Foundation Models output after source grounding, before app quantity recovery/defaulting.
  var rawQuantity: Double?
  var rawUnit: String?
  /// Effective values sent through USDA query/ranking/resolution, matching LogViewModel.
  var quantity: Double?
  var unit: String?
  var sourceHadExplicitAmount: Bool
  var quantityRecoveredFromSource: Bool
  var quantityDefaultedToOneServing: Bool
  var fractionOfWhole: Double?
  var containerSize: Double?
  var containerSizeUnit: String?
  var containsMultipleFoods: Bool?
  var searchQuery: String?
  var topFdcID: Int?
  var topDescription: String?
  var topDataType: String?
  var selectionStatus: String
  var resolutionStatus: String
  var resolutionDisplay: String?
  var consumedGrams: Double?
  var hasEnergy: Bool
  var energyKcal: Double?
  var checks: [String: Bool]
  var error: String?
  var parserCandidate: String = ParserCandidate.baseline.rawValue
  var interpretationRoute: String?
  var routeReasons: [String] = []
  var modelInvoked: Bool?
  /// Present for the production deterministic-first candidate. Nil for unrelated candidates.
  var deterministicFastPathUsed: Bool?
  /// Closed production allowlist family, or nil when the candidate fell back to the baseline.
  var deterministicFastPathFamily: String?
  var deterministicExtractionLatencyMs: Double?
  var routeDecisionLatencyMs: Double?
  var semanticGroundingAndMergeLatencyMs: Double?
  var timeToUSDADispatchMs: Double?
}

struct EvalReport: Codable, Sendable {
  var generatedAt: String
  var foundationModelsAvailability: String
  var promptProfile: String
  var modelUseCase: String
  var reasoningPolicy: String = MacFoundationModelsFoodParser.ReasoningPolicy.capabilityAwareLight
    .rawValue
  var warmState: String
  var caseCount: Int
  var passCount: Int
  var failCount: Int
  var includesInputText: Bool
  var p50ParseLatencyMs: Double?
  var p95ParseLatencyMs: Double?
  var p50SemanticResponseLatencyMs: Double?
  var p95SemanticResponseLatencyMs: Double?
  var averageInputTokenCount: Double?
  var averageCachedInputTokenCount: Double?
  var averageOutputTokenCount: Double?
  var averageReasoningTokenCount: Double?
  var cases: [EvalCaseReport]
  var parserCandidate: String = ParserCandidate.baseline.rawValue
}

enum ParseMode: String, Sendable {
  /// Use Foundation Models when available; error if unavailable unless fallback allowed.
  case foundationModels
  /// Force the crude deterministic fake (debug only).
  case fake
  /// Prefer Foundation Models; fall back to fake if unavailable.
  case foundationModelsOrFake
}

struct EvaluationQuantityPreparation: Sendable {
  let effective: ParsedFoodRequest
  let sourceHadExplicitAmount: Bool
  let quantityRecoveredFromSource: Bool
  let quantityDefaultedToOneServing: Bool
  let explicitSourceQuantityPreserved: Bool
}

/// Mirrors the quantity trust boundary used by `LogViewModel.runSearch`.
/// LoggingEval must evaluate the request the app actually sends downstream,
/// while retaining the raw parse in its report for model-quality diagnosis.
enum EvaluationQuantityPipeline {
  static func prepare(
    _ raw: ParsedFoodRequest,
    sourceText: String
  ) -> EvaluationQuantityPreparation {
    let sourceHadExplicitAmount = ParsedQuantityRecovery.containsExplicitAmount(
      in: sourceText,
      for: raw
    )
    let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(in: raw, from: sourceText)
    let effective = ParsedQuantityDefault.applyingDefaultIfNeeded(
      recovered,
      sourceText: sourceText
    )
    let quantityRecovered = !hasUsableAmount(raw) && hasUsableAmount(recovered)
    let defaulted = !hasUsableAmount(recovered) && isOneServing(effective)
    return EvaluationQuantityPreparation(
      effective: effective,
      sourceHadExplicitAmount: sourceHadExplicitAmount,
      quantityRecoveredFromSource: quantityRecovered,
      quantityDefaultedToOneServing: defaulted,
      explicitSourceQuantityPreserved: !sourceHadExplicitAmount || hasUsableAmount(effective)
    )
  }

  private static func hasUsableAmount(_ parsed: ParsedFoodRequest) -> Bool {
    if let quantity = parsed.quantity, quantity.isFinite, quantity > 0,
      parsed.unit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    {
      return true
    }
    if let fraction = parsed.fractionOfWhole, fraction.isFinite, fraction > 0,
      parsed.wholeUnit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    {
      return true
    }
    return false
  }

  private static func isOneServing(_ parsed: ParsedFoodRequest) -> Bool {
    parsed.quantity == 1 && UnitConversion.family(parsed.unit ?? "") == "serving"
  }
}

@available(macOS 27.0, *)
struct EvalRunner {
  private let provider: any FoodDataProviding
  private let parseMode: ParseMode
  private let promptProfile: MacFoundationModelsFoodParser.PromptProfile
  private let modelUseCase: MacFoundationModelsFoodParser.ModelUseCase
  private let reasoningPolicy: MacFoundationModelsFoodParser.ReasoningPolicy
  private let warmState: ParserEvaluationWarmState
  private let baselineParser: any EvaluatorBaselineFoodParsing
  private let parserCandidate: ParserCandidate
  private let includeInput: Bool
  private let semanticProposer: any SemanticFoodProposing
  private let queryBuilder = FoodSearchQueryBuilder()
  private let ranker = FoodSearchResultRanker()
  private let resolver = ServingResolutionService()
  private let calculator = NutritionCalculator()

  init(
    provider: any FoodDataProviding,
    parseMode: ParseMode = .foundationModels,
    promptProfile: MacFoundationModelsFoodParser.PromptProfile = .production,
    modelUseCase: MacFoundationModelsFoodParser.ModelUseCase = .general,
    reasoningPolicy: MacFoundationModelsFoodParser.ReasoningPolicy = .capabilityAwareLight,
    warmState: ParserEvaluationWarmState = .cold,
    parserCandidate: ParserCandidate = .baseline,
    includeInput: Bool = false,
    semanticProposer: (any SemanticFoodProposing)? = nil,
    baselineParser: (any EvaluatorBaselineFoodParsing)? = nil
  ) {
    self.provider = provider
    self.parseMode = parseMode
    self.promptProfile = promptProfile
    self.modelUseCase = modelUseCase
    self.reasoningPolicy = reasoningPolicy
    self.warmState = warmState
    self.parserCandidate = parserCandidate
    self.includeInput = includeInput
    self.baselineParser =
      baselineParser
      ?? MacFoundationModelsFoodParser(
        promptProfile: promptProfile,
        modelUseCase: modelUseCase,
        reasoningPolicy: reasoningPolicy
      )
    self.semanticProposer =
      semanticProposer
      ?? MacFoundationModelsSemanticFoodProposer(
        modelUseCase: modelUseCase,
        reasoningPolicy: reasoningPolicy
      )
  }

  func run(cases: [EvalCaseInput]) async -> EvalReport {
    var reports: [EvalCaseReport] = []
    for item in cases {
      reports.append(await evaluate(item))
    }
    let passCount = reports.filter(\.passed).count
    let latencies = reports.compactMap(\.parseLatencyMs)
    let semanticLatencies = reports.compactMap(\.semanticResponseLatencyMs)
    return EvalReport(
      generatedAt: ISO8601DateFormatter().string(from: Date()),
      foundationModelsAvailability: MacFoundationModelsFoodParser.availabilityDescription(
        for: modelUseCase),
      promptProfile: promptProfile.rawValue,
      modelUseCase: modelUseCase.rawValue,
      reasoningPolicy: reasoningPolicy.rawValue,
      warmState: warmState.rawValue,
      caseCount: reports.count,
      passCount: passCount,
      failCount: reports.count - passCount,
      includesInputText: includeInput,
      p50ParseLatencyMs: Self.percentile(latencies, fraction: 0.50),
      p95ParseLatencyMs: Self.percentile(latencies, fraction: 0.95),
      p50SemanticResponseLatencyMs: Self.percentile(semanticLatencies, fraction: 0.50),
      p95SemanticResponseLatencyMs: Self.percentile(semanticLatencies, fraction: 0.95),
      averageInputTokenCount: Self.average(reports.compactMap(\.inputTokenCount)),
      averageCachedInputTokenCount: Self.average(reports.compactMap(\.cachedInputTokenCount)),
      averageOutputTokenCount: Self.average(reports.compactMap(\.outputTokenCount)),
      averageReasoningTokenCount: Self.average(reports.compactMap(\.reasoningTokenCount)),
      cases: reports,
      parserCandidate: parserCandidate.rawValue
    )
  }

  private func evaluate(_ item: EvalCaseInput) async -> EvalCaseReport {
    let evaluationStarted = ContinuousClock.now
    var report = EvalCaseReport(
      id: item.id,
      input: includeInput ? item.description : nil,
      parseSource: "pending",
      modelAvailability: MacFoundationModelsFoodParser.availabilityDescription(for: modelUseCase),
      warmState: "notApplicable",
      parseLatencyMs: nil,
      semanticResponseLatencyMs: nil,
      prewarmLatencyMs: nil,
      inputTokenCount: nil,
      cachedInputTokenCount: nil,
      outputTokenCount: nil,
      reasoningTokenCount: nil,
      totalTokenCount: nil,
      brand: nil,
      productName: nil,
      rawQuantity: nil,
      rawUnit: nil,
      quantity: nil,
      unit: nil,
      sourceHadExplicitAmount: ParsedQuantityRecovery.containsExplicitAmount(
        in: item.description),
      quantityRecoveredFromSource: false,
      quantityDefaultedToOneServing: false,
      fractionOfWhole: nil,
      containerSize: nil,
      containerSizeUnit: nil,
      containsMultipleFoods: nil,
      searchQuery: nil,
      topFdcID: nil,
      topDescription: nil,
      topDataType: nil,
      selectionStatus: "notRun",
      resolutionStatus: "notRun",
      resolutionDisplay: nil,
      consumedGrams: nil,
      hasEnergy: false,
      energyKcal: nil,
      checks: [:],
      error: nil,
      parserCandidate: item.parsedOverride == nil ? parserCandidate.rawValue : "override",
      interpretationRoute: nil,
      routeReasons: [],
      modelInvoked: nil,
      deterministicFastPathUsed: nil,
      deterministicFastPathFamily: nil,
      deterministicExtractionLatencyMs: nil,
      routeDecisionLatencyMs: nil,
      semanticGroundingAndMergeLatencyMs: nil,
      timeToUSDADispatchMs: nil
    )

    let rawParsed: ParsedFoodRequest
    if let override = item.parsedOverride {
      rawParsed = override
      report.parseSource = "parsedJSON"
    } else {
      do {
        let output = try await parseDescription(item.description)
        rawParsed = output.parsed
        report.parseSource = output.source
        report.warmState = output.warmState
        report.inputTokenCount = output.usage?.inputTokenCount
        report.cachedInputTokenCount = output.usage?.cachedInputTokenCount
        report.outputTokenCount = output.usage?.outputTokenCount
        report.reasoningTokenCount = output.usage?.reasoningTokenCount
        report.totalTokenCount = output.usage?.totalTokenCount
        report.parseLatencyMs = output.generationLatencyMilliseconds
        report.semanticResponseLatencyMs = output.semanticResponseLatencyMilliseconds
        report.prewarmLatencyMs = output.prewarmLatencyMilliseconds
        report.interpretationRoute = output.interpretationRoute
        report.routeReasons = output.routeReasons
        report.modelInvoked = output.modelInvoked
        report.deterministicFastPathUsed = output.deterministicFastPathUsed
        report.deterministicFastPathFamily = output.deterministicFastPathFamily
        report.deterministicExtractionLatencyMs = output.deterministicExtractionLatencyMs
        report.routeDecisionLatencyMs = output.routeDecisionLatencyMs
        report.semanticGroundingAndMergeLatencyMs =
          output.semanticGroundingAndMergeLatencyMs
      } catch {
        report.parseSource = "parseFailed"
        report.error = String(describing: error)
        report.resolutionStatus = "error"
        report.checks = Self.checks(
          hasEnergy: false,
          gramsOK: false,
          resolved: false,
          hadQuantity: false,
          explicitQuantityPreserved: !report.sourceHadExplicitAmount
        )
        return report
      }
    }

    let prepared = EvaluationQuantityPipeline.prepare(rawParsed, sourceText: item.description)
    let parsed = prepared.effective
    report.productName = parsed.productName
    report.brand = parsed.brand
    report.rawQuantity = rawParsed.quantity
    report.rawUnit = rawParsed.unit
    report.quantity = parsed.quantity
    report.unit = parsed.unit
    report.sourceHadExplicitAmount = prepared.sourceHadExplicitAmount
    report.quantityRecoveredFromSource = prepared.quantityRecoveredFromSource
    report.quantityDefaultedToOneServing = prepared.quantityDefaultedToOneServing
    report.fractionOfWhole = parsed.fractionOfWhole
    report.containerSize = parsed.containerSize
    report.containerSizeUnit = parsed.containerSizeUnit
    report.containsMultipleFoods = parsed.containsMultipleFoods

    if let route = report.interpretationRoute,
      route == FoodInterpretationRoute.clarification.rawValue
        || route == FoodInterpretationRoute.composite.rawValue
        || route == FoodInterpretationRoute.manualSearch.rawValue
    {
      report.resolutionStatus = route
      report.checks = Self.checks(
        hasEnergy: false,
        gramsOK: true,
        resolved: false,
        hadQuantity: parsed.quantity != nil || parsed.fractionOfWhole != nil,
        explicitQuantityPreserved: prepared.explicitSourceQuantityPreserved
      )
      report.checks["safeNonSearchRoute"] = true
      return report
    }

    let searchRequest = queryBuilder.build(from: parsed)
    report.searchQuery = searchRequest.query

    do {
      report.timeToUSDADispatchMs = evaluationStarted.duration(to: .now).evaluationMilliseconds
      let response = try await provider.search(searchRequest)
      let ranked = ranker.rank(response.foods, for: parsed)
      guard let top = ranked.first else {
        report.resolutionStatus = "noResults"
        report.error = "No USDA foods matched"
        report.checks = Self.checks(
          hasEnergy: false,
          gramsOK: false,
          resolved: false,
          hadQuantity: parsed.quantity != nil,
          explicitQuantityPreserved: prepared.explicitSourceQuantityPreserved
        )
        return report
      }

      report.topFdcID = top.fdcID
      report.topDescription = top.description
      report.topDataType = top.dataType

      guard
        let selected = FoodSearchAutoSelect.highConfidencePick(
          ranked: ranked,
          for: parsed
        )
      else {
        // Match the app: ranking determines picker order, never permission to assume nutrition.
        // Do not fetch details or default a serving until the user confirms a record.
        report.selectionStatus = "pickerRequired"
        report.resolutionStatus = "pickerRequired"
        report.checks = Self.checks(
          hasEnergy: false,
          gramsOK: true,
          resolved: false,
          hadQuantity: parsed.quantity != nil || parsed.fractionOfWhole != nil,
          explicitQuantityPreserved: prepared.explicitSourceQuantityPreserved
        )
        report.checks["pickerRequired"] = true
        return report
      }

      report.selectionStatus = "autoSelected"

      let details = try await provider.foodDetails(fdcID: selected.fdcID)
      let selectedFoodParsed = ParsedQuantityDefault.applyingDefaultIfNeeded(
        parsed,
        sourceText: item.description,
        selectedFood: details
      )
      let defaultedAfterSelection =
        parsed.quantity == nil && parsed.fractionOfWhole == nil
        && selectedFoodParsed.quantity == 1
        && UnitConversion.family(selectedFoodParsed.unit ?? "") == "serving"
      report.quantity = selectedFoodParsed.quantity
      report.unit = selectedFoodParsed.unit
      report.quantityDefaultedToOneServing =
        report.quantityDefaultedToOneServing || defaultedAfterSelection
      let hasEnergyInRecord =
        details.nutrientsPer100Grams.contains { $0.key == .energy }
        || details.nutrientsPerServing.contains { $0.key == .energy }

      switch resolver.resolve(selectedFoodParsed, against: details) {
      case .needsClarification(let explanation):
        report.resolutionStatus = "needsClarification"
        report.resolutionDisplay = explanation
        report.hasEnergy = hasEnergyInRecord
        report.checks = Self.checks(
          hasEnergy: hasEnergyInRecord,
          gramsOK: true,  // No calculation occurred; clarification is a safe outcome.
          resolved: false,
          hadQuantity: selectedFoodParsed.quantity != nil
            || selectedFoodParsed.fractionOfWhole != nil,
          explicitQuantityPreserved: prepared.explicitSourceQuantityPreserved
        )
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

        let quantityPresent =
          selectedFoodParsed.quantity != nil || selectedFoodParsed.fractionOfWhole != nil
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
          hadQuantity: quantityPresent,
          explicitQuantityPreserved: prepared.explicitSourceQuantityPreserved
        )
      }
    } catch {
      report.error = String(describing: error)
      report.resolutionStatus = "error"
      report.checks = Self.checks(
        hasEnergy: false,
        gramsOK: false,
        resolved: false,
        hadQuantity: false,
        explicitQuantityPreserved: prepared.explicitSourceQuantityPreserved
      )
    }

    return report
  }

  private struct ParseOutput {
    let parsed: ParsedFoodRequest
    let source: String
    let usage: MacFoundationModelsFoodParser.UsageMetrics?
    let warmState: String
    let generationLatencyMilliseconds: Double?
    let semanticResponseLatencyMilliseconds: Double?
    let prewarmLatencyMilliseconds: Double?
    let interpretationRoute: String?
    let routeReasons: [String]
    let modelInvoked: Bool?
    let deterministicFastPathUsed: Bool?
    let deterministicFastPathFamily: String?
    var deterministicExtractionLatencyMs: Double? = nil
    var routeDecisionLatencyMs: Double? = nil
    var semanticGroundingAndMergeLatencyMs: Double? = nil
  }

  private func parseDescription(_ description: String) async throws -> ParseOutput {
    if parseMode != .fake, parserCandidate == .hybrid {
      let started = ContinuousClock.now
      let metricsBridge = EvaluatorSemanticMetricsBridge(
        proposer: semanticProposer,
        warmState: warmState
      )
      let result = try await HybridFoodInterpreter(proposer: metricsBridge).interpret(
        semanticContext: description,
        groundingText: description
      )
      let semanticMetrics = await metricsBridge.capturedMetrics()
      return ParseOutput(
        parsed: result.request,
        source: "hybrid",
        usage: semanticMetrics?.usage,
        warmState: result.modelInvoked ? warmState.rawValue : "notApplicable",
        generationLatencyMilliseconds: started.duration(to: .now).evaluationMilliseconds,
        semanticResponseLatencyMilliseconds: semanticMetrics?.generationLatencyMilliseconds,
        prewarmLatencyMilliseconds: semanticMetrics?.prewarmLatencyMilliseconds,
        interpretationRoute: result.finalDecision.route.rawValue,
        routeReasons: result.finalDecision.reasons.map(\.rawValue),
        modelInvoked: result.modelInvoked,
        deterministicFastPathUsed: nil,
        deterministicFastPathFamily: nil,
        deterministicExtractionLatencyMs:
          result.phaseDurations.deterministicExtraction.evaluationMilliseconds,
        routeDecisionLatencyMs: result.phaseDurations.routeDecision.evaluationMilliseconds,
        semanticGroundingAndMergeLatencyMs:
          result.phaseDurations.semanticGroundingAndMerge?.evaluationMilliseconds
      )
    }
    if parseMode != .fake, parserCandidate == .deterministicFirst {
      let started = ContinuousClock.now
      let metricsBridge = EvaluatorBaselineMetricsBridge(
        parser: baselineParser,
        warmState: warmState
      )
      let result = try await DeterministicFirstFoodParser(fallback: metricsBridge).interpret(
        semanticContext: description,
        groundingText: description
      )
      let baselineMetrics = await metricsBridge.capturedMetrics()
      return ParseOutput(
        parsed: result.request,
        source: result.usedDeterministicFastPath
          ? "deterministicFirst.fastPath" : "deterministicFirst.baselineFallback",
        usage: baselineMetrics?.usage,
        warmState: result.usedDeterministicFastPath ? "notApplicable" : warmState.rawValue,
        generationLatencyMilliseconds: started.duration(to: .now).evaluationMilliseconds,
        semanticResponseLatencyMilliseconds: nil,
        prewarmLatencyMilliseconds: baselineMetrics?.prewarmLatencyMilliseconds,
        interpretationRoute: result.routingDecision.route.rawValue,
        routeReasons: result.routingDecision.reasons.map(\.rawValue),
        modelInvoked: !result.usedDeterministicFastPath,
        deterministicFastPathUsed: result.usedDeterministicFastPath,
        deterministicFastPathFamily: result.promotedFamily?.rawValue,
        deterministicExtractionLatencyMs:
          result.phaseDurations.deterministicExtraction.evaluationMilliseconds,
        routeDecisionLatencyMs: result.phaseDurations.routeDecision.evaluationMilliseconds
      )
    }
    switch parseMode {
    case .foundationModels:
      let result = try await baselineParser.parseWithMetrics(description, warmState: warmState)
      return ParseOutput(
        parsed: result.parsed,
        source: "foundationModels",
        usage: result.usage,
        warmState: warmState.rawValue,
        generationLatencyMilliseconds: result.generationLatencyMilliseconds,
        semanticResponseLatencyMilliseconds: nil,
        prewarmLatencyMilliseconds: result.prewarmLatencyMilliseconds,
        interpretationRoute: nil,
        routeReasons: [],
        modelInvoked: true,
        deterministicFastPathUsed: nil,
        deterministicFastPathFamily: nil
      )
    case .fake:
      return ParseOutput(
        parsed: Self.deterministicFakeParse(description),
        source: "deterministicFake",
        usage: nil,
        warmState: "notApplicable",
        generationLatencyMilliseconds: nil,
        semanticResponseLatencyMilliseconds: nil,
        prewarmLatencyMilliseconds: nil,
        interpretationRoute: nil,
        routeReasons: [],
        modelInvoked: false,
        deterministicFastPathUsed: parserCandidate == .deterministicFirst ? false : nil,
        deterministicFastPathFamily: nil
      )
    case .foundationModelsOrFake:
      if MacFoundationModelsFoodParser.isAvailable(for: modelUseCase) {
        let result = try await baselineParser.parseWithMetrics(description, warmState: warmState)
        return ParseOutput(
          parsed: result.parsed,
          source: "foundationModels",
          usage: result.usage,
          warmState: warmState.rawValue,
          generationLatencyMilliseconds: result.generationLatencyMilliseconds,
          semanticResponseLatencyMilliseconds: nil,
          prewarmLatencyMilliseconds: result.prewarmLatencyMilliseconds,
          interpretationRoute: nil,
          routeReasons: [],
          modelInvoked: true,
          deterministicFastPathUsed: nil,
          deterministicFastPathFamily: nil
        )
      }
      return ParseOutput(
        parsed: Self.deterministicFakeParse(description),
        source: "deterministicFake",
        usage: nil,
        warmState: "notApplicable",
        generationLatencyMilliseconds: nil,
        semanticResponseLatencyMilliseconds: nil,
        prewarmLatencyMilliseconds: nil,
        interpretationRoute: nil,
        routeReasons: [],
        modelInvoked: false,
        deterministicFastPathUsed: nil,
        deterministicFastPathFamily: nil
      )
    }
  }

  /// Lets the production deterministic-first Core wrapper call the evaluator's 22-field parser
  /// while retaining the richer response metrics for the report when fallback is actually used.
  private actor EvaluatorBaselineMetricsBridge: FoodDescriptionParsing {
    private let parser: any EvaluatorBaselineFoodParsing
    private let warmState: ParserEvaluationWarmState
    private var metrics: MacFoundationModelsFoodParser.ParseResult?

    init(
      parser: any EvaluatorBaselineFoodParsing,
      warmState: ParserEvaluationWarmState
    ) {
      self.parser = parser
      self.warmState = warmState
    }

    func parse(_ input: String) async throws -> ParsedFoodRequest {
      let result = try await parser.parseWithMetrics(input, warmState: warmState)
      metrics = result
      return result.parsed
    }

    func capturedMetrics() -> MacFoundationModelsFoodParser.ParseResult? {
      metrics
    }
  }

  /// Adapts the Core protocol to the evaluator's richer metrics capability. Injected deterministic
  /// fakes continue to use the plain proposer method, while the real Mac proposer receives the
  /// requested warm state and reports the resulting usage and timings.
  private actor EvaluatorSemanticMetricsBridge: SemanticFoodProposing {
    private let proposer: any SemanticFoodProposing
    private let warmState: ParserEvaluationWarmState
    private var metrics: EvaluatorSemanticProposalResult?

    init(
      proposer: any SemanticFoodProposing,
      warmState: ParserEvaluationWarmState
    ) {
      self.proposer = proposer
      self.warmState = warmState
    }

    func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
      guard let measured = proposer as? any EvaluatorSemanticFoodProposing else {
        return try await proposer.propose(input)
      }
      let result = try await measured.proposeWithMetrics(input, warmState: warmState)
      metrics = result
      return result.proposal
    }

    func capturedMetrics() -> EvaluatorSemanticProposalResult? {
      metrics
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
    hadQuantity: Bool,
    explicitQuantityPreserved: Bool
  ) -> [String: Bool] {
    [
      "energyNutrientPresent": hasEnergy,
      "consumedGramsFinitePositiveWhenQuantityPresent": gramsOK,
      "servingResolved": resolved,
      "inputHadQuantity": hadQuantity,
      "explicitSourceQuantityPreserved": explicitQuantityPreserved,
    ]
  }

  private static func percentile(_ values: [Double], fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let index = min(Int(ceil(Double(sorted.count) * fraction)) - 1, sorted.count - 1)
    return sorted[max(0, index)]
  }

  private static func average(_ values: [Int]) -> Double? {
    guard !values.isEmpty else { return nil }
    return Double(values.reduce(0, +)) / Double(values.count)
  }
}

extension EvalCaseReport {
  var passed: Bool {
    if error != nil { return false }
    guard checks["explicitSourceQuantityPreserved"] == true else { return false }
    guard checks["consumedGramsFinitePositiveWhenQuantityPresent"] == true else { return false }
    // No USDA record has been selected on these safe stops, so requiring its nutrients would turn
    // the intended user decision boundary into an evaluator failure.
    if resolutionStatus == "pickerRequired" && checks["pickerRequired"] == true {
      return true
    }
    if checks["safeNonSearchRoute"] == true {
      return true
    }
    guard checks["energyNutrientPresent"] == true else { return false }
    // Safe clarification is acceptable; explicit source-quantity loss is gated above.
    if checks["servingResolved"] == true { return true }
    if resolutionStatus == "needsClarification" {
      return true
    }
    return false
  }
}

extension Duration {
  fileprivate var evaluationMilliseconds: Double {
    let components = self.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
