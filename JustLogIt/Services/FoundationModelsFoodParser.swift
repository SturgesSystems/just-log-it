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
    description: "Concise product or food name without brand, quantity, or conversational filler.")
  var productName: String

  @Guide(
    description:
      "Concise suggested food database search terms without quantity or conversational filler.")
  var searchTerms: String

  @Guide(description: "Primary numeric quantity after converting written numbers and fractions.")
  var quantity: Double?

  @Guide(description: "Unit for the primary quantity, singular when practical.")
  var unit: String?

  @Guide(description: "Original human-readable quantity phrase.")
  var quantityText: String?

  @Guide(
    description: "Fraction of a whole item when explicitly stated, such as 0.375 for three eighths."
  )
  var fractionOfWhole: Double?

  @Guide(description: "Whole-item unit associated with fractionOfWhole, such as pizza or bottle.")
  var wholeUnit: String?

  @Guide(description: "Explicit full container size, if stated.")
  var containerSize: Double?

  @Guide(description: "Unit for containerSize.")
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

struct FoundationModelsFoodParser: FoodDescriptionParsing {
  func parse(_ input: String) async throws -> ParsedFoodRequest {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw FoodParserError.emptyInput }

    let model = SystemLanguageModel.default
    switch model.availability {
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

    let session = LanguageModelSession(
      model: model,
      tools: [],
      instructions: """
        Parse one principal food description for a USDA database lookup. Separate an explicit brand from the product name. Preserve flavor, crust, variety, cut, product line, preparation, and other lookup-critical descriptors. Convert written numbers and common fractions. Preserve two equivalent quantities when supplied. Never infer a brand, package weight, restaurant size, pizza diameter, serving size, nutrients, or database record. An entire package is not automatically one serving. Mark multiple distinct foods and approximation language. Remove phrases such as 'I ate', meal context, and 'please log' from search terms.
        """
    )
    let options = GenerationOptions(
      samplingMode: .greedy, temperature: 0, maximumResponseTokens: 500)
    let response = try await session.respond(
      to: "Interpret this food description: \(trimmed)",
      generating: GeneratedFoodDescription.self,
      options: options
    )
    let generated = response.content
    let productName = generated.productName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !productName.isEmpty else { throw FoodParserError.invalidResponse }
    return ParsedFoodRequest(
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
