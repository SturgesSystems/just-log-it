import Foundation

// MARK: - Evidence and field metadata

/// Origin of the interpretation draft's evidence.
public enum EvidenceSourceKind: String, Sendable, Equatable, Codable {
  case typedText
  case photoObservation
  case rememberedFood
  case userEdit
}

/// How a field value was obtained. `userConfirmed` is set only by explicit user-confirm APIs.
public enum FieldProvenance: String, Sendable, Equatable, Codable {
  case directlyStated
  case visuallyObserved
  case deterministicDerivation
  case selectedUSDARecord
  case rememberedValue
  case userConfirmed
  case modelProposed
  case unknown
}

/// Field-level confidence. `confirmed` is never derived from model probability —
/// only `ClarificationPolicy.applyUserConfirm` (or equivalent explicit confirm) may set it.
public enum FieldConfidence: String, Sendable, Equatable, Codable {
  case confirmed
  case high
  case uncertain
  case unknown
}

/// Explicit ambiguity codes for policy routing.
public enum AmbiguityCode: String, Sendable, Equatable, Codable {
  case missingQuantity
  case invalidQuantity
  case conflictingUnits
  case multipleFoods
  case uncertainBrand
  case uncertainPreparation
  case hiddenIngredient
  case emptyIdentity
  case noPlausibleIdentity
  case maxTurnsExceeded
}

/// A single field value with provenance and confidence.
public struct FieldFact<Value: Sendable & Equatable>: Sendable, Equatable {
  public var value: Value
  public var provenance: FieldProvenance
  public var confidence: FieldConfidence

  public init(
    value: Value,
    provenance: FieldProvenance,
    confidence: FieldConfidence
  ) {
    self.value = value
    self.provenance = provenance
    self.confidence = confidence
  }

  /// Marks the field as explicitly confirmed by the user.
  public func confirmedByUser() -> FieldFact<Value> {
    FieldFact(value: value, provenance: .userConfirmed, confidence: .confirmed)
  }

  public func mapValue(_ transform: (Value) -> Value) -> FieldFact<Value> {
    FieldFact(value: transform(value), provenance: provenance, confidence: confidence)
  }
}

/// Deterministic validation finding (separate from model confidence).
public struct ValidationFinding: Sendable, Equatable, Codable {
  public var code: AmbiguityCode
  public var message: String
  public var field: String?

  public init(code: AmbiguityCode, message: String, field: String? = nil) {
    self.code = code
    self.message = message
    self.field = field
  }
}

/// A single targeted clarification question for the user.
public struct ClarificationQuestion: Sendable, Equatable, Codable {
  public var code: AmbiguityCode
  public var prompt: String
  public var suggestedAnswers: [String]
  public var allowsFreeform: Bool

  public init(
    code: AmbiguityCode,
    prompt: String,
    suggestedAnswers: [String] = [],
    allowsFreeform: Bool = true
  ) {
    self.code = code
    self.prompt = prompt
    self.suggestedAnswers = suggestedAnswers
    self.allowsFreeform = allowsFreeform
  }

  /// Post-USDA quantity question. UI may still use dedicated servings/grams fields;
  /// suggestions are optional shortcuts that resolve to those fields.
  public static func quantity(
    explanation: String,
    householdServing: String? = nil,
    servingSizeGrams: Double? = nil,
    code: AmbiguityCode = .missingQuantity
  ) -> ClarificationQuestion {
    var suggestions: [String] = []
    if householdServing != nil || servingSizeGrams != nil {
      suggestions.append("1 serving")
    }
    if let grams = servingSizeGrams, grams.isFinite, grams > 0 {
      let rounded = grams.rounded()
      if abs(rounded - grams) < 0.05 {
        suggestions.append("\(Int(rounded)) g")
      } else {
        suggestions.append(String(format: "%.1f g", grams))
      }
    }
    if !suggestions.contains("100 g") {
      suggestions.append("100 g")
    }
    return ClarificationQuestion(
      code: code,
      prompt: explanation,
      suggestedAnswers: suggestions,
      allowsFreeform: true
    )
  }
}

/// Policy outcome for a draft before USDA lookup or nutrition work.
public enum ClarificationDecision: Sendable, Equatable {
  case proceed(ParsedFoodRequest)
  /// Multi-food meal: look up each component, then save one composite entry.
  case beginComposite(componentNames: [String], sourceText: String)
  case clarify(ClarificationQuestion)
  case requireEdit(String)
  case fallbackManual(String)
}

// MARK: - Draft

/// Transient interpretation draft used by the clarification engine.
/// Not persisted as a food-log entry.
public struct FoodInterpretationDraft: Sendable, Equatable {
  public var sourceText: String
  public var evidenceKind: EvidenceSourceKind
  public var turnCount: Int

  public var productName: FieldFact<String>
  public var brand: FieldFact<String>?
  public var searchTerms: String
  public var quantity: FieldFact<Double>?
  public var unit: FieldFact<String>?
  public var quantityText: FieldFact<String>?
  public var fractionOfWhole: FieldFact<Double>?
  public var wholeUnit: FieldFact<String>?
  public var containerSize: FieldFact<Double>?
  public var containerSizeUnit: FieldFact<String>?
  public var alternateQuantity: FieldFact<Double>?
  public var alternateUnit: FieldFact<String>?
  public var preparation: FieldFact<String>?
  public var descriptors: FieldFact<[String]>
  public var isApproximate: Bool
  public var containsMultipleFoods: Bool
  public var multipleFoodAssessment: MultipleFoodAssessment?
  public var ambiguityNotes: String?
  public var componentNames: [String]
  /// Copied from model output; soft clarify uses `clarificationPrompt` only.
  public var quantityNeedsClarification: Bool
  public var preparationNeedsClarification: Bool
  public var clarificationPrompt: String?
  public var clarificationSuggestions: [String]

