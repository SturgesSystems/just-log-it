import Foundation
import FoundationModels
import JustLogItCore

/// Mac-side copy of the app's Foundation Models food parser for evaluation.
/// Uses the same production instructions, greedy sampling, and source grounding.
@available(macOS 26.4, *)
struct MacFoundationModelsFoodParser: FoodDescriptionParsing, Sendable {
  enum ParseError: Error, CustomStringConvertible {
    case emptyInput
    case unavailable(String)
    case invalidResponse

    var description: String {
      switch self {
      case .emptyInput: "Empty input"
      case .unavailable(let reason): reason
      case .invalidResponse: "Model returned an incomplete food description"
      }
    }
  }

  @Generable(
    description:
      "A structured interpretation of one principal food description for database lookup. Never contains nutrition facts or a database selection.",
    representNilExplicitlyInGeneratedContent: true
  )
  struct GeneratedFoodDescription {
    @Guide(description: "Brand or restaurant explicitly stated by the person. Never infer one.")
    var brand: String?

    @Guide(
      description: "Concise product or food name without brand, quantity, or conversational filler."
    )
    var productName: String

    @Guide(
      description:
        "Concise suggested food database search terms without quantity or conversational filler."
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
      description:
        "Fraction of a whole item when explicitly stated, such as 0.375 for three eighths."
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
        "Preparation state that materially changes lookup, such as cooked, raw, fried, or scrambled."
    )
    var preparation: String?

    @Guide(
      description:
        "Lookup descriptors such as flavor, crust type, variety, cut, size, fat percentage, or product line."
    )
    var descriptors: [String]

    @Guide(
      description:
        "True when wording includes about, around, roughly, almost, a few, some, several, a couple, a handful, or another approximation."
    )
    var isApproximate: Bool

    @Guide(
      description:
        "True when the input names more than one distinct food that should each get its own USDA lookup (e.g. cereal with milk)."
    )
    var containsMultipleFoods: Bool

    @Guide(
      description:
        "When containsMultipleFoods is true, list each distinct food (e.g. cereal, milk). Empty when single food."
    )
    var componentNames: [String]

    @Guide(description: "Short internal note on material ambiguity. Not shown to the user.")
    var ambiguityNotes: String?

    @Guide(
      description:
        "True only when a real food is already identified AND the person did not state a concrete amount (or only said a few/some/several). False when productName is empty."
    )
    var quantityNeedsClarification: Bool

    @Guide(
      description:
        "True only when a real food is already identified AND preparation was not stated but would change lookup. False when productName is empty."
    )
    var preparationNeedsClarification: Bool

    @Guide(
      description:
        """
        One natural chat question (single sentence, no slash alternatives). Empty only when ready for search.
        Priority (first only): (1) no food → ask only for the food name (never prep/amount); (2) multiple foods → which one; (3) amount; (4) prep.
        """
    )
    var clarificationPrompt: String?

    @Guide(
      description:
        "Optional short answer chips (0–4), never questions. When productName is empty: must be empty array. When food known: e.g. '2 scrambled'."
    )
    var clarificationSuggestions: [String]
  }

  /// Same production instruction text as the iOS app.
  static let productionInstructions = """
    You are the food-log interpreter. Output structured fields for one principal food for a USDA database lookup, plus optional soft clarification for the user.

    Facts only: never invent brand, package weight, restaurant size, pizza diameter, serving size, nutrients, or a database record. Never invent a food name. Convert written numbers and fractions. For a fraction of a sized container (e.g. half a 12-ounce bottle), keep fractionOfWhole, wholeUnit, containerSize, and containerSizeUnit separate. An entire package is not automatically one serving. Strip 'I ate', mealtime, and 'please log' from search terms.

    Identity first: productName must be a real food/product. If the message is only praise, vagueness, dismissal, or non-food chatter ("something yummy", "delicious", "who cares?", "idk", "whatever", "n/a", "a snack", "leftovers"), leave productName and searchTerms empty. Do not set quantityNeedsClarification or preparationNeedsClarification until a real food is known.

    Soft clarification: one natural chat question, first gap only. (1) no food → ask only for the food name; clarificationSuggestions empty; (2) multiple foods → which one; (3) vague amount (a few/some) → how many; written counts like "three" are concrete; (4) prep that changes USDA match and is missing (e.g. eggs without scrambled/fried/boiled) → how cooked, with cook-method chips. Never slash-style prompts or status phrases. Leave clarificationPrompt empty only when ready for search.

    Conversation replies: merge user reply into interpretation. Dismissive/non-food replies are not productNames — ask again for the food.
    """

  static var isAvailable: Bool {
    if case .available = SystemLanguageModel.default.availability {
      return true
    }
    return false
  }

  static var availabilityDescription: String {
    switch SystemLanguageModel.default.availability {
    case .available:
      return "available"
    case .unavailable(.deviceNotEligible):
      return "deviceNotEligible"
    case .unavailable(.appleIntelligenceNotEnabled):
      return "appleIntelligenceNotEnabled"
    case .unavailable(.modelNotReady):
      return "modelNotReady"
    case .unavailable(let other):
      return "unavailable(\(other))"
    }
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ParseError.emptyInput }

    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
      break
    case .unavailable(.deviceNotEligible):
      throw ParseError.unavailable("Apple Intelligence is not supported on this Mac.")
    case .unavailable(.appleIntelligenceNotEnabled):
      throw ParseError.unavailable("Apple Intelligence is turned off on this Mac.")
    case .unavailable(.modelNotReady):
      throw ParseError.unavailable("The on-device language model is not ready yet.")
    case .unavailable:
      throw ParseError.unavailable("The on-device language model is unavailable.")
    }

    let session = LanguageModelSession(
      model: model,
      tools: [],
      instructions: Self.productionInstructions
    )
    let options = GenerationOptions(
      samplingMode: .greedy, temperature: 0, maximumResponseTokens: 500)
    let response = try await session.respond(
      to: "Interpret this food description: \(trimmed)",
      generating: GeneratedFoodDescription.self,
      options: options
    )
    return try map(response.content, originalInput: trimmed)
  }

  private func map(
    _ generated: GeneratedFoodDescription,
    originalInput: String
  ) throws -> ParsedFoodRequest {
    let productName = generated.productName.trimmingCharacters(in: .whitespacesAndNewlines)
    let clarificationPrompt = cleaned(generated.clarificationPrompt)
    if productName.isEmpty, clarificationPrompt == nil {
      throw ParseError.invalidResponse
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
    let hasIdentity = !grounded.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if !hasIdentity {
      grounded.quantityNeedsClarification = false
      grounded.preparationNeedsClarification = false
    }
    let hasPrompt = grounded.clarificationPrompt != nil
    let hasMulti = grounded.containsMultipleFoods && grounded.componentNames.count >= 2
    guard hasIdentity || hasPrompt || hasMulti else {
      throw ParseError.invalidResponse
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
