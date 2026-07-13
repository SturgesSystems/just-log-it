import Foundation
import Testing

@testable import JustLogItCore

// MARK: - Proceed paths

@Test func groundedSingleFoodWithQuantityProceeds() {
  let parsed = ParsedFoodRequest(
    productName: "oreo cookie",
    searchTerms: "oreo cookie",
    quantity: 2,
    unit: "cookies"
  )
  let draft = FoodInterpretationValidator().draft(
    from: parsed,
    sourceText: "2 oreo cookies",
    evidenceKind: .typedText
  )
  let decision = ClarificationPolicy().decide(draft)

  guard case .proceed(let request) = decision else {
    Issue.record("Expected proceed, got \(decision)")
    return
  }
  #expect(request.productName == "oreo cookie")
  #expect(request.quantity == 2)
  #expect(request.unit == "cookies")
  #expect(draft.productName.confidence == .high)
  #expect(draft.productName.provenance == .directlyStated)
  #expect(draft.productName.confidence != .confirmed)
}

@Test func missingQuantityAloneStillProceedsPreUSDA() {
  // Quantity is resolved after USDA selection via ServingResolution.
  let parsed = ParsedFoodRequest(productName: "banana", searchTerms: "banana")
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "banana")
  let decision = ClarificationPolicy().decide(draft)

  guard case .proceed(let request) = decision else {
    Issue.record("Expected proceed for identity-only draft, got \(decision)")
    return
  }
  #expect(request.productName == "banana")
  #expect(request.quantity == nil)
  #expect(draft.ambiguities.contains(.missingQuantity))
}

// MARK: - Empty identity

@Test func emptyProductRequiresEditAndNeverProceeds() {
  let parsed = ParsedFoodRequest(productName: "", searchTerms: "")
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "???")
  let decision = ClarificationPolicy().decide(draft)

  switch decision {
  case .requireEdit, .fallbackManual:
    break
  case .proceed:
    Issue.record("Empty identity must never proceed to USDA")
  case .clarify:
    Issue.record("Empty identity should requireEdit, not clarify: \(decision)")
  }

  #expect(draft.ambiguities.contains(.emptyIdentity))
  #expect(!draft.hasIdentity)
}

@Test func whitespaceOnlyProductIsEmptyIdentity() {
  let parsed = ParsedFoodRequest(productName: "   ", searchTerms: "   ")
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "   ")
  #expect(!draft.hasIdentity)
  #expect(draft.ambiguities.contains(.emptyIdentity))

  let decision = ClarificationPolicy().decide(draft)
  guard case .requireEdit = decision else {
    Issue.record("Expected requireEdit for whitespace identity, got \(decision)")
    return
  }
}

// MARK: - Multiple foods

@Test func multipleFoodsClarifiesAndDoesNotProceed() {
  let parsed = ParsedFoodRequest(
    productName: "eggs and bacon",
    searchTerms: "eggs and bacon",
    containsMultipleFoods: true
  )
  let draft = FoodInterpretationValidator().draft(
    from: parsed,
    sourceText: "eggs and bacon"
  )
  let decision = ClarificationPolicy().decide(draft)

  guard case .clarify(let question) = decision else {
    Issue.record("Expected clarify for multiple foods, got \(decision)")
    return
  }
  #expect(question.code == .multipleFoods)
  #expect(draft.ambiguities.contains(.multipleFoods))
}

@Test func answeringMultipleFoodsSelectsSingleIdentity() {
  let parsed = ParsedFoodRequest(
    productName: "eggs and bacon",
    containsMultipleFoods: true
  )
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "eggs and bacon")
  guard case .clarify(let question) = ClarificationPolicy().decide(draft) else {
    Issue.record("Expected initial clarify")
    return
  }

  let updated = ClarificationPolicy().applyUserAnswer("eggs", to: draft, for: question)
  #expect(updated.productName.value == "eggs")
  #expect(!updated.containsMultipleFoods)
  #expect(updated.turnCount == 1)
  #expect(updated.productName.confidence == .high)
  #expect(updated.productName.confidence != .confirmed)

  let decision = ClarificationPolicy().decide(updated)
  guard case .proceed(let request) = decision else {
    Issue.record("Expected proceed after single-food answer, got \(decision)")
    return
  }
  #expect(request.productName == "eggs")
  #expect(request.containsMultipleFoods == false)
}

