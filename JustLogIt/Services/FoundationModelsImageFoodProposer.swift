import CoreGraphics
import Foundation
import ImageIO
import JustLogItCore

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// On-device photo → structured food identity proposal.
///
/// Nutrition numbers are never produced. Quantity/brand are only taken from an
/// explicit user caption or clearly visible packaging text — never invented from pixels alone.
struct FoundationModelsImageFoodProposer: Sendable {
  func propose(imageData: Data, caption: String? = nil) async throws -> ParsedFoodRequest {
    #if canImport(FoundationModels)
      return try await proposeWithFoundationModels(imageData: imageData, caption: caption)
    #else
      throw FoodParserError.unavailable(
        "On-device photo identification requires Foundation Models. Describe the food in text instead."
      )
    #endif
  }

  func propose(cgImage: CGImage, caption: String? = nil) async throws -> ParsedFoodRequest {
    #if canImport(FoundationModels)
      return try await proposeWithFoundationModels(cgImage: cgImage, caption: caption)
    #else
      throw FoodParserError.unavailable(
        "On-device photo identification requires Foundation Models. Describe the food in text instead."
      )
    #endif
  }
}

#if canImport(FoundationModels)

  @Generable(
    description:
      "Visible food identity for database lookup from a photo and optional caption. Never contains nutrition facts, calories, or invented weights.",
    representNilExplicitlyInGeneratedContent: true
  )
  private struct GeneratedFoodImageProposal {
    @Guide(
      description:
        "Concise principal food or dish name visible in the photo. No brand, quantity, or conversational filler unless printed on packaging or stated in the caption."
    )
    var productName: String

    @Guide(
      description:
        "Concise USDA search terms derived only from visible food and caption facts. No quantity or nutrition."
    )
    var searchTerms: String

    @Guide(
      description:
        "Brand only when clearly printed on packaging in the photo or explicitly named in the caption. Never invent a brand."
    )
    var brand: String?

    @Guide(
      description:
        "Preparation only when visibly obvious or stated in the caption, such as fried, grilled, raw, or scrambled. Never invent cooking fat or hidden ingredients."
    )
    var preparation: String?

    @Guide(
      description:
        "Visible lookup descriptors such as flavor cues, crust, variety, or cut that appear in the photo or caption. Do not invent hidden sauces or fillings."
    )
    var descriptors: [String]

    @Guide(
      description:
        "Amount only when the optional caption explicitly states a quantity. Never estimate mass, servings, or package size from appearance alone."
    )
    var quantity: Double?

    @Guide(
      description:
        "Unit for quantity only when the caption explicitly states one. Never invent grams, ounces, or servings from the photo."
    )
    var unit: String?

    @Guide(description: "Original quantity phrase from the caption only, when present.")
    var quantityText: String?

    @Guide(
      description:
        "True when the photo clearly shows more than one distinct food that would require separate database records."
    )
    var containsMultipleFoods: Bool

    @Guide(
      description:
        "Short note on material ambiguity (hidden ingredients, unclear identity, mixed plate). Do not invent certainty."
    )
    var ambiguityNotes: String?
  }

  extension FoundationModelsImageFoodProposer {
    fileprivate func proposeWithFoundationModels(
      imageData: Data,
      caption: String?
    ) async throws -> ParsedFoodRequest {
      guard let cgImage = Self.makeCGImage(from: imageData) else {
        throw FoodParserError.invalidResponse
      }
      return try await proposeWithFoundationModels(cgImage: cgImage, caption: caption)
    }

    fileprivate func proposeWithFoundationModels(
      cgImage: CGImage,
      caption: String?
    ) async throws -> ParsedFoodRequest {
      let model = SystemLanguageModel.default
      switch model.availability {
      case .available:
        break
      case .unavailable(.deviceNotEligible):
        throw FoodParserError.unavailable(
          "Apple Intelligence is not supported on this device. Describe the food in text instead.")
      case .unavailable(.appleIntelligenceNotEnabled):
        throw FoodParserError.unavailable(
          "Apple Intelligence is turned off. Enable it in Settings or describe the food in text.")
      case .unavailable(.modelNotReady):
        throw FoodParserError.unavailable(
          "The on-device language model is not ready yet. Describe the food in text while it finishes preparing."
        )
      case .unavailable:
        throw FoodParserError.unavailable(
          "On-device photo identification is unavailable. Describe the food in text instead.")
      }

      let session = LanguageModelSession(
        model: model,
        tools: [],
        instructions: """
          Identify the principal visible food in a photo for USDA FoodData Central lookup. \
          Output only identity and lookup descriptors supported by the image or an optional user caption. \
          Never invent calories, nutrients, serving size, package weight, brand, cooking fat, sauces, or hidden ingredients. \
          Never estimate quantity from appearance; only copy an amount explicitly present in the caption. \
          Mark multiple distinct foods. Prefer a short product name and search terms suitable for a food database. \
          When identity is unclear, set ambiguityNotes and still propose the best visible principal food.
          """
      )

      let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
      let hasCaption = !(trimmedCaption?.isEmpty ?? true)
      let options = GenerationOptions(
        samplingMode: .greedy, temperature: 0, maximumResponseTokens: 400)

      let response = try await session.respond(
        generating: GeneratedFoodImageProposal.self,
        options: options
      ) {
        "Identify the principal visible food for database lookup. Never invent nutrition numbers or quantities from appearance alone."
        if hasCaption, let trimmedCaption {
          "User caption (explicit facts only; caption may override image-only guesses): \(trimmedCaption)"
        }
        Attachment(cgImage).label("User-selected food photo")
      }

      return try map(response.content, caption: hasCaption ? trimmedCaption : nil)
    }

    private func map(
      _ generated: GeneratedFoodImageProposal,
      caption: String?
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
        preparation: cleaned(generated.preparation),
        descriptors: generated.descriptors.compactMap(cleaned),
        isApproximate: true,
        containsMultipleFoods: generated.containsMultipleFoods,
        ambiguityNotes: cleaned(generated.ambiguityNotes)
      )

      // Ground only when a caption provides textual evidence; pure photo proposals skip text grounding.
      if let caption, !caption.isEmpty {
        let grounded = ParsedFoodRequestGrounder().ground(candidate, in: caption)
        guard !grounded.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw FoodParserError.invalidResponse
        }
        return grounded
      }
      return candidate
    }

    private func cleaned(_ value: String?) -> String? {
      guard let value else { return nil }
      let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return result.isEmpty ? nil : result
    }

    private func cleaned(_ value: String) -> String? {
      cleaned(Optional(value))
    }

    private func valid(_ value: Double?) -> Double? {
      guard let value, value.isFinite, value > 0 else { return nil }
      return value
    }

    fileprivate static func makeCGImage(from data: Data) -> CGImage? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
  }

#endif
