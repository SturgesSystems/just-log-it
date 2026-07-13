import Foundation
import JustLogItCore
import SwiftData
import SwiftUI

/// A single turn in the logging conversation transcript.
enum ConversationTurn: Identifiable, Equatable {
  /// User text, optionally with a photo (bytes stay on-device for the session only).
  case user(id: UUID, text: String, imageData: Data?)
  case system(id: UUID, text: String)

  var id: UUID {
    switch self {
    case .user(let id, _, _), .system(let id, _):
      return id
    }
  }

  var isUser: Bool {
    if case .user = self { return true }
    return false
  }

  var text: String {
    switch self {
    case .user(_, let text, _), .system(_, let text):
      return text
    }
  }

  var imageData: Data? {
    if case .user(_, _, let data) = self { return data }
    return nil
  }
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
  @Published private(set) var stage: Stage = .idle
  @Published private(set) var parsed: ParsedFoodRequest?
  @Published private(set) var results: [FoodSearchResult] = []
  @Published private(set) var selectedResult: FoodSearchResult?
  @Published private(set) var details: FoodDetails?
  @Published private(set) var resolution: ServingResolution?
  @Published private(set) var nutrients: [NutrientAmount] = []
  @Published private(set) var message: String?
  @Published private(set) var failureKind: FailureKind?
  @Published private(set) var activeQuestion: ClarificationQuestion?
  @Published var clarificationAnswer = ""
  @Published var clarificationServings = ""
  @Published var clarificationGrams = ""
  @Published var showManualEntry = false
  /// When non-empty, `makeRecord()` saves a multi-component composite entry.
  @Published private(set) var compositeComponents: [CompositeComponentSnapshot] = []
  /// Remaining component names while assembling a multi-food log.
  @Published private(set) var pendingCompositeNames: [String] = []
  /// Human label for the meal while building composites (original user text).
  @Published private(set) var compositeSessionSource: String = ""
  /// Which component is currently being matched (for UI chrome).
  @Published private(set) var activeCompositeComponent: String?

  @Published private(set) var transcript: [ConversationTurn] = []
  @Published var whenEatenAnswer = ""
  @Published private(set) var consumedAt: Date = .now
  /// When set from clear wording (“just ate”, “for breakfast”), shown on review and we skip asking.
  @Published private(set) var consumedAtInference: MealTimeInference?
  @Published private(set) var lastSavedEntryID: UUID?
  @Published private(set) var lastSavedRecognizedFoodID: UUID?

  /// Chips for the when-eaten step (meal-aware when we have a soft inference).
  var whenEatenSuggestionChips: [String] {
    MealTimeInferenceService.suggestionChips(for: consumedAtInference)
  }

