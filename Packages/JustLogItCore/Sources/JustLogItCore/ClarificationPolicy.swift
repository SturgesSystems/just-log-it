import Foundation

/// Deterministic routing for food-interpretation drafts.
///
/// Priority (Phase 1, pre-USDA):
/// 1. Max automatic turns exceeded with open material issues → `fallbackManual`
/// 2. Empty / no identity → `requireEdit` (never proceed to USDA)
/// 3. Multiple foods → `clarify` (never silent proceed)
/// 4. Residual invalid-quantity findings that still block safety → `clarify`
///    (validator normally strips invalid quantities so proceed remains OK)
/// 5. Else → `proceed` — including when only `missingQuantity` remains, because
///    the app resolves portion after USDA selection via `ServingResolution`.
///
/// `FieldConfidence.confirmed` is set only by `applyUserConfirm`, never by model scores.
public struct ClarificationPolicy: Sendable {
  /// Maximum automatic clarification turns before fallback. Default 2; never loop.
  public var maxTurns: Int

  public init(maxTurns: Int = 2) {
    self.maxTurns = maxTurns
  }

  // MARK: - Decide

  public func decide(_ draft: FoodInterpretationDraft) -> ClarificationDecision {
    let validated = FoodInterpretationValidator().validate(draft)
    let material = validated.materialAmbiguities

    // 1. Two automatic clarify turns max, then offer manual edit / simpler path.
    if validated.turnCount >= maxTurns, hasBlockingMaterialIssue(validated) {
      var withMax = validated
      if !withMax.ambiguities.contains(.maxTurnsExceeded) {
        withMax.ambiguities.append(.maxTurnsExceeded)
      }
      return .fallbackManual(
        "Still unclear after \(maxTurns) clarification turns. Edit the entry manually or try a simpler search."
      )
    }

    // 2. Empty identity never proceeds to USDA.
    if !validated.hasIdentity || material.contains(.emptyIdentity)
      || material.contains(.noPlausibleIdentity)
    {
      return .requireEdit(
        "Enter a food name to search. Empty identity cannot proceed to USDA."
      )
    }

    // 3. Multiple foods → clarify (or requireEdit if we cannot form a question).
    if validated.containsMultipleFoods || material.contains(.multipleFoods) {
      return .clarify(
        ClarificationQuestion(
          code: .multipleFoods,
          prompt: "It looks like more than one food. Which one do you want to log?",
          suggestedAnswers: [],
          allowsFreeform: true
        )
      )
    }

    // 4. Invalid quantity that was not fully stripped (defensive).
    if validated.ambiguities.contains(.invalidQuantity),
      validated.quantity != nil || validated.fractionOfWhole != nil
        || validated.containerSize != nil || validated.alternateQuantity != nil
    {
      // Re-strip via validator path: if values remain but still marked invalid, ask.
      return .clarify(
        ClarificationQuestion(
          code: .invalidQuantity,
          prompt: "That amount doesn’t look valid. What quantity did you have?",
          suggestedAnswers: [],
          allowsFreeform: true
        )
      )
    }

    // 5. Proceed — missing quantity alone is OK pre-USDA (ServingResolution after pick).
    return .proceed(validated.toParsedFoodRequest())
  }

  // MARK: - Apply user answer

  /// Applies a free-form or suggested answer for the active clarification question.
  /// Increments `turnCount` and re-validates. Does not set `confirmed` confidence.
  public func applyUserAnswer(
    _ answer: String,
    to draft: FoodInterpretationDraft,
    for question: ClarificationQuestion
  ) -> FoodInterpretationDraft {
    var next = draft
    next.turnCount += 1
    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)

