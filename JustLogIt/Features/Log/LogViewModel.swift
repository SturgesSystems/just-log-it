import Foundation
import JustLogItCore
import SwiftData
import SwiftUI

@MainActor
final class LogViewModel: ObservableObject {
  enum Stage: Equatable {
    case idle
    case parsing
    case awaitingClarification
    case searching
    case choosing
    case loadingDetails
    case clarifying
    case reviewing
    case whenEaten
    case confirming
    case completed
    case failed
  }

  enum FailureKind: Equatable {
    case interpretation
    case search
    case noResults
    case details
  }

  @Published var input = ""
  @Published var manualSearchTerms = ""
  @Published var stage: Stage = .idle
  @Published var parsed: ParsedFoodRequest?
  @Published var results: [FoodSearchResult] = []
  @Published var selectedResult: FoodSearchResult?
  @Published var details: FoodDetails?
  @Published var resolution: ServingResolution?
  @Published var nutrients: [NutrientAmount] = []
  @Published var message: String?
  @Published var failureKind: FailureKind?
  @Published var activeQuestion: ClarificationQuestion?
  @Published var clarificationAnswer = ""
  @Published var clarificationServings = ""
  @Published var clarificationGrams = ""
  @Published var showManualEntry = false
  /// When non-empty, `makeRecord()` saves a multi-component composite entry.
  @Published var compositeComponents: [CompositeComponentSnapshot] = []
  /// Remaining component names while assembling a multi-food log.
  @Published var pendingCompositeNames: [String] = []
  /// Human label for the meal while building composites (original user text).
  @Published var compositeSessionSource: String = ""
  /// Which component is currently being matched (for UI chrome).
  @Published var activeCompositeComponent: String?

  @Published var transcript: [ConversationTurn] = []
  @Published var whenEatenAnswer = ""
  @Published var consumedAt: Date = .now
  /// When set from clear wording (“just ate”, “for breakfast”), shown on review and we skip asking.
  @Published var consumedAtInference: MealTimeInference?
  @Published var lastSavedEntryID: UUID?
  @Published var lastSavedRecognizedFoodID: UUID?

  /// Chips for the when-eaten step (meal-aware when we have a soft inference).
  var whenEatenSuggestionChips: [String] {
    MealTimeInferenceService.suggestionChips(for: consumedAtInference)
  }

  let parser: any FoodDescriptionParsing
  let imageProposer: FoundationModelsImageFoodProposer
  let provider: any FoodDataProviding
  let rememberedFoods: any RememberedFoodStoring
  let queryBuilder = FoodSearchQueryBuilder()
  let resultRanker = FoodSearchResultRanker()
  let resolver = ServingResolutionService()
  let calculator = NutritionCalculator()
  let numberParser: LocalizedNumberParser
  let interpretationValidator = FoodInterpretationValidator()
  let clarificationPolicy = ClarificationPolicy()
  var interpretationDraft: FoodInterpretationDraft?
  var operation: Task<Void, Never>?
  var operationGeneration: UInt = 0
  /// When true, the next `submit()` will not append a user turn (used after edit rewind).
  var skipNextUserTranscriptAppend = false
  var compositeSessionActive = false

  var isBuildingComposite: Bool {
    compositeSessionActive
  }

  init(
    parser: (any FoodDescriptionParsing)? = nil,
    imageProposer: FoundationModelsImageFoodProposer = FoundationModelsImageFoodProposer(),
    provider: (any FoodDataProviding)? = nil,
    numberParser: LocalizedNumberParser = LocalizedNumberParser(),
    rememberedFoods: (any RememberedFoodStoring)? = nil
  ) {
    self.numberParser = numberParser
    self.imageProposer = imageProposer
    self.rememberedFoods = rememberedFoods ?? UserDefaultsRememberedFoodStore()
    let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    if let parser {
      self.parser = parser
    } else if isUITesting {
      self.parser = MockFoodParser()
    } else {
      self.parser = FoundationModelsFoodParser()
    }
    if let provider {
      self.provider = provider
    } else if isUITesting {
      self.provider = MockFoodDataProvider()
    } else {
      self.provider = FoodDataProviderFactory.make()
    }
  }

  deinit {
    operation?.cancel()
  }