  private let parser: any FoodDescriptionParsing
  private let imageProposer: FoundationModelsImageFoodProposer
  private let provider: any FoodDataProviding
  private let rememberedFoods: any RememberedFoodStoring
  private let queryBuilder = FoodSearchQueryBuilder()
  private let resultRanker = FoodSearchResultRanker()
  private let resolver = ServingResolutionService()
  private let calculator = NutritionCalculator()
  private let numberParser: LocalizedNumberParser
  private let interpretationValidator = FoodInterpretationValidator()
  private let clarificationPolicy = ClarificationPolicy()
  private var interpretationDraft: FoodInterpretationDraft?
  private var operation: Task<Void, Never>?
  private var operationGeneration: UInt = 0
  /// When true, the next `submit()` will not append a user turn (used after edit rewind).
  private var skipNextUserTranscriptAppend = false
  private var compositeSessionActive = false

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
    } else if stage == .idle || stage == .completed || transcript.isEmpty {
      if stage == .completed {
        // New log after save: clear prior transcript first.
        transcript = []
        lastSavedEntryID = nil
        lastSavedRecognizedFoodID = nil
      }
      appendUserTurn(text)
    } else if stage == .failed {
      // Replacing the description after failure — treat as a fresh user turn.
      appendUserTurn(text)
    } else {
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
    let parseInput = Self.clarificationParseInput(
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

  /// Builds the model input for a clarification turn (facts + reply, not a fake food name).
  static func clarificationParseInput(
    sourceText: String,
    priorProduct: String,
    question: String,
    answer: String
  ) -> String {
    let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    let product = priorProduct.trimmingCharacters(in: .whitespacesAndNewlines)
    let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = ["Food log conversation for USDA lookup:"]
    if !source.isEmpty {
      lines.append("Original user message: \(source)")
    }
    if !product.isEmpty {
      lines.append("Current food candidate (may be wrong or empty): \(product)")
    }
    if !asked.isEmpty {
      lines.append("Assistant asked: \(asked)")
    }
    lines.append("User replied: \(reply)")
    lines.append(
      "Use the original message plus the reply. If the reply does not name or refine a real food (dismissive, off-topic, or empty of food facts), leave productName empty and write clarificationPrompt asking for the food. Do not treat phrases like \"who cares\", \"idk\", \"whatever\", or \"n/a\" as food names."
    )
    return lines.joined(separator: "\n")
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

  /// Applies a quantity suggestion or freeform text such as "1 serving" / "100 g" / "1 cup".
  func applyQuantitySuggestion(_ suggestion: String) {
    let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // "1 serving", "100 g", "1.5 cup"
    let pattern = #"^\s*([0-9]+(?:[.,][0-9]+)?)\s*([A-Za-z].*)?$"#
    if let regex = try? NSRegularExpression(pattern: pattern),
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
  private func refreshConsumedAtInference() {
    let source = loggingSourceText
    let inference = MealTimeInferenceService.infer(from: source)
    consumedAtInference = inference
    if inference.isClear {
      consumedAt = inference.date
    }
  }

  private func presentReview() {
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
  private var loggingSourceText: String {
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

  private func clearCompositeSession() {
    compositeComponents = []
    pendingCompositeNames = []
    compositeSessionSource = ""
    activeCompositeComponent = nil
    compositeSessionActive = false
  }

  func cancel() {
    invalidateOperation()
    clearInterpretationClarification()
    stage = .idle
    message = nil
    failureKind = nil
  }

  // MARK: - Private

  private func appendUserTurn(_ text: String, imageData: Data? = nil) {
    transcript.append(.user(id: UUID(), text: text, imageData: imageData))
  }

  private func appendSystemTurn(_ text: String) {
    transcript.append(.system(id: UUID(), text: text))
  }

  private func clearPipelineState() {
    parsed = nil
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    clearInterpretationClarification()
    clarificationServings = ""
    clarificationGrams = ""
    // Abort in-flight multi-food assembly when rewinding/canceling the pipeline.
    if compositeSessionActive {
      clearCompositeSession()
    }
  }

  private func beginOperation() -> UInt {
    invalidateOperation()
    failureKind = nil
    return operationGeneration
  }

  private func invalidateOperation() {
    operation?.cancel()
    operation = nil
    operationGeneration &+= 1
  }

  private func isCurrentOperation(_ generation: UInt) -> Bool {
    operationGeneration == generation && !Task.isCancelled
  }

  private func submitFlow(text: String, generation: UInt) async {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      fail(.interpretation, message: "Enter a food description first.")
      return
    }

    await runInterpretation(
      parseInput: text,
      evidenceText: text,
      turnCount: 0,
      generation: generation
    )
  }

  /// Re-interpret after a clarification reply (model harness — not field patching).
  private func clarificationReparseFlow(
    parseInput: String,
    evidenceText: String,
    turnCount: Int,
    generation: UInt
  ) async {
    await runInterpretation(
      parseInput: parseInput,
      evidenceText: evidenceText,
      turnCount: turnCount,
      generation: generation
    )
  }

  private func runInterpretation(
    parseInput: String,
    evidenceText: String,
    turnCount: Int,
    generation: UInt
  ) async {
    stage = .parsing
    message = nil
    failureKind = nil
    clearInterpretationClarification()
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    whenEatenAnswer = ""
    consumedAt = .now

    let request: ParsedFoodRequest
    do {
      let parsed = try await parser.parse(parseInput)
      guard isCurrentOperation(generation) else { return }

      let draft = interpretationValidator.draft(
        from: parsed,
        sourceText: evidenceText,
        evidenceKind: .typedText,
        turnCount: turnCount
      )
      interpretationDraft = draft
      switch clarificationPolicy.decide(draft) {
      case .proceed(let proceeded):
        self.parsed = proceeded
        manualSearchTerms = queryBuilder.build(from: proceeded).query
        request = proceeded
        // No status log — the USDA picker is the next conversational beat.
      case .beginComposite(let names, let sourceText):
        beginCompositeSession(componentNames: names, sourceText: sourceText, generation: generation)
        return
      case .clarify(let question):
        presentInterpretationClarification(
          question, draft: draft, sourceText: evidenceText)
        return
      case .requireEdit(let message):
        manualSearchTerms = evidenceText
        fail(.interpretation, message: message)
        return
      case .fallbackManual(let message):
        manualSearchTerms = evidenceText
        fail(.interpretation, message: message)
        return
      }
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      let failureMessage =
        (error as? LocalizedError)?.errorDescription
        ?? "On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually."
      fail(.interpretation, message: failureMessage)
      return
    }

    await runSearch(for: request, generation: generation)
  }

  private func imageProposalFlow(
    data: Data,
    caption: String?,
    generation: UInt
  ) async {
    stage = .parsing
    message = nil
    failureKind = nil
    clearInterpretationClarification()
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    whenEatenAnswer = ""
    consumedAt = .now

    do {
      let proposed = try await imageProposer.propose(imageData: data, caption: caption)
      guard isCurrentOperation(generation) else { return }

      let sourceText = caption ?? proposed.productName
      input = sourceText
      // Photo already appears in the transcript from proposeFromImage.

      let draft = interpretationValidator.draft(
        from: proposed,
        sourceText: sourceText,
        evidenceKind: .photoObservation
      )
      interpretationDraft = draft
      switch clarificationPolicy.decide(draft) {
      case .proceed(let proceeded):
        parsed = proceeded
        manualSearchTerms = queryBuilder.build(from: proceeded).query
        await runSearch(for: proceeded, generation: generation)
      case .beginComposite(let names, let sourceText):
        beginCompositeSession(componentNames: names, sourceText: sourceText, generation: generation)
      case .clarify(let question):
        presentInterpretationClarification(question, draft: draft, sourceText: sourceText)
      case .requireEdit(let message):
        manualSearchTerms = sourceText
        fail(.interpretation, message: message)
      case .fallbackManual(let message):
        manualSearchTerms = sourceText
        fail(.interpretation, message: message)
      }
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      if let caption {
        input = caption
        manualSearchTerms = caption
      }
      let failureMessage =
        (error as? FoodParserError)?.errorDescription
        ?? "Photo identification wasn’t available. Describe the food in text or enter nutrition manually."
      fail(.interpretation, message: failureMessage)
    }
  }

  /// Routes a policy decision after the user answers an interpretation question.
  private func routeInterpretationDecision(
    _ decision: ClarificationDecision,
    sourceText: String,
    generation: UInt
  ) {
    switch decision {
    case .proceed(let proceeded):
      clearInterpretationClarification(keepDraft: false)
      parsed = proceeded
      manualSearchTerms = queryBuilder.build(from: proceeded).query
      operation = Task { [weak self] in
        await self?.runSearch(for: proceeded, generation: generation)
      }
    case .beginComposite(let names, let compositeSource):
      clearInterpretationClarification(keepDraft: false)
      beginCompositeSession(
        componentNames: names, sourceText: compositeSource, generation: generation)
    case .clarify(let question):
      if let draft = interpretationDraft {
        presentInterpretationClarification(question, draft: draft, sourceText: sourceText)
      } else {
        manualSearchTerms = sourceText
        fail(.interpretation, message: question.prompt)
      }
    case .requireEdit(let message):
      manualSearchTerms = sourceText
      fail(.interpretation, message: message)
    case .fallbackManual(let message):
      manualSearchTerms = sourceText
      fail(.interpretation, message: message)
    }
  }

  // MARK: - Composite multi-food session

  private func beginCompositeSession(
    componentNames: [String],
    sourceText: String,
    generation: UInt
  ) {
    let names = componentNames
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard names.count >= 2 else {
      fail(.interpretation, message: "Couldn’t split that into separate foods. Try naming them.")
      return
    }
    compositeSessionActive = true
    compositeSessionSource = sourceText
    compositeComponents = []
    pendingCompositeNames = names
    let list = names.joined(separator: " · ")
    appendSystemTurn("I'll look up \(list) separately and put them in one log.")
    advanceCompositeQueue(generation: generation)
  }

  private func advanceCompositeQueue(generation: UInt) {
    guard let next = pendingCompositeNames.first else {
      finishCompositeAssembly()
      return
    }
    pendingCompositeNames.removeFirst()
    activeCompositeComponent = next
    // Keep leading counts ("1 Big Mac") so quantity resolves after USDA pick.
    let request = CompositeComponentRequest.make(from: next)
    parsed = request
    manualSearchTerms = request.searchTerms.isEmpty ? next : request.searchTerms
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    let ordinal =
      compositeComponents.isEmpty
      ? "First"
      : "Next"
    appendSystemTurn("\(ordinal): \(next).")
    operation = Task { [weak self] in
      await self?.runSearch(for: request, generation: generation)
    }
  }

  private func finishCompositeAssembly() {
    compositeSessionActive = false
    activeCompositeComponent = nil
    pendingCompositeNames = []
    guard !compositeComponents.isEmpty else {
      fail(.interpretation, message: "No foods were added to the meal.")
      return
    }
    let draft = CompositeDraftBuilder.make(
      name: nil,
      components: compositeComponents
    )
    nutrients = draft.totalNutrients
    parsed = ParsedFoodRequest(
      productName: draft.name,
      searchTerms: draft.name,
      containsMultipleFoods: true,
      componentNames: compositeComponents.map(\.displayName)
    )
    // Review uses composite components; single-food details are optional.
    details = nil
    resolution = nil
    selectedResult = nil
    results = []
    message = nil
    appendSystemTurn("Here's the meal together.")
    presentReview()
  }

  private func commitCompositeComponentIfNeeded() -> Bool {
    guard compositeSessionActive, let details, let resolution else { return false }
    let snap = CompositeComponentSnapshot(
      displayName: details.description,
      brand: details.brandOwner,
      fdcID: details.fdcID,
      quantityDisplay: resolution.displayText,
      nutrients: nutrients,
      isApproximate: parsed?.isApproximate == true
    )
    compositeComponents.append(snap)
    let generation = beginOperation()
    if pendingCompositeNames.isEmpty {
      finishCompositeAssembly()
    } else {
      advanceCompositeQueue(generation: generation)
    }
    return true
  }

  private func presentInterpretationClarification(
    _ question: ClarificationQuestion,
    draft: FoodInterpretationDraft,
    sourceText: String
  ) {
    interpretationDraft = draft
    activeQuestion = question
    message = question.prompt
    failureKind = nil
    if manualSearchTerms.isEmpty {
      manualSearchTerms = sourceText
    }
    stage = .awaitingClarification
    appendSystemTurn(question.prompt)
  }

  private func clearInterpretationClarification(keepDraft: Bool = false) {
    activeQuestion = nil
    clarificationAnswer = ""
    if !keepDraft {
      interpretationDraft = nil
    }
  }

  private func runSearch(for request: ParsedFoodRequest, generation: UInt) async {
    // Bare identity ("a Big Mac") → 1 serving so we can resolve without a quantity prompt.
    let withQuantity = ParsedQuantityDefault.applyingDefaultIfNeeded(request)
    parsed = withQuantity
    do {
      try await search(
        queryBuilder.build(from: withQuantity),
        rankingIntent: withQuantity,
        generation: generation
      )
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      fail(
        .search,
        message: (error as? LocalizedError)?.errorDescription ?? "Food search failed."
      )
    }
  }

  private func manualSearchFlow(generation: UInt) async {
    let request = queryBuilder.manual(manualSearchTerms)
    guard !request.query.isEmpty else {
      fail(.search, message: "Enter food search terms first.")
      return
    }
    if parsed == nil {
      parsed = ParsedFoodRequest(productName: request.query, searchTerms: request.query)
    }
    // Manual re-search clears a prior selection / review.
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    whenEatenAnswer = ""
    do {
      let rankingIntent = ParsedFoodRequest(productName: request.query, searchTerms: request.query)
      try await search(request, rankingIntent: rankingIntent, generation: generation)
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      fail(
        .search,
        message: (error as? LocalizedError)?.errorDescription ?? "Food search failed."
      )
    }
  }

  private func search(
    _ request: FoodSearchRequest,
    rankingIntent: ParsedFoodRequest,
    generation: UInt
  ) async throws {
    stage = .searching
    #if DEBUG
      let response = try await AppPerformanceTrace.measure("USDA search") {
        try await provider.search(request)
      }
    #else
      let response = try await provider.search(request)
    #endif
    guard isCurrentOperation(generation) else { return }
    let preferred = rememberedFoods.load().preferredFdcIDs(forQuery: request.query)
    results = resultRanker.rank(
      response.foods, for: rankingIntent, preferredFdcIDs: preferred)
    if results.isEmpty {
      fail(
        .noResults,
        message: "No USDA foods matched. Edit the search or enter nutrition manually."
      )
      return
    }

    // Strong identity (Big Mac, remembered pick, single clear hit) → skip the picker.
    // User can still choose a different food from review.
    if let auto = FoodSearchAutoSelect.highConfidencePick(
      ranked: results,
      for: rankingIntent,
      preferredFdcIDs: preferred
    ) {
      selectedResult = auto
      let label = auto.description.trimmingCharacters(in: .whitespacesAndNewlines)
      if !label.isEmpty {
        appendSystemTurn("Using \(label).")
      }
      await selectionFlow(auto, generation: generation)
      return
    }

    stage = .choosing
  }

  private func selectionFlow(_ result: FoodSearchResult, generation: UInt) async {
    stage = .loadingDetails
    message = nil
    do {
      let details = try await provider.foodDetails(fdcID: result.fdcID)
      guard isCurrentOperation(generation) else { return }
      self.details = details
      // Default amount if still missing (manual pick without quantity in the parse).
      let request =
        parsed.map { ParsedQuantityDefault.applyingDefaultIfNeeded($0) }
        ?? ParsedQuantityDefault.applyingDefaultIfNeeded(
          ParsedFoodRequest(productName: details.description, searchTerms: details.description)
        )
      parsed = request
      apply(resolver.resolve(request, against: details))
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      fail(
        .details,
        message: (error as? LocalizedError)?.errorDescription
          ?? "The selected food details could not be loaded."
      )
    }
  }

  private func fail(_ kind: FailureKind, message: String) {
    clearInterpretationClarification()
    failureKind = kind
    self.message = message
    stage = .failed
    // Single assistant bubble — the recovery card only offers actions, not a second copy.
    if transcript.last?.text != message {
      appendSystemTurn(message)
    }
  }

  private func apply(_ outcome: ServingResolutionOutcome) {
    switch outcome {
    case .needsClarification(let explanation):
      if let details {
        presentQuantityClarification(explanation: explanation, food: details)
      } else {
        stage = .clarifying
        message = explanation
        activeQuestion = ClarificationQuestion.quantity(explanation: explanation)
      }
    case .resolved(let resolution):
      guard let details else { return }
      do {
        nutrients = try calculator.calculate(food: details, resolution: resolution)
        guard nutrients.contains(where: { $0.key == .energy }) else {
          presentQuantityClarification(
            explanation:
              "This USDA record does not provide enough compatible nutrition data. Choose another result or enter nutrition manually.",
            food: details,
            code: .missingQuantity
          )
          return
        }
        activeQuestion = nil
        self.resolution = resolution
        message = nil
        if commitCompositeComponentIfNeeded() {
          return
        }
        presentReview()
      } catch {
        presentQuantityClarification(
          explanation:
            "The serving and nutrition bases could not be combined safely. Enter servings or grams.",
          food: details
        )
      }
    }
  }

  private func presentQuantityClarification(
    explanation: String,
    food: FoodDetails,
    code: AmbiguityCode = .missingQuantity
  ) {
    let grams: Double? = {
      guard let size = food.servingSize, size.isFinite, size > 0 else { return nil }
      let unit = food.servingSizeUnit?.lowercased() ?? ""
      if unit == "g" || unit == "gram" || unit == "grams" { return size }
      return nil
    }()
    let question = ClarificationQuestion.quantity(
      explanation: explanation,
      householdServing: food.householdServing,
      servingSizeGrams: grams,
      code: code
    )
    activeQuestion = question
    message = question.prompt
    failureKind = nil
    stage = .clarifying
    appendSystemTurn(question.prompt)
  }

  /// Records a confirmed USDA pick for future ranking boosts only — never auto-selects.
  private func rememberConfirmedSelectionIfPossible() {
    if !compositeComponents.isEmpty {
      var catalog = rememberedFoods.load()
      for component in compositeComponents {
        guard let fdcID = component.fdcID, fdcID > 0 else { continue }
        catalog.remember(
          query: component.displayName,
          fdcID: fdcID,
          displayName: component.displayName,
          brand: component.brand
        )
      }
      rememberedFoods.save(catalog)
      return
    }
    guard let details, details.fdcID > 0 else { return }
    let query =
      manualSearchTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? (parsed?.searchTerms ?? parsed?.productName ?? input)
      : manualSearchTerms
    var catalog = rememberedFoods.load()
    catalog.remember(
      query: query,
      fdcID: details.fdcID,
      displayName: details.description,
      brand: details.brandOwner ?? parsed?.brand
    )
    rememberedFoods.save(catalog)
  }

}

private struct MockFoodDataProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(
          fdcID: 999_001, description: "EGGS, SCRAMBLED", dataType: "Survey (FNDDS)",
          servingSize: 100, servingSizeUnit: "g", householdServing: "1 serving")
      ],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "Eggs, scrambled",
      dataType: "Survey (FNDDS)",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 serving",
      nutrientsPer100Grams: [
        NutrientAmount(key: .energy, amount: 148),
        NutrientAmount(key: .protein, amount: 10),
        NutrientAmount(key: .carbohydrate, amount: 1.6),
        NutrientAmount(key: .totalFat, amount: 11),
      ]
    )
  }
}
