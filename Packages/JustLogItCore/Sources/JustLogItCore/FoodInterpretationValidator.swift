import Foundation

/// Builds and validates `FoodInterpretationDraft` values from grounded parse output.
///
/// The model may propose; this type only applies deterministic checks (finiteness,
/// positivity, empty identity, multiple foods). It never sets `FieldConfidence.confirmed`.
public struct FoodInterpretationValidator: Sendable {
  public init() {}

  /// Constructs a draft from a (preferably grounded) `ParsedFoodRequest`.
  ///
  /// - Parameters:
  ///   - parsed: Candidate parse, ideally after `ParsedFoodRequestGrounder`.
  ///   - sourceText: Original user evidence text (for provenance context).
  ///   - evidenceKind: How the evidence was obtained.
  ///   - turnCount: Clarification turns already taken for this draft.
  public func draft(
    from parsed: ParsedFoodRequest,
    sourceText: String = "",
    evidenceKind: EvidenceSourceKind = .typedText,
    turnCount: Int = 0
  ) -> FoodInterpretationDraft {
    let provenance = Self.defaultProvenance(for: evidenceKind)
    let confidence = Self.defaultConfidence(for: evidenceKind)

    func fact<T>(_ value: T) -> FieldFact<T> {
      FieldFact(value: value, provenance: provenance, confidence: confidence)
    }

    func optionalFact<T>(_ value: T?) -> FieldFact<T>? {
      guard let value else { return nil }
      return fact(value)
    }

    var draft = FoodInterpretationDraft(
      sourceText: sourceText,
      evidenceKind: evidenceKind,
      turnCount: turnCount,
      productName: fact(parsed.productName),
      brand: optionalFact(parsed.brand),
      searchTerms: parsed.searchTerms,
      quantity: optionalFact(parsed.quantity),
      unit: optionalFact(parsed.unit),
      quantityText: optionalFact(parsed.quantityText),
      fractionOfWhole: optionalFact(parsed.fractionOfWhole),
      wholeUnit: optionalFact(parsed.wholeUnit),
      containerSize: optionalFact(parsed.containerSize),
      containerSizeUnit: optionalFact(parsed.containerSizeUnit),
      alternateQuantity: optionalFact(parsed.alternateQuantity),
      alternateUnit: optionalFact(parsed.alternateUnit),
      preparation: optionalFact(parsed.preparation),
      descriptors: fact(parsed.descriptors),
      isApproximate: parsed.isApproximate,
      containsMultipleFoods: parsed.containsMultipleFoods,
      multipleFoodAssessment: parsed.multipleFoodAssessment,
      ambiguityNotes: parsed.ambiguityNotes,
      componentNames: parsed.componentNames,
      quantityNeedsClarification: parsed.quantityNeedsClarification,
      preparationNeedsClarification: parsed.preparationNeedsClarification,
      clarificationPrompt: parsed.clarificationPrompt,
      clarificationSuggestions: parsed.clarificationSuggestions
    )

    // Grounded nonempty product identity is high when directly stated (post-grounding).
    // Never assign `.confirmed` here — only ClarificationPolicy.applyUserConfirm may.
    if draft.hasIdentity, evidenceKind == .typedText || evidenceKind == .userEdit {
      draft.productName = FieldFact(
        value: draft.trimmedIdentity,
        provenance: evidenceKind == .userEdit ? .userConfirmed : .directlyStated,
        confidence: .high
      )
    }

    return validate(draft)
  }