  func submit() {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      fail(.interpretation, message: "Enter a food description first.")
      return
    }
    if skipNextUserTranscriptAppend {
      skipNextUserTranscriptAppend = false
    } else {
      if stage == .completed {
        // New log after save: clear the prior transcript first.
        transcript = []
        lastSavedEntryID = nil
        lastSavedRecognizedFoodID = nil
      }
      appendUserTurn(text)
    }
    // Chat feel: message lives in the transcript; composer returns to empty.
    // Capture `text` for the pipeline — do not re-read `input` after clearing.
    input = ""

    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.submitFlow(text: text, generation: generation)
    }
  }

  /// Proposes food identity from a user-selected photo, then continues clarification/search.
  /// Photo bytes never leave the device; only derived text search terms reach USDA.
  func proposeFromImage(data: Data, caption: String?) async {
    let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
    let captionOrNil = (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil

    if stage == .completed {
      transcript = []
      lastSavedEntryID = nil
      lastSavedRecognizedFoodID = nil
    }

    // Show the photo in the chat immediately (before model work).
    appendUserTurn(captionOrNil ?? "", imageData: data)

    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.imageProposalFlow(
        data: data, caption: captionOrNil, generation: generation)
    }
    await operation?.value
  }

  /// Surfaces a photo load/decode failure while keeping the text composer available.
  func reportPhotoUnavailable(_ message: String) {
    fail(.interpretation, message: message)
  }

  /// Rewinds the transcript to the given user turn, replaces its text, and re-runs parsing.
  func editUserMessage(id: UUID, newText: String) {
    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let index = transcript.firstIndex(where: { turn in
      if case .user(let turnID, _, _) = turn { return turnID == id }
      return false
    }) else { return }

    invalidateOperation()
    clearPipelineState()
    transcript = Array(transcript.prefix(index))
    transcript.append(.user(id: id, text: trimmed, imageData: nil))
    input = trimmed
    manualSearchTerms = ""
    whenEatenAnswer = ""
    consumedAt = .now
    consumedAtInference = nil
    message = nil
    failureKind = nil
    skipNextUserTranscriptAppend = true
    // Keep composer empty while the edited bubble is the source of truth.
    input = ""
    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.submitFlow(text: trimmed, generation: generation)
    }
  }

  func searchManually() {
    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.manualSearchFlow(generation: generation)
    }
  }

  func select(_ result: FoodSearchResult) {
    let generation = beginOperation()
    selectedResult = result
    // Echo the pick as a short chat acknowledgment (not a debug "Selected …" line).
    let label = result.description.trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty {
      appendSystemTurn("Using \(label).")
    }
    operation = Task { [weak self] in
      await self?.selectionFlow(result, generation: generation)
    }
  }

  var canSubmitClarificationAnswer: Bool {
    !clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func canResolveClarificationQuantity(usingServings: Bool) -> Bool {
    let text = usingServings ? clarificationServings : clarificationGrams
    return numberParser.parse(text, minimum: .greaterThanZero) != nil
  }

  /// Applies the free-form or suggested answer to the active interpretation question.
  ///
  /// Re-runs the on-device model on the conversation (original + question + reply).
  /// Do **not** blindly stuff the reply into `productName` — that turned dismissals
  /// like "who cares?" into USDA queries.
  func submitClarificationAnswer() {
    let answer = clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !answer.isEmpty, let question = activeQuestion, let draft = interpretationDraft else {
      return
    }
    appendUserTurn(answer)
    clarificationAnswer = ""
    let parseInput = ClarificationPromptBuilder.parseInput(
      sourceText: draft.sourceText,
      priorProduct: draft.trimmedIdentity,
      question: question.prompt,
      answer: answer
    )
    let evidenceText = [draft.sourceText, answer]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    let turnCount = draft.turnCount + 1
    // Leave interpretationDraft until reparse completes so cancel still works.
    activeQuestion = nil
    message = nil
    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.clarificationReparseFlow(
        parseInput: parseInput,
        evidenceText: evidenceText,
        turnCount: turnCount,
        generation: generation
      )
    }
  }


  func chooseClarificationSuggestion(_ suggestion: String) {
    if stage == .clarifying {
      applyQuantitySuggestion(suggestion)
      return
    }
    if stage == .whenEaten {
      applyWhenEatenSuggestion(suggestion)
      return
    }
    clarificationAnswer = suggestion
    submitClarificationAnswer()
  }

  func resolveWithServings() {
    resolveQuantityEntry(amountText: clarificationServings, unit: "serving")
  }

  func resolveWithGrams() {
    resolveQuantityEntry(amountText: clarificationGrams, unit: "g")
  }

  /// Resolve a typed amount + unit (servings, g, cup, tbsp, bowl, …) via `ServingResolution`.
  func resolveQuantityEntry(amountText: String, unit: String) {
    let amountRaw = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
    let unitRaw = unit.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !amountRaw.isEmpty, !unitRaw.isEmpty else {
      message = "Enter an amount and unit."
      return
    }
    guard let amount = numberParser.parse(amountRaw, minimum: .greaterThanZero) else {
      message = "Enter a valid amount."
      return
    }
    guard let details else {
      message = "Pick a USDA food first."
      return
    }

    let display = "\(amountRaw) \(unitRaw)"
    appendUserTurn(display)
    clarificationAnswer = ""
    message = nil

    let family = unitRaw.lowercased()
    if family.hasPrefix("serving") || family == "srv" {
      clarificationServings = amountRaw
      apply(resolver.manualServings(amount, food: details))
      return
    }
    if family == "g" || family.hasPrefix("gram") {
      clarificationGrams = amountRaw
      apply(resolver.manualGrams(amount, food: details))
      return
    }

    var req =
      parsed
      ?? ParsedFoodRequest(
        productName: details.description,
        searchTerms: details.description
      )
    req.quantity = amount
    req.unit = unitRaw
    req.quantityText = display
    req.fractionOfWhole = nil
    req.wholeUnit = nil
    req.containerSize = nil
    req.containerSizeUnit = nil
    parsed = req
    apply(resolver.resolve(req, against: details))
  }

  private static let quantitySuggestionRegex = try? NSRegularExpression(
    pattern: #"^\s*([0-9]+(?:[.,][0-9]+)?)\s*([A-Za-z].*)?$"#)

  /// Applies a quantity suggestion or freeform text such as "1 serving" / "100 g" / "1 cup".
  func applyQuantitySuggestion(_ suggestion: String) {
    let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // "1 serving", "100 g", "1.5 cup"
    if let regex = Self.quantitySuggestionRegex,
      let match = regex.firstMatch(
        in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
      let amountRange = Range(match.range(at: 1), in: trimmed)
    {
      let amountText = String(trimmed[amountRange])
      let unitText: String
      if match.numberOfRanges > 2, let unitRange = Range(match.range(at: 2), in: trimmed) {
        let raw = String(trimmed[unitRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        unitText = raw.isEmpty ? "serving" : raw
      } else {
        unitText = "serving"
      }
      resolveQuantityEntry(amountText: amountText, unit: unitText)
      return
    }

    // Bare number → servings when possible.
    if numberParser.parse(trimmed, minimum: .greaterThanZero) != nil {
      resolveQuantityEntry(amountText: trimmed, unit: "serving")
    }
  }

  /// Advances from nutrition review: skip “when?” when timing was already clear in the log text.
  /// From review, re-enter just the amount for the same food — no re-search.
  func adjustQuantity() {
    guard stage == .reviewing, compositeComponents.isEmpty, let details else { return }
    clarificationServings = ""
    clarificationGrams = ""
    presentQuantityClarification(explanation: "How much did you have?", food: details)
  }

  func continueFromReview() {
    guard stage == .reviewing else { return }
    message = nil

    // Re-infer in case source text is richer than at review entry.
    refreshConsumedAtInference()
    if let inference = consumedAtInference, inference.isClear {
      consumedAt = inference.date
      appendSystemTurn("Logged for \(inference.displayLabel.lowercased()).")
      stage = .confirming
      return
    }

    whenEatenAnswer = ""
    stage = .whenEaten
    appendSystemTurn("When did you eat this?")
  }

  func applyWhenEatenSuggestion(_ text: String) {
    whenEatenAnswer = text
    submitWhenEaten()
  }

  func submitWhenEaten() {
    guard stage == .whenEaten else { return }
    let text = whenEatenAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    let display = text.isEmpty ? "Just now" : text
    appendUserTurn(display)

    let resolved = MealTimeInferenceService.resolveAnswer(display)
    consumedAt = resolved.date
    consumedAtInference = MealTimeInference(
      date: resolved.date,
      displayLabel: resolved.displayLabel,
      isClear: resolved.wasParsed
    )
    if !resolved.wasParsed {
      message = "Couldn’t parse that time — using now."
    } else {
      message = nil
    }
    stage = .confirming
  }

  /// Applies clear meal-time cues from the original message onto review.
  func refreshConsumedAtInference() {
    let source = loggingSourceText
    let inference = MealTimeInferenceService.infer(from: source)
    consumedAtInference = inference
    if inference.isClear {
      consumedAt = inference.date
    }
  }

  func presentReview() {
    refreshConsumedAtInference()
    stage = .reviewing
  }

  /// Installs confirmed multi-food components for a later composite save.
  func setCompositeComponents(_ components: [CompositeComponentSnapshot]) {
    compositeComponents = components
  }

  func makeRecord() throws -> FoodLogEntryRecord {
    let source = loggingSourceText
    if !compositeComponents.isEmpty {
      let draft = CompositeDraftBuilder.makeFromMultiFoodConfirmation(
        sourceText: source,
        components: compositeComponents
      )
      let anyApproximate = draft.components.contains(where: \.isApproximate)
        || (parsed?.isApproximate == true)
      return try FoodLogEntryRecord(
        consumedAt: consumedAt,
        originalText: source,
        displayName: draft.name,
        brand: nil,
        quantityDisplay: "\(draft.components.count) foods",
        isApproximate: anyApproximate,
        source: .usda,
        calculationBasis: .manual,
        nutrients: draft.totalNutrients,
        isComposite: true,
        components: draft.components
      )
    }

    guard let parsed, let details, let resolution else { throw FoodParserError.invalidResponse }
    return try FoodLogEntryRecord(
      consumedAt: consumedAt,
      originalText: source,
      displayName: details.description,
      brand: details.brandOwner ?? parsed.brand,
      quantityDisplay: resolution.displayText,
      isApproximate: parsed.isApproximate,
      source: .usda,
      fdcID: details.fdcID,
      usdaDescription: details.description,
      usdaDataType: details.dataType,
      calculationBasis: resolution.basis,
      servingMultiplier: resolution.servingMultiplier,
      consumedGrams: resolution.consumedGrams,
      nutrients: nutrients
    )
  }

  /// Original user text for saves (chat clears `input` after send).
  var loggingSourceText: String {
    if !compositeSessionSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return compositeSessionSource
    }
    if let draft = interpretationDraft?.sourceText,
      !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return draft
    }
    if let firstUser = transcript.first(where: \.isUser)?.text,
      !firstUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return firstUser
    }
    return input
  }

  /// Marks a successful save after the view inserts the entry.
  func markSaved(entryID: UUID, recognizedFoodID: UUID? = nil) {
    rememberConfirmedSelectionIfPossible()
    lastSavedEntryID = entryID
    lastSavedRecognizedFoodID = recognizedFoodID
    stage = .completed
    message = "Entry saved on this device."
    appendSystemTurn("All set — that one’s saved.")
  }

  /// Convenience for tests that do not persist an entry.
  func markSaved() {
    markSaved(entryID: lastSavedEntryID ?? UUID(), recognizedFoodID: lastSavedRecognizedFoodID)
  }

  func markManualSaved() {
    reset()
    stage = .completed
    message = "Manual entry saved on this device."
  }

  func markSaveFailed() {
    stage = .confirming
    message = "The entry could not be saved. Your review has not been discarded."
  }

  func reset() {
    invalidateOperation()
    input = ""
    manualSearchTerms = ""
    clearPipelineState()
    message = nil
    failureKind = nil
    clearCompositeSession()
    clarificationServings = ""
    clarificationGrams = ""
    whenEatenAnswer = ""
    consumedAt = .now
    consumedAtInference = nil
    lastSavedEntryID = nil
    lastSavedRecognizedFoodID = nil
    transcript = []
    skipNextUserTranscriptAppend = false
    stage = .idle
  }

  func clearCompositeSession() {
    compositeComponents = []
    pendingCompositeNames = []
    compositeSessionSource = ""
    activeCompositeComponent = nil
    compositeSessionActive = false
  }

  func cancel() {
    invalidateOperation()
    clearInterpretationClarification()
    // Abandon any in-progress multi-food assembly so a later log doesn't merge
    // into it.
    if compositeSessionActive { clearCompositeSession() }
    stage = .idle
    message = nil
    failureKind = nil
  }
}
