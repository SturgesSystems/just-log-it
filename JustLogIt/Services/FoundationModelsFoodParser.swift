import Foundation
import FoundationModels
import JustLogItCore

enum FoodParserError: LocalizedError {
  case unavailable(String)
  case emptyInput
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .emptyInput: "Enter a food description first."
    case .invalidResponse:
      "The on-device parser returned an incomplete description. Search manually instead."
    }
  }
}

@Generable(
  description:
    "A structured interpretation of one principal food description for database lookup. Never contains nutrition facts or a database selection.",
  representNilExplicitlyInGeneratedContent: true
)
private struct GeneratedFoodDescription {
  @Guide(description: "Brand or restaurant explicitly stated by the person. Never infer one.")
  var brand: String?

  @Guide(
    description:
      "Concise real food or product name only (e.g. eggs, oatmeal, pizza). Empty string when the person only gave praise, feelings, dismissal, or placeholders with no food (e.g. something yummy, delicious, who cares, idk, whatever, n/a, a snack, leftovers) — never invent a food, and never use those phrases as the product name."
  )
  var productName: String

  @Guide(
    description:
      "Concise food database search terms without quantity or conversational filler. Empty when productName is empty."
  )
  var searchTerms: String

  @Guide(
    description:
      "Amount actually consumed after converting written numbers and fractions. For a fraction of a sized container, do not use the container's full size here; put the fraction, whole-item unit, and full size in their dedicated fields."
  )
  var quantity: Double?

  @Guide(
    description:
      "Unit for quantity, singular when practical. It must describe the consumed quantity, not the full container size."
  )
  var unit: String?

  @Guide(description: "Original human-readable quantity phrase.")
  var quantityText: String?

  @Guide(
    description: "Fraction of a whole item when explicitly stated, such as 0.375 for three eighths."
  )
  var fractionOfWhole: Double?

  @Guide(description: "Whole-item unit associated with fractionOfWhole, such as pizza or bottle.")
  var wholeUnit: String?

  @Guide(
    description:
      "Explicit full container size before applying fractionOfWhole. Example: for half a 12-ounce bottle, this is 12."
  )
  var containerSize: Double?

  @Guide(
    description:
      "Unit for the full containerSize. Example: for half a 12-ounce bottle, this is ounce."
  )
  var containerSizeUnit: String?

  @Guide(description: "Second equivalent quantity explicitly supplied by the person.")
  var alternateQuantity: Double?

  @Guide(description: "Unit for alternateQuantity.")
  var alternateUnit: String?

  @Guide(
    description:
      "Preparation state that materially changes lookup, such as cooked, raw, fried, or scrambled.")
  var preparation: String?

  @Guide(
    description:
      "Lookup descriptors such as flavor, crust type, variety, cut, size, fat percentage, or product line.",
    .maximumCount(6)
  )
  var descriptors: [String]

  @Guide(
    description:
      "True when wording includes about, around, roughly, almost, a few, some, several, a couple, a handful, or another approximation."
  )
  var isApproximate: Bool

  @Guide(
    description:
      "True when the input names more than one distinct food that should each get its own USDA lookup (e.g. cereal with milk, eggs and toast, coffee with cream). False for a single dish name even if it has ingredients (e.g. pepperoni pizza)."
  )
  var containsMultipleFoods: Bool

  @Guide(
    description:
      "When containsMultipleFoods is true, list each distinct food to look up separately, short names only (e.g. cereal, milk). Empty when a single food. Do not invent foods not present in the message.",
    .maximumCount(8)
  )
  var componentNames: [String]

  @Guide(description: "Short internal note on material ambiguity. Not shown to the user.")
  var ambiguityNotes: String?

  @Guide(
    description:
      "True only when a real food is already identified AND the person did not state a concrete amount (or only said a few/some/several/a couple/a handful). False when productName is empty, and false when a definite number or fraction is present. Never invent a quantity."
  )
  var quantityNeedsClarification: Bool

  @Guide(
    description:
      """
      True only when a real food is already identified AND cook/preparation was not stated but would change which USDA record matches (e.g. eggs without scrambled/fried/boiled/poached; meat or potatoes without cooking method; raw vs cooked when both exist). False when productName is empty, when prep is already in the message, or when prep does not matter for lookup (e.g. banana, apple, branded packaged snack with a clear product name).
      """
  )
  var preparationNeedsClarification: Bool