  /// Recomputes quantity stripping and ambiguity/findings for an existing draft.
  public func validate(_ draft: FoodInterpretationDraft) -> FoodInterpretationDraft {
    var result = draft
    var findings: [ValidationFinding] = []
    var ambiguities: [AmbiguityCode] = []

    // Identity
    if !result.hasIdentity {
      let finding = ValidationFinding(
        code: .emptyIdentity,
        message: "Food identity is empty; provide a product name before USDA search.",
        field: "productName"
      )
      findings.append(finding)
      ambiguities.append(.emptyIdentity)
    }

    // Multiple foods block silent proceed.
    if result.containsMultipleFoods {
      let finding = ValidationFinding(
        code: .multipleFoods,
        message: "Input appears to describe more than one food.",
        field: "containsMultipleFoods"
      )
      findings.append(finding)
      ambiguities.append(.multipleFoods)
    }

    // Quantity: strip nonfinite / non-positive values; fraction must be in (0, 1].
    if let quantityFact = result.quantity {
      if !Self.isValidPositiveFinite(quantityFact.value) {
        findings.append(
          ValidationFinding(
            code: .invalidQuantity,
            message: "Quantity must be a positive finite number.",
            field: "quantity"
          )
        )
        ambiguities.append(.invalidQuantity)
        result.quantity = nil
        // Paired unit is unusable without quantity.
        result.unit = nil
      }
    }

    if let unitFact = result.unit {
      let trimmed = unitFact.value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        result.unit = nil
      } else if unitFact.value != trimmed {
        result.unit = FieldFact(
          value: trimmed, provenance: unitFact.provenance, confidence: unitFact.confidence)
      }
    }

    // Quantity without unit (or unit without quantity) is not a usable pair;
    // leave values if only one side remains after other checks, but treat as missing usable quantity.
    if let fractionFact = result.fractionOfWhole {
      if !Self.isValidFraction(fractionFact.value) {
        findings.append(
          ValidationFinding(
            code: .invalidQuantity,
            message: "Fraction of whole must be in (0, 1].",
            field: "fractionOfWhole"
          )
        )
        if !ambiguities.contains(.invalidQuantity) {
          ambiguities.append(.invalidQuantity)
        }
        result.fractionOfWhole = nil
        result.wholeUnit = nil
      }
    }

    if let containerFact = result.containerSize {
      if !Self.isValidPositiveFinite(containerFact.value) {
        findings.append(
          ValidationFinding(
            code: .invalidQuantity,
            message: "Container size must be a positive finite number.",
            field: "containerSize"
          )
        )
        if !ambiguities.contains(.invalidQuantity) {
          ambiguities.append(.invalidQuantity)
        }
        result.containerSize = nil
        result.containerSizeUnit = nil
      }
    }

    if let alternateFact = result.alternateQuantity {
      if !Self.isValidPositiveFinite(alternateFact.value) {
        findings.append(
          ValidationFinding(
            code: .invalidQuantity,
            message: "Alternate quantity must be a positive finite number.",
            field: "alternateQuantity"
          )
        )
        if !ambiguities.contains(.invalidQuantity) {
          ambiguities.append(.invalidQuantity)
        }
        result.alternateQuantity = nil
        result.alternateUnit = nil
      }
    }

    // Missing quantity is recorded but does not block pre-USDA proceed when identity is OK.
    // ServingResolution handles portion after the user picks a USDA record.
    let hasQuantityUnitPair = result.quantity != nil && result.unit != nil
    let hasFraction = result.fractionOfWhole != nil
    if !hasQuantityUnitPair && !hasFraction {
      findings.append(
        ValidationFinding(
          code: .missingQuantity,
          message:
            "No usable quantity or fraction; USDA search may proceed and quantity can be resolved after selection.",
          field: "quantity"
        )
      )
      ambiguities.append(.missingQuantity)
    }

    result.findings = findings
    result.ambiguities = ambiguities
    return result
  }

  // MARK: - Helpers

  public static func isValidPositiveFinite(_ value: Double) -> Bool {
    value.isFinite && value > 0
  }

  /// Fraction of a whole item/container must be in (0, 1].
  public static func isValidFraction(_ value: Double) -> Bool {
    value.isFinite && value > 0 && value <= 1
  }

  private static func defaultProvenance(for kind: EvidenceSourceKind) -> FieldProvenance {
    switch kind {
    case .typedText: return .directlyStated
    case .photoObservation: return .visuallyObserved
    case .rememberedFood: return .rememberedValue
    case .userEdit: return .userConfirmed
    }
  }

  private static func defaultConfidence(for kind: EvidenceSourceKind) -> FieldConfidence {
    switch kind {
    case .typedText: return .high
    case .photoObservation: return .uncertain
    case .rememberedFood: return .high
    // User edits are confirmed only via applyUserConfirm; draft-from-edit still high until confirm.
    case .userEdit: return .high
    }
  }
}