    switch question.code {
    case .multipleFoods, .emptyIdentity, .noPlausibleIdentity:
      if !trimmed.isEmpty {
        next.productName = FieldFact(
          value: trimmed,
          provenance: .userConfirmed,
          confidence: .high
        )
        next.searchTerms = trimmed
        next.containsMultipleFoods = false
        // Clear multiple-foods ambiguity state; validate will recompute.
        next.ambiguities.removeAll { $0 == .multipleFoods || $0 == .emptyIdentity }
      }

    case .invalidQuantity, .missingQuantity:
      if let parsed = Self.parsePositiveQuantity(trimmed) {
        next.quantity = FieldFact(
          value: parsed,
          provenance: .userConfirmed,
          confidence: .high
        )
        // Leave unit as-is unless answer embeds a simple unit token.
        if let unit = Self.parseTrailingUnit(trimmed) {
          next.unit = FieldFact(
            value: unit,
            provenance: .userConfirmed,
            confidence: .high
          )
        }
      }

    case .uncertainBrand:
      if !trimmed.isEmpty {
        next.brand = FieldFact(
          value: trimmed,
          provenance: .userConfirmed,
          confidence: .high
        )
      }

    case .uncertainPreparation:
      if !trimmed.isEmpty {
        next.preparation = FieldFact(
          value: trimmed,
          provenance: .userConfirmed,
          confidence: .high
        )
      }

    case .conflictingUnits, .hiddenIngredient, .maxTurnsExceeded:
      // Phase 1: treat free-form as identity refinement when non-empty.
      if !trimmed.isEmpty, !next.hasIdentity {
        next.productName = FieldFact(
          value: trimmed,
          provenance: .userConfirmed,
          confidence: .high
        )
        next.searchTerms = trimmed
      }
    }

    return FoodInterpretationValidator().validate(next)
  }

  // MARK: - Confirm

  /// Explicit user confirmation: sets present fields to `userConfirmed` / `confirmed`.
  /// This is the only API that assigns `FieldConfidence.confirmed`.
  public func applyUserConfirm(_ draft: FoodInterpretationDraft) -> FoodInterpretationDraft {
    var next = draft
    next.productName = next.productName.confirmedByUser()
    next.brand = next.brand?.confirmedByUser()
    next.quantity = next.quantity?.confirmedByUser()
    next.unit = next.unit?.confirmedByUser()
    next.quantityText = next.quantityText?.confirmedByUser()
    next.fractionOfWhole = next.fractionOfWhole?.confirmedByUser()
    next.wholeUnit = next.wholeUnit?.confirmedByUser()
    next.containerSize = next.containerSize?.confirmedByUser()
    next.containerSizeUnit = next.containerSizeUnit?.confirmedByUser()
    next.alternateQuantity = next.alternateQuantity?.confirmedByUser()
    next.alternateUnit = next.alternateUnit?.confirmedByUser()
    next.preparation = next.preparation?.confirmedByUser()
    next.descriptors = next.descriptors.confirmedByUser()
    next.evidenceKind = .userEdit
    return FoodInterpretationValidator().validate(next)
  }

  // MARK: - Private

  private func hasBlockingMaterialIssue(_ draft: FoodInterpretationDraft) -> Bool {
    if !draft.hasIdentity { return true }
    if draft.containsMultipleFoods { return true }
    if draft.ambiguities.contains(where: {
      switch $0 {
      case .emptyIdentity, .noPlausibleIdentity, .multipleFoods:
        return true
      default:
        return false
      }
    }) {
      return true
    }
    return false
  }

  private static func parsePositiveQuantity(_ text: String) -> Double? {
    // Leading number (locale-agnostic for Phase 1 ASCII / plain Double).
    let pattern = #"^[\s]*([0-9]+(?:\.[0-9]+)?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let numberRange = Range(match.range(at: 1), in: text),
      let value = Double(text[numberRange]),
      FoodInterpretationValidator.isValidPositiveFinite(value)
    else { return nil }
    return value
  }

  private static func parseTrailingUnit(_ text: String) -> String? {
    let pattern = #"^[0-9]+(?:\.[0-9]+)?\s+([A-Za-z]+)\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let unitRange = Range(match.range(at: 1), in: text)
    else { return nil }
    let unit = String(text[unitRange])
    return unit.isEmpty ? nil : unit
  }
}
