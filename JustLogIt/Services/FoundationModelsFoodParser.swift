import Foundation
import FoundationModels
import JustLogItCore

#if DEBUG
  import OSLog
#endif

#if DEBUG
  enum AppPerformanceTrace {
    private static let logger = Logger(
      subsystem: Bundle.main.bundleIdentifier ?? "JustLogIt",
      category: "Performance"
    )
    private static let signposter = OSSignposter(logger: logger)

    static func measure<Value>(
      _ name: StaticString,
      operation: () throws -> Value
    ) rethrows -> Value {
      let started = ContinuousClock.now
      let state = signposter.beginInterval(name)
      do {
        let value = try operation()
        finish(name, state: state, started: started, outcome: "success")
        return value
      } catch {
        finish(name, state: state, started: started, outcome: "failure")
        throw error
      }
    }

    static func measure<Value>(
      _ name: StaticString,
      isolation: isolated (any Actor)? = #isolation,
      operation: () async throws -> Value
    ) async rethrows -> Value {
      let started = ContinuousClock.now
      let state = signposter.beginInterval(name)
      do {
        let value = try await operation()
        finish(name, state: state, started: started, outcome: "success")
        return value
      } catch {
        finish(name, state: state, started: started, outcome: "failure")
        throw error
      }
    }

    private static func finish(
      _ name: StaticString,
      state: OSSignpostIntervalState,
      started: ContinuousClock.Instant,
      outcome: StaticString
    ) {
      signposter.endInterval(name, state)
      let components = started.duration(to: .now).components
      let milliseconds =
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
      logger.debug(
        "\(String(describing: name), privacy: .public) duration_ms=\(milliseconds, privacy: .public) outcome=\(String(describing: outcome), privacy: .public)"
      )
    }
  }
#endif

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
    description: "Concise product or food name without brand, quantity, or conversational filler.")
  var productName: String

  @Guide(
    description:
      "Concise suggested food database search terms without quantity or conversational filler.")
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
      "Lookup descriptors such as flavor, crust type, variety, cut, size, fat percentage, or product line."
  )
  var descriptors: [String]

  @Guide(
    description:
      "True only when wording includes about, around, roughly, almost, or another approximation.")
  var isApproximate: Bool

  @Guide(
    description:
      "True when the input names more than one distinct food that would require separate database records."
  )
  var containsMultipleFoods: Bool

  @Guide(description: "Short note describing material ambiguity. Do not invent certainty.")
  var ambiguityNotes: String?
}

enum FoundationModelsPromptProfile: String, CaseIterable, Sendable {
  case production
  case leanCandidate

  var instructions: String {
    switch self {
    case .production:
      """
      Parse one principal food description for a USDA database lookup. Separate an explicit brand from the product name. Preserve flavor, crust, variety, cut, product line, preparation, and other lookup-critical descriptors. Convert written numbers and common fractions. Preserve two equivalent quantities when supplied. When a person eats a fraction of a container with an explicit full size, keep the fraction and full container size separate: for "half a 12-ounce bottle", fractionOfWhole is 0.5, wholeUnit is bottle, containerSize is 12, and containerSizeUnit is ounce; the consumed amount is 6 ounces, never 0.5 ounce. Never infer a brand, package weight, restaurant size, pizza diameter, serving size, nutrients, or database record. An entire package is not automatically one serving. Mark multiple distinct foods and approximation language. Remove phrases such as 'I ate', meal context, and 'please log' from search terms.
      """
    case .leanCandidate:
      """
      Extract one principal food for USDA lookup using only facts explicitly present in the current message. Separate brand, food, preparation, descriptors, and quantity. Convert written numbers and fractions. Keep a fraction of a sized container as fraction, whole unit, container size, and container unit. Never invent food, brand, quantity, serving, package, ingredient, nutrition, or prior-message context. Mark multiple foods and approximation wording.
      """
    }
  }
}

struct FoundationModelsFoodParser: FoodDescriptionParsing {
  private let promptProfile: FoundationModelsPromptProfile

  init(promptProfile: FoundationModelsPromptProfile = .production) {
    self.promptProfile = promptProfile
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw FoodParserError.emptyInput }

    let model = SystemLanguageModel.default
    #if DEBUG
      let availability = AppPerformanceTrace.measure("FM availability") { model.availability }
    #else
      let availability = model.availability
    #endif
    switch availability {
    case .available:
      break
    case .unavailable(.deviceNotEligible):
      throw FoodParserError.unavailable(
        "Apple Intelligence is not supported on this device. Search manually instead.")
    case .unavailable(.appleIntelligenceNotEnabled):
      throw FoodParserError.unavailable(
        "Apple Intelligence is turned off. Enable it in Settings or search manually.")
    case .unavailable(.modelNotReady):
      throw FoodParserError.unavailable(
        "The on-device language model is not ready yet. Search manually while it finishes preparing."
      )
    case .unavailable:
      throw FoodParserError.unavailable(
        "The on-device language model is unavailable. Search manually instead.")
    }

    #if DEBUG
      let session = AppPerformanceTrace.measure("FM session creation") {
        makeSession(model: model)
      }
    #else
      let session = makeSession(model: model)
    #endif
    let options = GenerationOptions(
      samplingMode: .greedy, temperature: 0, maximumResponseTokens: 500)
    #if DEBUG
      let response = try await AppPerformanceTrace.measure("FM respond") {
        try await session.respond(
          to: "Interpret this food description: \(trimmed)",
          generating: GeneratedFoodDescription.self,
          options: options
        )
      }
    #else
      let response = try await session.respond(
        to: "Interpret this food description: \(trimmed)",
        generating: GeneratedFoodDescription.self,
        options: options
      )
    #endif
    let generated = response.content
    #if DEBUG
      return try AppPerformanceTrace.measure("FM mapping") {
        try map(generated, originalInput: trimmed)
      }
    #else
      return try map(generated, originalInput: trimmed)
    #endif
  }

  private func makeSession(model: SystemLanguageModel) -> LanguageModelSession {
    LanguageModelSession(
      model: model,
      tools: [],
      instructions: promptProfile.instructions
    )
  }

  private func map(
    _ generated: GeneratedFoodDescription,
    originalInput: String
  ) throws -> ParsedFoodRequest {
    let productName = generated.productName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !productName.isEmpty else { throw FoodParserError.invalidResponse }
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
      ambiguityNotes: cleaned(generated.ambiguityNotes)
    )
    let grounded = ParsedFoodRequestGrounder().ground(candidate, in: originalInput)
    guard !grounded.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

struct MockFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    if ProcessInfo.processInfo.arguments.contains("-ui-testing-parser-failure") {
      throw FoodParserError.invalidResponse
    }
    return ParsedFoodRequest(productName: input, searchTerms: input, quantity: 1, unit: "serving")
  }
}
