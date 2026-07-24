import Foundation
import FoundationModels
import JustLogItCore

// SEMANTIC-PARITY-SCHEMA-BEGIN
@Generable(
  description: "A minimal source-grounded proposal of semantic food facts.",
  representNilExplicitlyInGeneratedContent: true
)
private struct GeneratedSemanticFoodProposal {
  @Guide(description: "Food or product name explicitly supported by the current user facts.")
  var productName: String

  @Guide(description: "Brand or restaurant explicitly stated by the user. Never infer one.")
  var brand: String?

  @Guide(description: "Explicit preparation state such as cooked, fried, raw, or scrambled.")
  var preparation: String?

  @Guide(
    description: "Explicit lookup descriptors such as variety, flavor, cut, size, or percentage.",
    .maximumCount(6)
  )
  var descriptors: [String]

  @Guide(
    description:
      "True only for distinct foods needing separate lookups, such as cereal with milk. False for one named dish."
  )
  var containsMultipleFoods: Bool

  @Guide(
    description: "Short source-supported food names when multiple foods is true; otherwise empty.",
    .maximumCount(8)
  )
  var componentNames: [String]
}
// SEMANTIC-PARITY-SCHEMA-END

// SEMANTIC-PARITY-PROMPT-BEGIN
enum FoundationModelsSemanticPromptProfile: String, CaseIterable, Sendable {
  case minimal

  var instructions: String {
    """
    Identify food facts explicitly supported by the user's current facts. Return only food identity, explicit brand or restaurant, preparation, lookup descriptors, whether distinct foods require separate lookups, and their short component names.

    Do not extract quantities, units, fractions, containers, serving sizes, nutrition, USDA queries, confidence, ambiguity notes, clarification questions, or suggested replies. Never invent a food or brand. A named dish is one food even if it has ingredients. Separate independent foods such as cereal with milk or eggs and toast. Assistant-authored context helps interpret a reply but is not evidence for any returned fact.
    """
  }
}
// SEMANTIC-PARITY-PROMPT-END

enum HybridFoodParserError: LocalizedError {
  case unavailable
  case refused
  case invalidResponse
  case needsManualSearch

  var errorDescription: String? {
    switch self {
    case .unavailable:
      "On-device interpretation isn’t available right now. Search USDA or enter nutrition manually."
    case .refused:
      "That description couldn’t be interpreted on device. Edit it, search USDA, or enter nutrition manually."
    case .invalidResponse:
      "On-device interpretation was incomplete. Search USDA or enter nutrition manually."
    case .needsManualSearch:
      "That description needs a quick manual check. Edit the USDA search terms or enter nutrition manually."
    }
  }
}

/// App-side capability for parsers that already own the authoritative Core validation/policy
/// boundary. LogViewModel consumes this resolution directly instead of parsing and deciding a
/// second time.
protocol FoodDescriptionTerminalResolving: FoodDescriptionParsing {
  func resolveForApplication(
    semanticContext: String,
    groundingText: String,
    turnCount: Int
  ) async throws -> FoodInterpretationTerminalResolution
}

extension HybridFoodInterpretationResult {
  /// The core coordinator expresses a safe fallback as a route, while the app pipeline expresses
  /// it as a recoverable interpretation failure. Do not let an empty fallback request flow into
  /// clarification policy, where the original text could be misclassified a second time.
  func appFacingRequest() throws -> ParsedFoodRequest {
    guard finalDecision.route == .manualSearch else { return request }
    if finalDecision.reasons.contains(.semanticUnavailable) {
      throw HybridFoodParserError.unavailable
    }
    if finalDecision.reasons.contains(.semanticRefused) {
      throw HybridFoodParserError.refused
    }
    let deterministicManualReasons: Set<FoodInterpretationRouteReason> = [
      .missingIdentity,
      .promptInjectionLanguage,
      .deterministicShapeNotPromoted,
      .unsafeAmountBinding,
      .deterministicFamilyDisabled,
      .unsupportedDeterministicShape,
    ]
    if finalDecision.reasons.contains(where: deterministicManualReasons.contains) {
      throw HybridFoodParserError.needsManualSearch
    }
    throw HybridFoodParserError.invalidResponse
  }
}

