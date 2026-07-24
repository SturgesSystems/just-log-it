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

@available(macOS 27.0, *)
struct EvaluatorSemanticProposalResult: Sendable {
  let proposal: SemanticFoodProposal
  let usage: MacFoundationModelsFoodParser.UsageMetrics
  let generationLatencyMilliseconds: Double
  let prewarmLatencyMilliseconds: Double?
}

/// Evaluator-only capability that preserves the Core proposer seam while exposing measurements
/// needed to compare cold and genuinely prewarmed semantic inference.
protocol EvaluatorSemanticFoodProposing: SemanticFoodProposing {
  func proposeWithMetrics(
    _ input: SemanticFoodProposalInput,
    warmState: ParserEvaluationWarmState
  ) async throws -> EvaluatorSemanticProposalResult
}

struct MacFoundationModelsSemanticFoodProposer: EvaluatorSemanticFoodProposing, Sendable {

  // SEMANTIC-PARITY-PROMPT-BEGIN
  enum PromptProfile: String, CaseIterable, Sendable {
    case minimal

    var instructions: String {
      """
      Identify food facts explicitly supported by the user's current facts. Return only food identity, explicit brand or restaurant, preparation, lookup descriptors, whether distinct foods require separate lookups, and their short component names.

      Do not extract quantities, units, fractions, containers, serving sizes, nutrition, USDA queries, confidence, ambiguity notes, clarification questions, or suggested replies. Never invent a food or brand. A named dish is one food even if it has ingredients. Separate independent foods such as cereal with milk or eggs and toast. Assistant-authored context helps interpret a reply but is not evidence for any returned fact.
      """
    }
  }
  // SEMANTIC-PARITY-PROMPT-END

  static let promptPrefix = "Interpret the current food facts:\n"

  private let promptProfile: PromptProfile
  private let modelUseCase: MacFoundationModelsFoodParser.ModelUseCase
  private let reasoningPolicy: MacFoundationModelsFoodParser.ReasoningPolicy

  init(
    promptProfile: PromptProfile = .minimal,
    modelUseCase: MacFoundationModelsFoodParser.ModelUseCase = .general,
    reasoningPolicy: MacFoundationModelsFoodParser.ReasoningPolicy = .capabilityAwareLight
  ) {
    self.promptProfile = promptProfile
    self.modelUseCase = modelUseCase
    self.reasoningPolicy = reasoningPolicy
  }

  func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
    try await proposeWithMetrics(input, warmState: .cold).proposal
  }

  func proposeWithMetrics(
    _ input: SemanticFoodProposalInput,
    warmState: ParserEvaluationWarmState
  ) async throws -> EvaluatorSemanticProposalResult {
    let context = input.semanticContext.trimmingCharacters(in: .whitespacesAndNewlines)
    let grounding = input.groundingText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !context.isEmpty, !grounding.isEmpty else {
      throw SemanticFoodProposalError.invalidResponse
    }

    let model = SystemLanguageModel(useCase: modelUseCase.systemUseCase)
    guard case .available = model.availability else {
      throw SemanticFoodProposalError.unavailable
    }
    let session = LanguageModelSession(
      model: model,
      tools: [],
      instructions: promptProfile.instructions
    )
    let prewarmLatencyMilliseconds: Double?
    if warmState == .prewarmed {
      let started = ContinuousClock.now
      session.prewarm(promptPrefix: Prompt(Self.promptPrefix))
      prewarmLatencyMilliseconds = started.duration(to: .now).evaluationMilliseconds
    } else {
      prewarmLatencyMilliseconds = nil
    }
    let prompt = """
      \(Self.promptPrefix)USER FACTS (the only grounding evidence):
      \(grounding)

      BOUNDED CONTEXT (interpretation only; never copy assistant wording as fact):
      \(context)
      """
    do {
      let started = ContinuousClock.now
      let response = try await session.respond(
        to: prompt,
        generating: GeneratedSemanticFoodProposal.self,
        options: .init(samplingMode: .greedy, temperature: 0, maximumResponseTokens: 192),
        contextOptions: MacFoundationModelsFoodParser.contextOptions(
          supportsReasoning: model.capabilities.contains(.reasoning),
          reasoningPolicy: reasoningPolicy
        )
      )
      let latency = started.duration(to: .now).evaluationMilliseconds
      try Task.checkCancellation()
      let generated = response.content
      return EvaluatorSemanticProposalResult(
        proposal: .init(
          productName: generated.productName,
          brand: generated.brand,
          preparation: generated.preparation,
          descriptors: generated.descriptors,
          containsMultipleFoods: generated.containsMultipleFoods,
          componentNames: generated.componentNames
        ),
        usage: .init(
          inputTokenCount: .init(response.usage.input.totalTokenCount),
          cachedInputTokenCount: .init(response.usage.input.cachedTokenCount),
          outputTokenCount: .init(response.usage.output.totalTokenCount),
          reasoningTokenCount: .init(response.usage.output.reasoningTokenCount),
          totalTokenCount: .init(response.usage.totalTokenCount)
        ),
        generationLatencyMilliseconds: latency,
        prewarmLatencyMilliseconds: prewarmLatencyMilliseconds
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw SemanticFoodProposalError.invalidResponse
    }
  }
}

extension Duration {
  fileprivate var evaluationMilliseconds: Double {
    let components = self.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
