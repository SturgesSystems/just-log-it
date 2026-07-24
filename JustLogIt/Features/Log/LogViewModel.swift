import Foundation
import JustLogItCore
import SwiftData
import SwiftUI

/// Transient provenance for a confirmed USDA component. The lookup key is already normalized,
/// so composite saves can improve repeat ranking without copying the meal conversation into the
/// persisted component snapshot.
struct CompositeRememberedChoice: Equatable {
  let lookupSignature: String
  let fdcID: Int
  let displayName: String
  let brand: String?
}

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
  let imageProposer: any FoodImageProposing
  let provider: any FoodDataProviding
  let rememberedFoods: any RememberedFoodStoring
  let queryBuilder = FoodSearchQueryBuilder()
  let resultRanker = FoodSearchResultRanker()
  let resolver = ServingResolutionService()
  let calculator = NutritionCalculator()
  let numberParser: LocalizedNumberParser
  let terminalResolver = FoodInterpretationTerminalResolver()
  var interpretationDraft: FoodInterpretationDraft?
  var operation: Task<Void, Never>?
  var operationGeneration: UInt = 0
  var interactionTimeline: FoodLogInteractionTimeline?
  /// When true, the next `submit()` will not append a user turn (used after edit rewind).
  var skipNextUserTranscriptAppend = false
  var compositeSessionActive = false
  /// Normalized query used by the currently visible component picker.
  var activeCompositeLookupSignature: String?
  /// Confirmed component choices retained only until this composite log is saved or discarded.
  var compositeRememberedChoices: [CompositeRememberedChoice] = []

  var isBuildingComposite: Bool {
    compositeSessionActive
  }

  /// Position of the active component among the meal queue (1-based).
  var compositeMatchingPosition: (index: Int, total: Int)? {
    guard compositeSessionActive, activeCompositeComponent != nil else { return nil }
    return CompositeMatchingProgress.position(
      confirmedCount: compositeComponents.count,
      remainingAfterActive: pendingCompositeNames.count
    )
  }

  /// Typing-bubble label while matching the active composite component.
  var compositeMatchingStatusLabel: String? {
    guard let active = activeCompositeComponent,
      let position = compositeMatchingPosition
    else { return nil }
    return CompositeMatchingProgress.searchingMessage(
      componentLabel: active,
      index: position.index,
      total: position.total
    )
  }

  /// Compact caption for the USDA picker while building a composite.
  var compositePickerCaption: String? {
    guard let active = activeCompositeComponent,
      let position = compositeMatchingPosition
    else { return nil }
    return CompositeMatchingProgress.pickerCaption(
      componentLabel: active,
      index: position.index,
      total: position.total
    )
  }

  init(
    parser: (any FoodDescriptionParsing)? = nil,
    imageProposer: (any FoodImageProposing)? = nil,
    provider: (any FoodDataProviding)? = nil,
    numberParser: LocalizedNumberParser = LocalizedNumberParser(),
    rememberedFoods: (any RememberedFoodStoring)? = nil
  ) {
    self.numberParser = numberParser
    self.imageProposer = imageProposer ?? FoundationModelsImageFoodProposer()
    self.rememberedFoods = rememberedFoods ?? UserDefaultsRememberedFoodStore()
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      let isUITesting = AppLaunchArgumentPolicy.isUITesting(
        arguments: arguments,
        honorsDebugArguments: true
      )
      let hasParserOverride = ["-baseline-parser", "-deterministic-parser", "-hybrid-parser"]
        .contains(where: arguments.contains)
      if let parser {
        self.parser = parser
      } else if isUITesting, let hybridParser = MockHybridFoodParser() {
        self.parser = hybridParser
      } else if isUITesting && !hasParserOverride {
        self.parser = MockFoodParser()
      } else {
        self.parser = Self.makeDefaultParser()
      }
      if let provider {
        self.provider = provider
      } else if isUITesting {
        self.provider = MockFoodDataProvider()
      } else {
        self.provider = FoodDataProviderFactory.make()
      }
    #else
      self.parser = parser ?? Self.makeDefaultParser()
      self.provider = provider ?? FoodDataProviderFactory.make()
    #endif
  }

  deinit {
    operation?.cancel()
  }

  private static func makeDefaultParser() -> any FoodDescriptionParsing {
    FoodParserFactory.make()
  }

  /// Warms a fresh Foundation Models session when the logging surface appears.
  /// Test and fallback parsers simply do not expose this optional capability.
  func prewarmParser() async {
    guard let prewarmingParser = parser as? any FoodDescriptionParserPrewarming else { return }
    await prewarmingParser.prewarm()
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
        // New log after save: clear the prior transcript and meal time first.
        transcript = []
        lastSavedEntryID = nil
        lastSavedRecognizedFoodID = nil
        consumedAt = .now
        consumedAtInference = nil
      }
      appendUserTurn(text)
    }
    // Chat feel: message lives in the transcript; composer returns to empty.
    // Capture `text` for the pipeline — do not re-read `input` after clearing.
    input = ""

    beginInteractionTimeline()
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

    beginInteractionTimeline()
    let generation = beginOperation()
    // Show the photo bubble immediately; replace with the bounded representation after normalize.
    let turnID = UUID()
    transcript.append(.user(id: turnID, text: captionOrNil ?? "", imageData: data))
    stage = .parsing
    let normalizationTask = FoodImageNormalizer.task(for: data)
    operation = Task { [weak self] in
      await self?.preparedImageProposalFlow(
        turnID: turnID,
        normalizationTask: normalizationTask,
        caption: captionOrNil,
        generation: generation)
    }
  }

  /// Surfaces a photo load/decode failure while keeping the text composer available.
  func reportPhotoUnavailable(_ message: String) {
    fail(.interpretation, message: message)
  }

  /// Rewinds the transcript to the given user turn, replaces its text, and re-runs parsing.
  func editUserMessage(id: UUID, newText: String) {
    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard
      let index = transcript.firstIndex(where: { turn in
        if case .user(let turnID, _, _) = turn { return turnID == id }
        return false
      })
    else { return }

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
    beginInteractionTimeline()
    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.submitFlow(text: trimmed, generation: generation)
    }
  }

  func searchManually() {
    beginInteractionTimeline()
    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.manualSearchFlow(generation: generation)
    }
  }

  func select(_ result: FoodSearchResult) {
    beginInteractionTimeline()
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
    beginInteractionTimeline()
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

  /// From review/confirm, re-enter just the amount for the same USDA food — no re-search.
  /// Composite meals keep multi-item amounts fixed (edit time only).
  func editAmountFromReview() {
    guard stage == .reviewing || stage == .confirming else { return }
    guard compositeComponents.isEmpty, let details else { return }
    clarificationServings = ""
    clarificationGrams = ""
    if resolution?.basis == .servings,
      let multiplier = resolution?.servingMultiplier, multiplier > 0
    {
      clarificationServings = Self.formatQuantitySeed(multiplier)
    } else if let grams = resolution?.consumedGrams, grams > 0 {
      clarificationGrams = Self.formatQuantitySeed(grams)
    }
    presentQuantityClarification(explanation: "How much did you have?", food: details)
  }

  /// Backward-compatible alias for `editAmountFromReview()`.
  func adjustQuantity() {
    editAmountFromReview()
  }

  /// From review/confirm, re-open when-eaten with the current time label prefilled.
  /// Keeps selected food, resolution, and nutrients intact.
  func editTimeFromReview() {
    guard stage == .reviewing || stage == .confirming else { return }
    message = nil
    let label = consumedAtInference?.displayLabel
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    whenEatenAnswer = label
    stage = .whenEaten
    appendSystemTurn("When did you eat this?")
  }

  /// Advances from nutrition review: skip “when?” when timing was already clear in the log text.
  func continueFromReview() {
    guard stage == .reviewing else { return }
    message = nil

    // Re-infer in case source text is richer than at review entry.
    refreshConsumedAtInference()
    if let inference = consumedAtInference, inference.isClear {
      consumedAt = inference.date
      appendSystemTurn("Time set to \(inference.displayLabel.lowercased()).")
      stage = .confirming
      return
    }

    whenEatenAnswer = ""
    stage = .whenEaten
    appendSystemTurn("When did you eat this?")
  }

  private static func formatQuantitySeed(_ value: Double) -> String {
    if value.rounded() == value {
      return String(Int(value))
    }
    // Prefer one decimal when the auto-default path produced a simple fraction.
    let one = (value * 10).rounded() / 10
    if one == value || abs(one - value) < 0.000_1 {
      return String(format: "%g", one)
    }
    return String(format: "%g", value)
  }

  func applyWhenEatenSuggestion(_ text: String) {
    whenEatenAnswer = text
    submitWhenEaten()
  }

  func submitWhenEaten() {
    guard stage == .whenEaten else { return }
    let text = whenEatenAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    let display = text.isEmpty ? "Just now" : text

    let resolved = MealTimeInferenceService.resolveAnswer(display)
    guard resolved.wasParsed else {
      message =
        "I couldn’t understand that time. Try “8:30 pm,” “yesterday at 7,” or choose an exact date and time."
      return
    }

    appendUserTurn(display)
    consumedAt = resolved.date
    consumedAtInference = MealTimeInference(
      date: resolved.date,
      displayLabel: resolved.displayLabel,
      isClear: true
    )
    message = nil
    stage = .confirming
  }

  /// Uses the exact picker value as a deterministic remediation for free-form input.
  func useSelectedWhenEatenDate() {
    guard stage == .whenEaten else { return }
    let label = consumedAt.formatted(date: .abbreviated, time: .shortened)
    appendUserTurn(label)
    consumedAtInference = MealTimeInference(date: consumedAt, displayLabel: label, isClear: true)
    whenEatenAnswer = label
    message = nil
    stage = .confirming
  }

  /// Applies clear meal-time cues from the original message onto review.
  /// Preserves an already-clear inference (e.g. Siri/Shortcuts `consumedAt` handoff)
  /// so when-eaten stays skipped and the external timestamp is not overwritten.
  func refreshConsumedAtInference() {
    if let existing = consumedAtInference, existing.isClear {
      consumedAt = existing.date
      return
    }
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
    recordFirstActionableUIIfNeeded()
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
      let anyApproximate =
        draft.components.contains(where: \.isApproximate)
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
    activeCompositeLookupSignature = nil
    compositeRememberedChoices = []
    compositeSessionActive = false
  }

  /// Drops the active component after a failed match and continues the meal with remaining items.
  /// Confirmed components are preserved.
  func skipActiveCompositeComponent() {
    guard compositeSessionActive else { return }
    let skipped = activeCompositeComponent.map(CompositeMatchingProgress.displayLabel(for:)) ?? "item"
    invalidateOperation()
    activeCompositeComponent = nil
    activeCompositeLookupSignature = nil
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    message = nil
    failureKind = nil
    appendSystemTurn("Skipped \(skipped).")
    let generation = beginOperation()
    if pendingCompositeNames.isEmpty {
      if compositeComponents.isEmpty {
        clearCompositeSession()
        fail(.interpretation, message: "No foods were added to the meal.")
      } else {
        finishCompositeAssembly()
      }
    } else {
      advanceCompositeQueue(generation: generation)
    }
  }

  /// Whether recovery can skip the active composite component without discarding prior items.
  var canSkipActiveCompositeComponent: Bool {
    compositeSessionActive && activeCompositeComponent != nil
      && (stage == .failed || stage == .choosing)
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