  @Guide(
    description:
      """
      One natural user-facing question shown verbatim (a single sentence people would say in chat — never instruction-style alternatives like "What did you eat / what was it?"). Empty only when ready for USDA search.
      Priority (first only — never skip ahead):
      1) No real food named → ask only for the food name, matching tone (e.g. "I'm sure it was! What was it?"). Do NOT mention amount, prep, cooking, temperature, or container.
      2) More than one distinct food → which one to log.
      3) Food known, amount vague/missing when it matters → how much / how many.
      4) Food known, prep missing when it changes lookup → how it was prepared.
      """
  )
  var clarificationPrompt: String?

  @Guide(
    description:
      """
      Optional short tap-to-send *answers* (0–4), never questions and never ending with '?'.
      When productName is empty (identity gap): leave this array EMPTY — the person should type the food name freeform. Do not suggest warm, cooked, delicious, yummy, or other non-food words.
      When food is known: concrete answers only, e.g. "2 scrambled", "3 fried", "1 cup".
      When multiple foods: short food names from the message only.
      """,
    .maximumCount(4)
  )
  var clarificationSuggestions: [String]
}

enum FoundationModelsPromptProfile: String, CaseIterable, Sendable {
  case production
  case leanCandidate

  var instructions: String {
    switch self {
    case .production:
      """
      You are the food-log interpreter. Output structured fields for one principal food for a USDA database lookup, plus optional soft clarification for the user.

      Facts only: never invent brand, package weight, restaurant size, pizza diameter, serving size, nutrients, or a database record. Never invent a food name. Convert written numbers and fractions. For a fraction of a sized container (e.g. half a 12-ounce bottle), keep fractionOfWhole, wholeUnit, containerSize, and containerSizeUnit separate. An entire package is not automatically one serving. Strip 'I ate', mealtime, and 'please log' from search terms.

      Identity first: productName must be a real food/product. If the message is only praise, vagueness, dismissal, or non-food chatter ("something yummy", "delicious", "who cares?", "idk", "whatever", "n/a", "a snack", "leftovers"), leave productName and searchTerms empty — never use those phrases as the food name. Do not set quantityNeedsClarification or preparationNeedsClarification until a real food is known.

      Multi-food meals: when the person ate distinct items that each have their own USDA records (cereal with milk; eggs and toast; coffee with cream), set containsMultipleFoods true and fill componentNames with each item (e.g. cereal, milk). Do not invent components. A single named dish (pepperoni pizza, chicken burrito) is one food — not multi. When componentNames has 2+ items, leave clarificationPrompt empty so the app can log them as one multi-item entry.

      Soft clarification: the app shows clarificationPrompt verbatim and blocks USDA search while it is non-empty. Write one natural chat question (no slash alternatives, no "Interpreted as…"). Gaps in order: (1) no food → ask only for the food name (tone-match); leave clarificationSuggestions empty; (2) multi without clear componentNames → which items; (3) food known, vague amount (a few/some) → how many/how much; (4) food known and prep would change USDA match but was not stated (classic: "three eggs" without scrambled/fried/boiled) → how cooked. Written numbers ("three") count as a concrete amount. Leave clarificationPrompt empty when ready for search or multi-component handoff.

      Conversation replies: when the input includes an assistant question and a user reply, merge the reply into the interpretation. A dismissive or non-food reply is not a productName — ask again for the food instead of searching.
      """
    case .leanCandidate:
      """
      Extract foods for USDA lookup from explicit facts only. Never invent food/brand/quantity. Multi-item meals: containsMultipleFoods + componentNames (e.g. cereal, milk). Empty productName for non-food text. Flag missing prep when it changes lookup. Written counts are concrete. clarificationPrompt: one natural sentence; empty when multi-components are listed or ready for search.
      """
    }
  }
}

/// Experimental model choice for the on-device parser evaluation harness.
/// Production remains on the general-purpose model until device measurements
/// show that content tagging preserves the app's clarification behavior.
enum FoundationModelsModelUseCase: String, CaseIterable, Sendable {
  case general
  case contentTagging

  var systemUseCase: SystemLanguageModel.UseCase {
    switch self {
    case .general: .general
    case .contentTagging: .contentTagging
    }
  }
}