// MARK: - Invalid quantity

@Test func invalidQuantityIsStrippedAndCanStillProceed() {
  let parsed = ParsedFoodRequest(
    productName: "milk",
    searchTerms: "milk",
    quantity: -3,
    unit: "cups"
  )
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "-3 cups milk")

  #expect(draft.quantity == nil)
  #expect(draft.unit == nil)
  #expect(draft.findings.contains { $0.code == .invalidQuantity })
  #expect(draft.ambiguities.contains(.invalidQuantity))

  let decision = ClarificationPolicy().decide(draft)
  guard case .proceed(let request) = decision else {
    Issue.record("Expected proceed after stripping invalid quantity, got \(decision)")
    return
  }
  #expect(request.productName == "milk")
  #expect(request.quantity == nil)
}

@Test func nonfiniteQuantityIsStripped() {
  let parsed = ParsedFoodRequest(
    productName: "rice",
    quantity: .nan,
    unit: "g"
  )
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "rice")
  #expect(draft.quantity == nil)
  #expect(draft.findings.contains { $0.code == .invalidQuantity })
}

@Test func zeroQuantityIsInvalid() {
  let parsed = ParsedFoodRequest(
    productName: "rice",
    quantity: 0,
    unit: "g"
  )
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "0 g rice")
  #expect(draft.quantity == nil)
  #expect(draft.findings.contains { $0.code == .invalidQuantity })
}

@Test func invalidFractionIsStripped() {
  let parsed = ParsedFoodRequest(
    productName: "pizza",
    fractionOfWhole: 1.5,
    wholeUnit: "pizza"
  )
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "1.5 pizza")
  #expect(draft.fractionOfWhole == nil)
  #expect(draft.wholeUnit == nil)
  #expect(draft.findings.contains { $0.code == .invalidQuantity })
}

@Test func validFractionIsPreserved() {
  let parsed = ParsedFoodRequest(
    productName: "pizza",
    fractionOfWhole: 0.5,
    wholeUnit: "pizza"
  )
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "half a pizza")
  #expect(draft.fractionOfWhole?.value == 0.5)
  #expect(!draft.ambiguities.contains(.missingQuantity))
  #expect(!draft.ambiguities.contains(.invalidQuantity))

  guard case .proceed = ClarificationPolicy().decide(draft) else {
    Issue.record("Expected proceed for valid fraction draft")
    return
  }
}

// MARK: - Max turns

@Test func afterTwoTurnsWithMultipleFoodsStillSetFallsBackManual() {
  let parsed = ParsedFoodRequest(
    productName: "eggs and bacon",
    containsMultipleFoods: true
  )
  var draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "eggs and bacon")
  draft.turnCount = 2

  let decision = ClarificationPolicy().decide(draft)
  guard case .fallbackManual(let message) = decision else {
    Issue.record("Expected fallbackManual after max turns, got \(decision)")
    return
  }
  #expect(!message.isEmpty)
}

@Test func underMaxTurnsStillClarifiesMultipleFoods() {
  let parsed = ParsedFoodRequest(
    productName: "eggs and bacon",
    containsMultipleFoods: true
  )
  var draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "eggs and bacon")
  draft.turnCount = 1

  let decision = ClarificationPolicy().decide(draft)
  guard case .clarify(let question) = decision else {
    Issue.record("Expected clarify under max turns, got \(decision)")
    return
  }
  #expect(question.code == .multipleFoods)
}

@Test func maxTurnsWithResolvedDraftProceeds() {
  // Even at max turns, a clean identity with no material issues proceeds.
  let parsed = ParsedFoodRequest(
    productName: "apple",
    quantity: 1,
    unit: "medium"
  )
  var draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "1 medium apple")
  draft.turnCount = 2

  let decision = ClarificationPolicy().decide(draft)
  guard case .proceed = decision else {
    Issue.record("Resolved draft at max turns should proceed, got \(decision)")
    return
  }
}

// MARK: - User confirm