struct FoundationModelsSemanticFoodProposer: SemanticFoodProposing,
  FoodDescriptionParserPrewarming
{
  static let promptPrefix = "Interpret the current food facts:\n"

  private let model: SystemLanguageModel
  private let reasoningPolicy: FoundationModelsReasoningPolicy
  private let sessionPool: FoundationModelsSemanticSessionPool
  private let evaluationMetricsRecorder: FoundationModelsEvaluationMetricsRecorder?

  init(
    promptProfile: FoundationModelsSemanticPromptProfile = .minimal,
    modelUseCase: FoundationModelsModelUseCase = .general,
    reasoningPolicy: FoundationModelsReasoningPolicy = .capabilityAwareLight,
    evaluationMetricsRecorder: FoundationModelsEvaluationMetricsRecorder? = nil
  ) {
    let model = SystemLanguageModel(useCase: modelUseCase.systemUseCase)
    self.model = model
    self.reasoningPolicy = reasoningPolicy
    self.sessionPool = .init(model: model, instructions: promptProfile.instructions)
    self.evaluationMetricsRecorder = evaluationMetricsRecorder
  }

  func prewarm() async {
    guard let evaluationMetricsRecorder else {
      await sessionPool.prewarm()
      return
    }
    let started = ContinuousClock.now
    let performed = await sessionPool.prewarm()
    if performed {
      await evaluationMetricsRecorder.recordPrewarm(started.duration(to: .now))
    }
  }

  func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
    guard let evaluationMetricsRecorder else {
      return try await performProposal(input)
    }
    await evaluationMetricsRecorder.beginInvocation()
    do {
      let proposal = try await performProposal(input)
      await evaluationMetricsRecorder.finishInvocation()
      return proposal
    } catch {
      await evaluationMetricsRecorder.finishInvocation()
      throw error
    }
  }

  private func performProposal(
    _ input: SemanticFoodProposalInput
  ) async throws -> SemanticFoodProposal {
    let context = input.semanticContext.trimmingCharacters(in: .whitespacesAndNewlines)
    let grounding = input.groundingText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !context.isEmpty, !grounding.isEmpty else {
      throw SemanticFoodProposalError.invalidResponse
    }
    let availability = AppObservability.measure(.parserAvailability) { model.availability }
    switch availability {
    case .available:
      AppObservability.recordParserAvailability(.available)
    case .unavailable(.deviceNotEligible):
      AppObservability.recordParserAvailability(.deviceNotEligible)
      throw SemanticFoodProposalError.unavailable
    case .unavailable(.appleIntelligenceNotEnabled):
      AppObservability.recordParserAvailability(.intelligenceDisabled)
      throw SemanticFoodProposalError.unavailable
    case .unavailable(.modelNotReady):
      AppObservability.recordParserAvailability(.modelNotReady)
      throw SemanticFoodProposalError.unavailable
    case .unavailable:
      AppObservability.recordParserAvailability(.otherUnavailable)
      throw SemanticFoodProposalError.unavailable
    }

    let acquisitionStarted = ContinuousClock.now
    let acquisition = await AppObservability.measure(.hybridSessionAcquisition) {
      await sessionPool.takeSession()
    }
    await evaluationMetricsRecorder?.recordSessionAcquisition(
      acquisitionStarted.duration(to: .now))
    AppObservability.recordSemanticSessionSource(acquisition.source)
    let session = acquisition.session
    let prompt = """
      \(Self.promptPrefix)USER FACTS (the only grounding evidence):
      \(grounding)

      BOUNDED CONTEXT (interpretation only; never copy assistant wording as fact):
      \(context)
      """
    do {
      let responseStarted = ContinuousClock.now
      let response = try await {
        do {
          return try await AppObservability.measure(.hybridSemanticResponse) {
            try await session.respond(
              to: prompt,
              generating: GeneratedSemanticFoodProposal.self,
              options: .init(samplingMode: .greedy, temperature: 0, maximumResponseTokens: 192),
              contextOptions: FoundationModelsFoodParser.contextOptions(
                supportsReasoning: model.capabilities.contains(.reasoning),
                reasoningPolicy: reasoningPolicy
              )
            )
          }
        } catch {
          await evaluationMetricsRecorder?.recordResponse(responseStarted.duration(to: .now))
          throw error
        }
      }()
      await evaluationMetricsRecorder?.recordResponse(
        responseStarted.duration(to: .now),
        inputTokenCount: response.usage.input.totalTokenCount,
        cachedInputTokenCount: response.usage.input.cachedTokenCount,
        outputTokenCount: response.usage.output.totalTokenCount,
        reasoningTokenCount: response.usage.output.reasoningTokenCount,
        totalTokenCount: response.usage.totalTokenCount
      )
      try Task.checkCancellation()
      AppObservability.recordCount(
        .parserInputTokens, .init(response.usage.input.totalTokenCount))
      AppObservability.recordCount(
        .parserCachedInputTokens, .init(response.usage.input.cachedTokenCount))
      AppObservability.recordCount(
        .parserOutputTokens, .init(response.usage.output.totalTokenCount))
      AppObservability.recordCount(
        .parserReasoningTokens, .init(response.usage.output.reasoningTokenCount))
      let generated = response.content
      return SemanticFoodProposal(
        productName: generated.productName,
        brand: generated.brand,
        preparation: generated.preparation,
        descriptors: generated.descriptors,
        containsMultipleFoods: generated.containsMultipleFoods,
        componentNames: generated.componentNames
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw SemanticFoodProposalError.invalidResponse
    }
  }
}