/// Evaluation dimension for measuring whether light reasoning earns its latency/token cost.
/// App construction never reads this from runtime configuration: production always uses the
/// capability-aware default and omits reasoning only when the selected model cannot support it.
enum FoundationModelsReasoningPolicy: String, CaseIterable, Sendable {
  case capabilityAwareLight
  #if DEBUG
    case disabled
  #endif

  func contextOptions(supportsReasoning: Bool) -> ContextOptions {
    switch self {
    case .capabilityAwareLight:
      ContextOptions(reasoningLevel: supportsReasoning ? .light : nil)
    #if DEBUG
      case .disabled:
        ContextOptions(reasoningLevel: nil)
    #endif
    }
  }
}

/// Optional capability kept separate from `FoodDescriptionParsing` so Core and
/// test parsers do not need to know about Foundation Models session lifecycle.
protocol FoodDescriptionParserPrewarming: Sendable {
  func prewarm() async
}

/// Content-free measurements exposed only when the device evaluation harness injects a recorder.
/// These are observable app intervals and Foundation Models usage counters—not model-loading or
/// time-to-first-token measurements, which the framework APIs used here do not expose.
struct FoundationModelsEvaluationMetrics: Sendable, Equatable {
  var prewarmLatencyMilliseconds: Double? = nil
  var sessionAcquisitionLatencyMilliseconds: Double? = nil
  var responseLatencyMilliseconds: Double? = nil
  var mappingLatencyMilliseconds: Double? = nil
  var inputTokenCount: Int? = nil
  var cachedInputTokenCount: Int? = nil
  var outputTokenCount: Int? = nil
  var reasoningTokenCount: Int? = nil
  var totalTokenCount: Int? = nil
}