@Test func applyUserConfirmMarksConfirmed() {
  let parsed = ParsedFoodRequest(
    brand: "Oreo",
    productName: "cookie",
    quantity: 2,
    unit: "cookies",
    preparation: "crushed",
    descriptors: ["chocolate"]
  )
  let draft = FoodInterpretationValidator().draft(
    from: parsed,
    sourceText: "2 crushed Oreo cookies"
  )
  #expect(draft.productName.confidence != .confirmed)

  let confirmed = ClarificationPolicy().applyUserConfirm(draft)

  #expect(confirmed.productName.confidence == .confirmed)
  #expect(confirmed.productName.provenance == .userConfirmed)
  #expect(confirmed.brand?.confidence == .confirmed)
  #expect(confirmed.brand?.provenance == .userConfirmed)
  #expect(confirmed.quantity?.confidence == .confirmed)
  #expect(confirmed.unit?.confidence == .confirmed)
  #expect(confirmed.preparation?.confidence == .confirmed)
  #expect(confirmed.descriptors.confidence == .confirmed)
  #expect(confirmed.descriptors.provenance == .userConfirmed)
}

@Test func draftConstructionNeverSetsConfirmedConfidence() {
  let parsed = ParsedFoodRequest(productName: "yogurt", quantity: 1, unit: "cup")
  let draft = FoodInterpretationValidator().draft(from: parsed, sourceText: "1 cup yogurt")
  #expect(draft.productName.confidence != .confirmed)
  #expect(draft.quantity?.confidence != .confirmed)
  #expect(draft.unit?.confidence != .confirmed)
}

// MARK: - toParsedFoodRequest

@Test func toParsedFoodRequestUsesProductNameWhenSearchEmpty() {
  let draft = FoodInterpretationDraft(
    productName: FieldFact(
      value: "salmon",
      provenance: .directlyStated,
      confidence: .high
    ),
    searchTerms: ""
  )
  let request = draft.toParsedFoodRequest()
  #expect(request.productName == "salmon")
  #expect(request.searchTerms == "salmon")
}

@Test func toParsedFoodRequestPreservesExplicitSearchTerms() {
  let draft = FoodInterpretationDraft(
    productName: FieldFact(
      value: "cookie",
      provenance: .directlyStated,
      confidence: .high
    ),
    brand: FieldFact(value: "Oreo", provenance: .directlyStated, confidence: .high),
    searchTerms: "Oreo cookie"
  )
  let request = draft.toParsedFoodRequest()
  #expect(request.searchTerms == "Oreo cookie")
  #expect(request.brand == "Oreo")
}

// MARK: - Package hygiene

@Test func corePackageHasNoForbiddenImports() throws {
  let sourcesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // JustLogItCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // JustLogItCore package root
    .appendingPathComponent("Sources/JustLogItCore", isDirectory: true)

  let forbidden = ["SwiftUI", "SwiftData", "FoundationModels", "HealthKit"]
  let enumerator = FileManager.default.enumerator(
    at: sourcesRoot,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
  )

  var checked = 0
  while let item = enumerator?.nextObject() as? URL {
    guard item.pathExtension == "swift" else { continue }
    checked += 1
    let source = try String(contentsOf: item, encoding: .utf8)
    for module in forbidden {
      let importLine = "import \(module)"
      #expect(
        !source.contains(importLine),
        "Forbidden import \(module) in \(item.lastPathComponent)"
      )
    }
  }
  #expect(checked > 0, "Expected to find Swift sources under \(sourcesRoot.path)")
}

@Test func multipleFoodsClarificationIncludesSplitSuggestions() {
  let parsed = ParsedFoodRequest(
    productName: "eggs and bacon",
    searchTerms: "eggs and bacon",
    containsMultipleFoods: true
  )
  let draft = FoodInterpretationValidator().draft(
    from: parsed,
    sourceText: "eggs and bacon",
    evidenceKind: .typedText
  )
  let decision = ClarificationPolicy().decide(draft)
  guard case .clarify(let question) = decision else {
    Issue.record("Expected clarify, got \(decision)")
    return
  }
  #expect(question.code == .multipleFoods)
  #expect(question.suggestedAnswers.count >= 2)
  #expect(question.suggestedAnswers.map { $0.lowercased() }.contains("eggs"))
  #expect(question.suggestedAnswers.map { $0.lowercased() }.contains("bacon"))
}