enum OneShotPreparedResourceSource: Sendable, Equatable {
  case prewarmed
  case fresh
}

struct OneShotPreparedResourceAcquisition<Resource: Sendable>: Sendable {
  let resource: Resource
  let source: OneShotPreparedResourceSource
}

/// Framework-independent lifecycle for an expensive resource that may be prepared once ahead of
/// use. The prepared value is consumed by exactly one acquisition; later acquisitions are fresh.
/// Keeping this state machine independent of Foundation Models makes its concurrency and
/// cancellation behavior testable on Simulator.
actor OneShotPreparedResourcePool<Resource: Sendable> {
  private struct Preparation: Sendable {
    let id: UInt64
    var shouldPublish: Bool
  }

  private let makeResource: @Sendable () -> Resource
  private var preparedResource: Resource?
  private var preparation: Preparation?
  private var nextPreparationID: UInt64 = 0

  init(makeResource: @escaping @Sendable () -> Resource) {
    self.makeResource = makeResource
  }

  @discardableResult
  func prewarm(using prepare: @escaping @Sendable (Resource) throws -> Void) async throws -> Bool {
    try Task.checkCancellation()
    guard preparedResource == nil, preparation == nil else { return false }

    let resource = makeResource()
    nextPreparationID &+= 1
    let preparationID = nextPreparationID
    preparation = .init(id: preparationID, shouldPublish: true)

    // Foundation Models exposes prewarm as a synchronous call. Running it on this actor would
    // prevent an interactive acquisition from bypassing speculative work that is still blocked.
    let preparationTask = Task.detached {
      try Task.checkCancellation()
      try prepare(resource)
      try Task.checkCancellation()
    }
    do {
      try await withTaskCancellationHandler {
        try await preparationTask.value
        try Task.checkCancellation()
      } onCancel: {
        preparationTask.cancel()
      }
    } catch {
      if preparation?.id == preparationID {
        preparation = nil
      }
      throw error
    }

    guard preparation?.id == preparationID else { return false }
    let shouldPublish = preparation?.shouldPublish == true
    preparation = nil
    if shouldPublish {
      preparedResource = resource
    }
    return shouldPublish
  }

  func acquire() -> OneShotPreparedResourceAcquisition<Resource> {
    if let preparedResource {
      self.preparedResource = nil
      return .init(resource: preparedResource, source: .prewarmed)
    }
    // The interactive request wins over an unfinished speculative prewarm. Keep the in-flight
    // marker so duplicate prewarms remain suppressed, but discard its result when it completes.
    preparation?.shouldPublish = false
    return .init(resource: makeResource(), source: .fresh)
  }
}

private struct FoundationModelsSemanticSessionPool: Sendable {
  private let model: SystemLanguageModel
  private let pool: OneShotPreparedResourcePool<LanguageModelSession>

  init(model: SystemLanguageModel, instructions: String) {
    self.model = model
    self.pool = OneShotPreparedResourcePool {
      LanguageModelSession(model: model, tools: [], instructions: instructions)
    }
  }