/// One invocation at a time is recorded because the physical evaluation harness runs each parser
/// instance sequentially. Production constructs neither this actor nor any metrics snapshot.
actor FoundationModelsEvaluationMetricsRecorder {
  private var pendingPrewarmLatencyMilliseconds: Double?
  private var active: FoundationModelsEvaluationMetrics?
  private var completed: FoundationModelsEvaluationMetrics?

  func recordPrewarm(_ duration: Duration) {
    pendingPrewarmLatencyMilliseconds = Self.milliseconds(duration)
  }

  func beginInvocation() {
    active = FoundationModelsEvaluationMetrics(
      prewarmLatencyMilliseconds: pendingPrewarmLatencyMilliseconds
    )
    pendingPrewarmLatencyMilliseconds = nil
  }

  func recordSessionAcquisition(_ duration: Duration) {
    active?.sessionAcquisitionLatencyMilliseconds = Self.milliseconds(duration)
  }

  func recordResponse(
    _ duration: Duration,
    inputTokenCount: Int,
    cachedInputTokenCount: Int,
    outputTokenCount: Int,
    reasoningTokenCount: Int,
    totalTokenCount: Int
  ) {
    active?.responseLatencyMilliseconds = Self.milliseconds(duration)
    active?.inputTokenCount = Self.count(inputTokenCount)
    active?.cachedInputTokenCount = Self.count(cachedInputTokenCount)
    active?.outputTokenCount = Self.count(outputTokenCount)
    active?.reasoningTokenCount = Self.count(reasoningTokenCount)
    active?.totalTokenCount = Self.count(totalTokenCount)
  }

  /// Records a completed framework call that ended in an error before usage became available.
  func recordResponse(_ duration: Duration) {
    active?.responseLatencyMilliseconds = Self.milliseconds(duration)
  }

  func recordMapping(_ duration: Duration) {
    active?.mappingLatencyMilliseconds = Self.milliseconds(duration)
  }

  func finishInvocation() {
    completed = active
    active = nil
  }

  /// Consumes the most recently completed invocation so metrics cannot bleed into another case.
  func takeCompletedInvocation() -> FoundationModelsEvaluationMetrics? {
    defer { completed = nil }
    return completed
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let bounded = AppObservability.BoundedDuration(duration).value
    let components = bounded.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func count(_ value: Int) -> Int {
    AppObservability.Count(value).value
  }
}

/// Holds at most one unused, prewarmed session. Taking it removes it from the
/// pool, so a session that has accumulated a transcript is never reused for a
/// different food description.
private struct FoundationModelsFoodParserSessionPool: Sendable {
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
        try AppObservability.measure(.parserPrewarm) {
          try Task.checkCancellation()
          session.prewarm(promptPrefix: Prompt(FoundationModelsFoodParser.promptPrefix))
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

  func takeSession() async -> LanguageModelSession {
    await pool.acquire().resource
  }
}

struct FoundationModelsFoodParser: FoodDescriptionParsing, FoodDescriptionParserPrewarming {
  fileprivate static let promptPrefix = "Interpret this food description: "

  private let promptProfile: FoundationModelsPromptProfile
  private let modelUseCase: FoundationModelsModelUseCase
  private let reasoningPolicy: FoundationModelsReasoningPolicy
  private let model: SystemLanguageModel
  private let sessionPool: FoundationModelsFoodParserSessionPool
  private let evaluationMetricsRecorder: FoundationModelsEvaluationMetricsRecorder?

  init(
    promptProfile: FoundationModelsPromptProfile = .production,
    modelUseCase: FoundationModelsModelUseCase = .general,
    reasoningPolicy: FoundationModelsReasoningPolicy = .capabilityAwareLight,
    evaluationMetricsRecorder: FoundationModelsEvaluationMetricsRecorder? = nil
  ) {
    self.promptProfile = promptProfile
    self.modelUseCase = modelUseCase
    self.reasoningPolicy = reasoningPolicy
    let model = SystemLanguageModel(useCase: modelUseCase.systemUseCase)
    self.model = model
    self.sessionPool = FoundationModelsFoodParserSessionPool(
      model: model,
      instructions: promptProfile.instructions
    )
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

  static func contextOptions(
    supportsReasoning: Bool,
    reasoningPolicy: FoundationModelsReasoningPolicy = .capabilityAwareLight
  ) -> ContextOptions {
    reasoningPolicy.contextOptions(supportsReasoning: supportsReasoning)
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    try await parse(semanticContext: input, groundingText: input)
  }

  func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    guard let evaluationMetricsRecorder else {
      return try await performParse(
        semanticContext: semanticContext,
        groundingText: groundingText
      )
    }
    await evaluationMetricsRecorder.beginInvocation()
    do {
      let parsed = try await performParse(
        semanticContext: semanticContext,
        groundingText: groundingText
      )
      await evaluationMetricsRecorder.finishInvocation()
      return parsed
    } catch {
      await evaluationMetricsRecorder.finishInvocation()
      throw error
    }
  }

  private func performParse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    let inputs = try Self.normalizedInputs(
      semanticContext: semanticContext,
      groundingText: groundingText
    )

    let availability = AppObservability.measure(.parserAvailability) { model.availability }
    switch availability {
    case .available:
      AppObservability.recordParserAvailability(.available)
      break
    case .unavailable(.deviceNotEligible):
      AppObservability.recordParserAvailability(.deviceNotEligible)
      throw FoodParserError.unavailable(
        "Apple Intelligence is not supported on this device. Search manually instead.")
    case .unavailable(.appleIntelligenceNotEnabled):
      AppObservability.recordParserAvailability(.intelligenceDisabled)
      throw FoodParserError.unavailable(
        "Apple Intelligence is turned off. Enable it in Settings or search manually.")
    case .unavailable(.modelNotReady):
      AppObservability.recordParserAvailability(.modelNotReady)
      throw FoodParserError.unavailable(
        "The on-device language model is not ready yet. Search manually while it finishes preparing."
      )
    case .unavailable:
      AppObservability.recordParserAvailability(.otherUnavailable)
      throw FoodParserError.unavailable(
        "The on-device language model is unavailable. Search manually instead.")
    }

    let sessionStarted = ContinuousClock.now
    let session = await AppObservability.measure(.parserSessionAcquisition) {
      let session = await sessionPool.takeSession()
      return session
    }
    await evaluationMetricsRecorder?.recordSessionAcquisition(
      sessionStarted.duration(to: .now))
    let options = GenerationOptions(
      samplingMode: .greedy, temperature: 0, maximumResponseTokens: 500)
    let contextOptions = Self.contextOptions(
      supportsReasoning: model.capabilities.contains(.reasoning),
      reasoningPolicy: reasoningPolicy)
    let responseStarted = ContinuousClock.now
    let response = try await {
      do {
        return try await AppObservability.measure(.parserResponse) {
          try await session.respond(
            to: Self.promptPrefix + inputs.semanticContext,
            generating: GeneratedFoodDescription.self,
            options: options,
            contextOptions: contextOptions
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
    AppObservability.recordCount(
      .parserInputTokens, .init(response.usage.input.totalTokenCount))
    AppObservability.recordCount(
      .parserCachedInputTokens, .init(response.usage.input.cachedTokenCount))
    AppObservability.recordCount(
      .parserOutputTokens, .init(response.usage.output.totalTokenCount))
    AppObservability.recordCount(
      .parserReasoningTokens, .init(response.usage.output.reasoningTokenCount))
    let generated = response.content
    let mappingStarted = ContinuousClock.now
    let parsed: ParsedFoodRequest
    do {
      parsed = try AppObservability.measure(.parserMapping) {
        // Conversation context may help the model understand a clarification reply, but it is not
        // evidence. Only user-authored grounding text can authorize facts that affect nutrition.
        try map(generated, originalInput: inputs.groundingText)
      }
    } catch {
      await evaluationMetricsRecorder?.recordMapping(mappingStarted.duration(to: .now))
      throw error
    }
    await evaluationMetricsRecorder?.recordMapping(mappingStarted.duration(to: .now))
    let route: AppObservability.ParserRoute
    if parsed.containsMultipleFoods && parsed.componentNames.count >= 2 {
      route = .composite
    } else if parsed.clarificationPrompt != nil {
      route = .clarification
    } else {
      route = .searchReady
    }
    AppObservability.recordParserRoute(route)
    return parsed
  }

  static func normalizedInputs(
    semanticContext: String,
    groundingText: String
  ) throws -> (semanticContext: String, groundingText: String) {
    let context = semanticContext.trimmingCharacters(in: .whitespacesAndNewlines)
    let evidence = groundingText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !evidence.isEmpty else { throw FoodParserError.emptyInput }
    return (context.isEmpty ? evidence : context, evidence)
  }

  private func map(
    _ generated: GeneratedFoodDescription,
    originalInput: String
  ) throws -> ParsedFoodRequest {
    let productName = generated.productName.trimmingCharacters(in: .whitespacesAndNewlines)
    let clarificationPrompt = cleaned(generated.clarificationPrompt)
    let components = generated.componentNames.compactMap(cleaned)
    // Empty identity is valid when clarifying or handing off a multi-item meal.
    if productName.isEmpty, clarificationPrompt == nil, components.count < 2 {
      throw FoodParserError.invalidResponse
    }
    let candidate = ParsedFoodRequest(
      brand: cleaned(generated.brand),
      productName: productName,
      searchTerms: generated.searchTerms,
      quantity: valid(generated.quantity),
      unit: cleaned(generated.unit),
      quantityText: cleaned(generated.quantityText),
      fractionOfWhole: validFraction(generated.fractionOfWhole),
      wholeUnit: cleaned(generated.wholeUnit),
      containerSize: valid(generated.containerSize),
      containerSizeUnit: cleaned(generated.containerSizeUnit),
      alternateQuantity: valid(generated.alternateQuantity),
      alternateUnit: cleaned(generated.alternateUnit),
      preparation: cleaned(generated.preparation),
      descriptors: generated.descriptors.compactMap(cleaned),
      isApproximate: generated.isApproximate,
      containsMultipleFoods: generated.containsMultipleFoods,
      ambiguityNotes: cleaned(generated.ambiguityNotes),
      componentNames: generated.componentNames.compactMap(cleaned),
      quantityNeedsClarification: generated.quantityNeedsClarification,
      preparationNeedsClarification: generated.preparationNeedsClarification,
      clarificationPrompt: clarificationPrompt,
      clarificationSuggestions: generated.clarificationSuggestions.compactMap(cleaned)
    )
    var grounded = ParsedFoodRequestGrounder().ground(candidate, in: originalInput)
    // Structural guard: without a food, amount/prep flags are meaningless.
    let hasIdentity = !grounded.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if !hasIdentity {
      grounded.quantityNeedsClarification = false
      grounded.preparationNeedsClarification = false
    }
    let hasPrompt = grounded.clarificationPrompt != nil
    let hasMulti = grounded.containsMultipleFoods && grounded.componentNames.count >= 2
    guard hasIdentity || hasPrompt || hasMulti else {
      throw FoodParserError.invalidResponse
    }
    return grounded
  }

  private func cleaned(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }

  private func valid(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
  }

  private func validFraction(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0, value <= 1 else { return nil }
    return value
  }
}