  public var findings: [ValidationFinding]
  public var ambiguities: [AmbiguityCode]

  public init(
    sourceText: String = "",
    evidenceKind: EvidenceSourceKind = .typedText,
    turnCount: Int = 0,
    productName: FieldFact<String>,
    brand: FieldFact<String>? = nil,
    searchTerms: String = "",
    quantity: FieldFact<Double>? = nil,
    unit: FieldFact<String>? = nil,
    quantityText: FieldFact<String>? = nil,
    fractionOfWhole: FieldFact<Double>? = nil,
    wholeUnit: FieldFact<String>? = nil,
    containerSize: FieldFact<Double>? = nil,
    containerSizeUnit: FieldFact<String>? = nil,
    alternateQuantity: FieldFact<Double>? = nil,
    alternateUnit: FieldFact<String>? = nil,
    preparation: FieldFact<String>? = nil,
    descriptors: FieldFact<[String]> = FieldFact(
      value: [], provenance: .unknown, confidence: .unknown),
    isApproximate: Bool = false,
    containsMultipleFoods: Bool = false,
    multipleFoodAssessment: MultipleFoodAssessment? = nil,
    ambiguityNotes: String? = nil,
    componentNames: [String] = [],
    quantityNeedsClarification: Bool = false,
    preparationNeedsClarification: Bool = false,
    clarificationPrompt: String? = nil,
    clarificationSuggestions: [String] = [],
    findings: [ValidationFinding] = [],
    ambiguities: [AmbiguityCode] = []
  ) {
    self.sourceText = sourceText
    self.evidenceKind = evidenceKind
    self.turnCount = turnCount
    self.productName = productName
    self.brand = brand
    self.searchTerms = searchTerms
    self.quantity = quantity
    self.unit = unit
    self.quantityText = quantityText
    self.fractionOfWhole = fractionOfWhole
    self.wholeUnit = wholeUnit
    self.containerSize = containerSize
    self.containerSizeUnit = containerSizeUnit
    self.alternateQuantity = alternateQuantity
    self.alternateUnit = alternateUnit
    self.preparation = preparation
    self.descriptors = descriptors
    self.isApproximate = isApproximate
    self.containsMultipleFoods = containsMultipleFoods
    self.multipleFoodAssessment = multipleFoodAssessment
    self.ambiguityNotes = ambiguityNotes
    self.componentNames = componentNames
    self.quantityNeedsClarification = quantityNeedsClarification
    self.preparationNeedsClarification = preparationNeedsClarification
    self.clarificationPrompt = clarificationPrompt
    self.clarificationSuggestions = clarificationSuggestions
    self.findings = findings
    self.ambiguities = ambiguities
  }

  /// Nonempty trimmed product name is required before USDA search.
  public var hasIdentity: Bool {
    !trimmedIdentity.isEmpty
  }

  public var trimmedIdentity: String {
    productName.value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// True when a quantity+unit pair or a fraction/container fact remains after validation.
  public var hasUsableQuantity: Bool {
    if quantity != nil, unit != nil { return true }
    if fractionOfWhole != nil { return true }
    return false
  }

  /// Material issues that block safe USDA selection or require user resolution before proceed.
  ///
  /// Note: `missingQuantity` alone is intentionally **not** material pre-USDA.
  /// The current app resolves quantity after USDA selection via `ServingResolution`.
  public var materialAmbiguities: [AmbiguityCode] {
    ambiguities.filter { code in
      switch code {
      case .emptyIdentity, .noPlausibleIdentity, .multipleFoods, .maxTurnsExceeded:
        return true
      case .invalidQuantity, .conflictingUnits:
        // Residual invalid quantities after strip are still material if present.
        return findings.contains { $0.code == code }
      case .missingQuantity, .uncertainBrand, .uncertainPreparation, .hiddenIngredient:
        return false
      }
    }
  }

  /// Builds a `ParsedFoodRequest` for USDA search / downstream resolution.
  /// Search terms fall back to product name when empty.
  public func toParsedFoodRequest() -> ParsedFoodRequest {
    let name = trimmedIdentity
    let trimmedSearch = searchTerms.trimmingCharacters(in: .whitespacesAndNewlines)
    return ParsedFoodRequest(
      brand: brand.map(\.value),
      productName: name,
      searchTerms: trimmedSearch.isEmpty ? name : trimmedSearch,
      quantity: quantity?.value,
      unit: unit?.value,
      quantityText: quantityText?.value,
      fractionOfWhole: fractionOfWhole?.value,
      wholeUnit: wholeUnit?.value,
      containerSize: containerSize?.value,
      containerSizeUnit: containerSizeUnit?.value,
      alternateQuantity: alternateQuantity?.value,
      alternateUnit: alternateUnit?.value,
      preparation: preparation?.value,
      descriptors: descriptors.value,
      isApproximate: isApproximate,
      containsMultipleFoods: containsMultipleFoods,
      multipleFoodAssessment: multipleFoodAssessment,
      ambiguityNotes: ambiguityNotes,
      componentNames: componentNames,
      quantityNeedsClarification: quantityNeedsClarification,
      preparationNeedsClarification: preparationNeedsClarification,
      clarificationPrompt: clarificationPrompt,
      clarificationSuggestions: clarificationSuggestions
    )
  }

  /// Non-empty model-authored clarification question, if any.
  public var modelClarificationPrompt: String? {
    let trimmed = clarificationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