  @discardableResult
  func prewarm() async -> Bool {
    guard case .available = model.availability else { return false }
    do {
      return try await pool.prewarm { session in
        try AppObservability.measure(.hybridSemanticPrewarm) {
          try Task.checkCancellation()
          session.prewarm(promptPrefix: Prompt(FoundationModelsSemanticFoodProposer.promptPrefix))
          try Task.checkCancellation()
        }
      }
    } catch is CancellationError {
      // Prewarming is speculative. Cancellation deliberately leaves no prepared session behind.
      return false
    } catch {
      // Foundation Models prewarm is currently nonthrowing; retain a safe no-op if that changes.
      return false
    }
  }

  func takeSession() async -> FoundationModelsSemanticSessionAcquisition {
    let acquisition = await pool.acquire()
    return .init(
      session: acquisition.resource,
      source: acquisition.source == .prewarmed ? .prewarmed : .fresh
    )
  }
}

private struct FoundationModelsSemanticSessionAcquisition: Sendable {
  let session: LanguageModelSession
  let source: AppObservability.SemanticSessionSource
}

/// App-facing adapter kept separate from the 22-field baseline parser so a request executes one
/// architecture, never both. The Debug launch switch selects this adapter during beta evaluation.
struct FoundationModelsHybridFoodParser: ContextualFoodDescriptionParsing,
  FoodDescriptionTerminalResolving,
  FoodDescriptionParserPrewarming
{
  private let proposer: FoundationModelsSemanticFoodProposer
  private let interpreter: HybridFoodInterpreter

  init(
    promptProfile: FoundationModelsSemanticPromptProfile = .minimal,
    modelUseCase: FoundationModelsModelUseCase = .general,
    reasoningPolicy: FoundationModelsReasoningPolicy = .capabilityAwareLight
  ) {
    let proposer = FoundationModelsSemanticFoodProposer(
      promptProfile: promptProfile,
      modelUseCase: modelUseCase,
      reasoningPolicy: reasoningPolicy
    )
    self.proposer = proposer
    self.interpreter = HybridFoodInterpreter(proposer: proposer)
  }

  func prewarm() async {
    await proposer.prewarm()
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    try await parse(semanticContext: input, groundingText: input)
  }

  func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    let result = try await interpreted(
      semanticContext: semanticContext,
      groundingText: groundingText,
      turnCount: 0
    )
    return try result.appFacingRequest()
  }

  func resolveForApplication(
    semanticContext: String,
    groundingText: String,
    turnCount: Int
  ) async throws -> FoodInterpretationTerminalResolution {
    let result = try await interpreted(
      semanticContext: semanticContext,
      groundingText: groundingText,
      turnCount: turnCount
    )
    _ = try result.appFacingRequest()
    return result.terminalResolution
  }

  private func interpreted(
    semanticContext: String,
    groundingText: String,
    turnCount: Int
  ) async throws -> HybridFoodInterpretationResult {
    let result = try await AppObservability.measure(.hybridPipeline) {
      try await interpreter.interpret(
        semanticContext: semanticContext,
        groundingText: groundingText,
        turnCount: turnCount
      )
    }
    AppObservability.recordInterpretationPhases(result.phaseDurations)
    AppObservability.recordSemanticInvocation(result.modelInvoked ? .invoked : .skipped)
    if let semanticOutcome = HybridSemanticObservation.outcome(
      modelInvoked: result.modelInvoked,
      reasons: result.finalDecision.reasons
    ) {
      AppObservability.recordSemanticOutcome(semanticOutcome)
    }
    let route: AppObservability.ParserRoute =
      switch result.finalDecision.route {
      case .composite: .composite
      case .deterministicSearch, .onDeviceSemantic: .searchReady
      case .clarification: .clarification
      case .manualSearch: .manualSearch
      case .pccCandidate: .pccCandidate
      }
    AppObservability.recordParserRoute(route)
    return result
  }
}

enum HybridSemanticObservation {
  static func outcome(
    modelInvoked: Bool,
    reasons: [FoodInterpretationRouteReason]
  ) -> AppObservability.SemanticOutcome? {
    guard modelInvoked else { return nil }
    if reasons.contains(.semanticUnavailable) { return .unavailable }
    if reasons.contains(.semanticRefused) { return .refused }
    if reasons.contains(.invalidOnDeviceProposal) { return .invalid }
    return .accepted
  }
}
