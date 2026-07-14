import Foundation

/// Deterministic routing for food-interpretation drafts.
///
/// Soft user-facing clarification is **model-authored only**: when
/// `clarificationPrompt` is non-empty, the app shows that prompt. This type does
/// not invent chat copy, food-type rules, or sufficiency heuristics.
///
/// Priority (pre-USDA):
/// 1. Max automatic turns exceeded with open material issues → `fallbackManual`
/// 2. Non-empty model `clarificationPrompt` → `clarify` (prompt + suggestions from model)
/// 3. Empty identity without a model prompt → `requireEdit` (model failed to guide)
/// 4. Multiple foods without a model prompt → `requireEdit`
/// 5. Residual invalid quantity values → `clarify` with a validation message
/// 6. Else → `proceed`
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

    // 1. Two automatic clarify turns max, then manual path.
    if validated.turnCount >= maxTurns, hasBlockingMaterialIssue(validated) {
      var withMax = validated
      if !withMax.ambiguities.contains(.maxTurnsExceeded) {
        withMax.ambiguities.append(.maxTurnsExceeded)
      }
      return .fallbackManual(
        "Still unclear after \(maxTurns) clarification turns. Edit the entry manually or try a simpler search."
      )
    }

    // 2. Multi-food meal → composite (several USDA lookups, one log entry).
    // Prefer model componentNames; otherwise recover from source "X with Y" / "X and Y".
    if validated.turnCount < maxTurns {
      var components = Self.dedupedComponentNames(validated.componentNames)
      // Recover components from source text only on the initial interpretation
      // when the model was silent. An explicit model clarify prompt ("which
      // one?") means ask the user; and once the user has answered a turn we must
      // not re-split the original "X and Y" source into a composite.
      if components.count < 2, validated.turnCount == 0,
        validated.modelClarificationPrompt == nil
      {
        components = Self.dedupedComponentNames(
          Self.inferredComponents(from: validated.sourceText))
      }
      if components.count >= 2,
        validated.containsMultipleFoods || Self.looksLikeMultiItemMeal(validated.sourceText)
      {
        return .beginComposite(
          componentNames: components,
          sourceText: validated.sourceText
        )
      }
    }

    // 3. Model-authored soft clarify — the only source of conversational copy.
    if validated.turnCount < maxTurns, let prompt = validated.modelClarificationPrompt {
      let code = Self.clarificationCode(for: validated)
      // Identity freeform only: model often emits junk chips (warm/cooked) here.
      let chips: [String]
      switch code {
      case .emptyIdentity, .noPlausibleIdentity:
        chips = []
      default:
        chips = Self.usableAnswerChips(validated.clarificationSuggestions, for: code)
      }
      return .clarify(
        ClarificationQuestion(
          code: code,
          prompt: prompt,
          suggestedAnswers: chips,
          allowsFreeform: true
        )
      )
    }

    // 4. Empty identity with no model question → hard stop (no canned chat).
    if !validated.hasIdentity {
      return .requireEdit(
        validated.ambiguityNotes
          ?? "No food identity to look up. Name the food or enter nutrition manually."
      )
    }

    // 5. Multiple foods without usable component list → pick one or manual.
    if validated.containsMultipleFoods {
      if validated.turnCount < maxTurns {
        return .clarify(
          ClarificationQuestion(
            code: .multipleFoods,
            prompt: validated.modelClarificationPrompt
              ?? "It looks like more than one food. Which one should I log first?",
            suggestedAnswers: Self.usableAnswerChips(
              validated.clarificationSuggestions, for: .multipleFoods),
            allowsFreeform: true
          )
        )
      }
      return .requireEdit(
        validated.ambiguityNotes
          ?? "More than one food was mentioned. Log one food at a time or enter nutrition manually."
      )
    }

    // 6. Invalid quantity that was not fully stripped (defensive validation).
    if validated.ambiguities.contains(.invalidQuantity),
      validated.quantity != nil || validated.fractionOfWhole != nil
        || validated.containerSize != nil || validated.alternateQuantity != nil
    {
      return .clarify(
        ClarificationQuestion(
          code: .invalidQuantity,
          prompt: "That amount doesn’t look valid. What quantity did you have?",
          suggestedAnswers: [],
          allowsFreeform: true
        )
      )
    }

    // 7. Proceed.
    return .proceed(validated.toParsedFoodRequest())
  }

  // MARK: - Apply user answer

  /// Applies a free-form or suggested answer for the active clarification question.
  /// Increments `turnCount` and re-validates. Does not set `confirmed` confidence.
  ///
  /// Prefer re-parsing the conversation with the on-device model when available;
  /// this path keeps offline recovery and unit tests working.
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
        next.ambiguities.removeAll { $0 == .multipleFoods || $0 == .emptyIdentity }
      }

    case .invalidQuantity, .missingQuantity, .uncertainPreparation:
      Self.applyDetailAnswer(trimmed, to: &next, for: question.code)

    case .uncertainBrand:
      if !trimmed.isEmpty {
        next.brand = FieldFact(
          value: trimmed,
          provenance: .userConfirmed,
          confidence: .high
        )
      }

    case .conflictingUnits, .hiddenIngredient, .maxTurnsExceeded:
      if !trimmed.isEmpty, !next.hasIdentity {
        next.productName = FieldFact(
          value: trimmed,
          provenance: .userConfirmed,
          confidence: .high
        )
        next.searchTerms = trimmed
      }
    }

    // User answered — clear model clarify so we do not re-ask the same prompt.
    next.quantityNeedsClarification = false
    next.preparationNeedsClarification = false
    next.clarificationPrompt = nil
    next.clarificationSuggestions = []

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
    next.quantityNeedsClarification = false
    next.preparationNeedsClarification = false
    next.clarificationPrompt = nil
    next.clarificationSuggestions = []
    return FoodInterpretationValidator().validate(next)
  }

  // MARK: - Private

  private func hasBlockingMaterialIssue(_ draft: FoodInterpretationDraft) -> Bool {
    if !draft.hasIdentity { return true }
    if draft.containsMultipleFoods { return true }
    if draft.modelClarificationPrompt != nil { return true }
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

  /// Maps model state to an ambiguity code for answer handling — not for copy.
  private static func clarificationCode(for draft: FoodInterpretationDraft) -> AmbiguityCode {
    if !draft.hasIdentity { return .emptyIdentity }
    if draft.containsMultipleFoods { return .multipleFoods }
    if draft.quantityNeedsClarification { return .missingQuantity }
    if draft.preparationNeedsClarification { return .uncertainPreparation }
    return .noPlausibleIdentity
  }

  private static func dedupedComponentNames(_ names: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for raw in names {
      let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      let key = name.lowercased()
      guard seen.insert(key).inserted else { continue }
      ordered.append(name)
    }
    return ordered
  }

  /// Conservative multi-item detectors for phrases like "cereal with milk".
  private static func looksLikeMultiItemMeal(_ source: String) -> Bool {
    let lower = " \(source.lowercased()) "
    return lower.contains(" with ") || lower.contains(" and ") || lower.contains(" plus ")
  }

  /// Split source on with/and/plus into 2 short food-ish phrases when possible.
  private static func inferredComponents(from source: String) -> [String] {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    let separators = [" with ", " and ", " plus ", " & "]
    for sep in separators {
      let range = trimmed.range(of: sep, options: .caseInsensitive)
      guard let range else { continue }
      let left = String(trimmed[..<range.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let right = String(trimmed[range.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard left.count >= 3, right.count >= 3 else { continue }
      // Strip leading meal-speak so search works better.
      let cleanedLeft = stripLeadingMealPhrase(left)
      let cleanedRight = stripLeadingMealPhrase(right)
      guard cleanedLeft.count >= 2, cleanedRight.count >= 2 else { continue }
      // Avoid splitting sandwich-style names that are one food ("peanut butter and jelly sandwich").
      if cleanedRight.lowercased().hasSuffix("sandwich")
        || cleanedRight.lowercased().hasSuffix("burger")
        || cleanedRight.lowercased().hasSuffix("pizza")
      {
        continue
      }
      return [cleanedLeft, cleanedRight]
    }
    return []
  }

  private static func stripLeadingMealPhrase(_ text: String) -> String {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixes = [
      "i had a bowl of ", "i had a ", "i had an ", "i had ", "i ate a ", "i ate an ", "i ate ",
      "a bowl of ", "bowl of ", "a glass of ", "glass of ", "a cup of ", "cup of ",
      "some ", "a ", "an ", "the ",
    ]
    let lower = t.lowercased()
    for p in prefixes where lower.hasPrefix(p) {
      t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
      break
    }
    return t
  }

  /// Drop question-shaped or non-answer chips; never invent replacements.
  private static func usableAnswerChips(_ suggestions: [String], for code: AmbiguityCode) -> [String]
  {
    let nonFoodNoise: Set<String> = [
      "warm", "hot", "cold", "cooked", "raw", "yummy", "delicious", "tasty", "good", "great",
      "something", "food", "meal", "snack", "leftovers", "whatever", "idk", "n/a", "na",
    ]
    return suggestions
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { chip in
        guard !chip.isEmpty, chip.count <= 48 else { return false }
        if chip.hasSuffix("?") { return false }
        let lower = chip.lowercased()
        if lower.hasPrefix("how ") || lower.hasPrefix("what ") || lower.hasPrefix("which ")
          || lower.hasPrefix("were ") || lower.hasPrefix("was ") || lower.hasPrefix("could ")
          || lower.hasPrefix("can ") || lower.hasPrefix("did ")
        {
          return false
        }
        // Prep-only chips are fine for prep questions, not for multi-food identity picks.
        if code == .multipleFoods, nonFoodNoise.contains(lower) { return false }
        if code == .missingQuantity, nonFoodNoise.contains(lower), !chip.contains(where: \.isNumber)
        {
          return false
        }
        return true
      }
  }

  private static func applyDetailAnswer(
    _ answer: String,
    to draft: inout FoodInterpretationDraft,
    for code: AmbiguityCode
  ) {
    guard !answer.isEmpty else { return }

    if let quantity = parsePositiveQuantity(answer) {
      draft.quantity = FieldFact(
        value: quantity,
        provenance: .userConfirmed,
        confidence: .high
      )
      draft.quantityText = FieldFact(
        value: answer,
        provenance: .userConfirmed,
        confidence: .high
      )
      if let unit = parseTrailingUnit(answer) {
        draft.unit = FieldFact(
          value: unit,
          provenance: .userConfirmed,
          confidence: .high
        )
      } else if let remainder = trailingDetail(afterQuantityIn: answer), !remainder.isEmpty {
        draft.preparation = FieldFact(
          value: remainder,
          provenance: .userConfirmed,
          confidence: .high
        )
        foldPreparationIntoSearch(remainder, draft: &draft)
      }
    } else if code == .uncertainPreparation || code == .missingQuantity {
      draft.preparation = FieldFact(
        value: answer,
        provenance: .userConfirmed,
        confidence: .high
      )
      foldPreparationIntoSearch(answer, draft: &draft)
      if code == .missingQuantity {
        draft.quantityText = FieldFact(
          value: answer,
          provenance: .userConfirmed,
          confidence: .high
        )
      }
    }
  }

  private static func foldPreparationIntoSearch(
    _ preparation: String,
    draft: inout FoodInterpretationDraft
  ) {
    let base = draft.trimmedIdentity
    let prep = preparation.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !base.isEmpty, !prep.isEmpty else { return }
    if !base.lowercased().contains(prep.lowercased()) {
      draft.searchTerms = "\(prep) \(base)"
    }
  }

  // Constant patterns, compiled once rather than on every clarification answer.
  private static let quantityPrefixRegex = try? NSRegularExpression(
    pattern: #"^[\s]*([0-9]+(?:\.[0-9]+)?)"#)
  private static let trailingUnitRegex = try? NSRegularExpression(
    pattern: #"^[0-9]+(?:\.[0-9]+)?\s+([A-Za-z]+)\s*$"#)
  private static let trailingDetailRegex = try? NSRegularExpression(
    pattern: #"^[0-9]+(?:\.[0-9]+)?\s+(.+)$"#)

  private static func parsePositiveQuantity(_ text: String) -> Double? {
    guard let regex = quantityPrefixRegex else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let numberRange = Range(match.range(at: 1), in: text),
      let value = Double(text[numberRange]),
      FoodInterpretationValidator.isValidPositiveFinite(value)
    else { return nil }
    return value
  }

  private static func parseTrailingUnit(_ text: String) -> String? {
    guard let regex = trailingUnitRegex else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let unitRange = Range(match.range(at: 1), in: text)
    else { return nil }
    let unit = String(text[unitRange]).lowercased()
    guard measurementUnits.contains(unit) else { return nil }
    return unit
  }

  private static func trailingDetail(afterQuantityIn text: String) -> String? {
    guard let regex = trailingDetailRegex else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let detailRange = Range(match.range(at: 1), in: text)
    else { return nil }
    let detail = String(text[detailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    return detail.isEmpty ? nil : detail
  }

  private static let measurementUnits: Set<String> = [
    "g", "gram", "grams", "kg", "mg",
    "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds",
    "ml", "l", "liter", "liters", "litre", "litres",
    "cup", "cups", "tbsp", "tsp", "tablespoon", "tablespoons", "teaspoon", "teaspoons",
    "serving", "servings", "slice", "slices", "piece", "pieces",
  ]
}
