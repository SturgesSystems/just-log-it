import Foundation
import JustLogItCore
import SwiftData
import SwiftUI

// Internal pipeline for LogViewModel: interpretation, search, composite
// assembly, resolution, and transcript/operation plumbing.
extension LogViewModel {
  func beginInteractionTimeline(at instant: ContinuousClock.Instant = .now) {
    interactionTimeline = FoodLogInteractionTimeline(startedAt: instant)
  }

  func recordUSDARequestDispatchIfNeeded(at instant: ContinuousClock.Instant = .now) {
    guard var timeline = interactionTimeline else { return }
    let measurement = timeline.markUSDARequestDispatch(at: instant)
    interactionTimeline = timeline
    if let measurement {
      AppObservability.recordMilestone(measurement.milestone, duration: measurement.duration)
    }
  }

  func recordFirstActionableUIIfNeeded(at instant: ContinuousClock.Instant = .now) {
    guard var timeline = interactionTimeline else { return }
    let measurement = timeline.markFirstActionableUI(at: instant)
    interactionTimeline = timeline
    if let measurement {
      AppObservability.recordMilestone(measurement.milestone, duration: measurement.duration)
    }
  }

  func appendUserTurn(_ text: String, imageData: Data? = nil) {
    transcript.append(.user(id: UUID(), text: text, imageData: imageData))
  }

  func appendSystemTurn(_ text: String) {
    transcript.append(.system(id: UUID(), text: text))
  }

  /// Replaces the image bytes on an existing user turn (optimistic photo → bounded prep).
  func updateUserTurnImage(id: UUID, imageData: Data) {
    guard let index = transcript.firstIndex(where: { $0.id == id }),
      case .user(_, let text, _) = transcript[index]
    else { return }
    transcript[index] = .user(id: id, text: text, imageData: imageData)
  }

  func removeUserTurn(id: UUID) {
    transcript.removeAll { $0.id == id }
  }

  func clearPipelineState() {
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

  func beginOperation() -> UInt {
    invalidateOperation()
    failureKind = nil
    return operationGeneration
  }

  func invalidateOperation() {
    operation?.cancel()
    operation = nil
    operationGeneration &+= 1
  }

  func isCurrentOperation(_ generation: UInt) -> Bool {
    operationGeneration == generation && !Task.isCancelled
  }

  func submitFlow(text: String, generation: UInt) async {
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
  func clarificationReparseFlow(
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

  func runInterpretation(
    parseInput: String,
    evidenceText: String,
    turnCount: Int,
    generation: UInt
  ) async {
    stage = .parsing
    message = nil
    failureKind = nil
    clearInterpretationClarification()
    // A fresh interpretation must not inherit an abandoned multi-food session.
    if compositeSessionActive { clearCompositeSession() }
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    whenEatenAnswer = ""
    // Keep a clear handoff time (Siri/Shortcuts consumedAt); otherwise start from now.
    if consumedAtInference?.isClear != true {
      consumedAt = .now
    }

    let request: ParsedFoodRequest
    do {
      let terminalResolution: FoodInterpretationTerminalResolution
      if let resolvingParser = parser as? any FoodDescriptionTerminalResolving {
        terminalResolution = try await resolvingParser.resolveForApplication(
          semanticContext: parseInput,
          groundingText: evidenceText,
          turnCount: turnCount
        )
      } else {
        let parsed = try await parser.parse(
          semanticContext: parseInput,
          groundingText: evidenceText
        )
        terminalResolution = terminalResolver.resolve(
          parsed,
          sourceText: evidenceText,
          evidenceKind: .typedText,
          turnCount: turnCount,
          searchRoute: .onDeviceSemantic
        )
      }
      guard isCurrentOperation(generation) else { return }

      let draft = terminalResolution.draft
      interpretationDraft = draft
      switch terminalResolution.decision {
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
      // Preserve the user's text so the manual-search / recovery path isn't blank
      // when the on-device model is unavailable or errors out.
      manualSearchTerms = evidenceText
      let failureMessage =
        (error as? LocalizedError)?.errorDescription
        ?? "On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually."
      fail(.interpretation, message: failureMessage)
      return
    }

    await runSearch(for: request, generation: generation)
  }

  func imageProposalFlow(
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
    // Keep a clear handoff time (Siri/Shortcuts consumedAt); otherwise start from now.
    if consumedAtInference?.isClear != true {
      consumedAt = .now
    }
    // A fresh interpretation must not inherit an abandoned multi-food session.
    if compositeSessionActive { clearCompositeSession() }

    do {
      let proposed = try await imageProposer.propose(imageData: data, caption: caption)
      guard isCurrentOperation(generation) else { return }

      let sourceText = caption ?? proposed.productName
      input = sourceText
      // Photo bubble was appended in proposeFromImage (then swapped to bounded bytes).

      let terminalResolution = terminalResolver.resolve(
        proposed,
        sourceText: sourceText,
        evidenceKind: .photoObservation,
        searchRoute: .onDeviceSemantic
      )
      let draft = terminalResolution.draft
      interpretationDraft = draft
      switch terminalResolution.decision {
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

  /// Awaits the off-main image preparation task, then swaps the optimistic transcript photo for the
  /// same bounded bytes the model receives. On cancel/supersede/failure the optimistic turn is
  /// removed so multi-meg originals are not retained.
  func preparedImageProposalFlow(
    turnID: UUID,
    normalizationTask: Task<Data, any Error>,
    caption: String?,
    generation: UInt
  ) async {
    do {
      let preparedData = try await withTaskCancellationHandler {
        try await normalizationTask.value
      } onCancel: {
        normalizationTask.cancel()
      }
      guard isCurrentOperation(generation) else {
        removeUserTurn(id: turnID)
        return
      }
      updateUserTurnImage(id: turnID, imageData: preparedData)
      await imageProposalFlow(data: preparedData, caption: caption, generation: generation)
    } catch is CancellationError {
      removeUserTurn(id: turnID)
      return
    } catch {
      removeUserTurn(id: turnID)
      guard isCurrentOperation(generation) else { return }
      let failureMessage =
        (error as? LocalizedError)?.errorDescription
        ?? "That photo could not be prepared. Describe the food in text instead."
      fail(.interpretation, message: failureMessage)
    }
  }

  /// Routes a policy decision after the user answers an interpretation question.
  func routeInterpretationDecision(
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

  func beginCompositeSession(
    componentNames: [String],
    sourceText: String,
    generation: UInt
  ) {
    let names =
      componentNames
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard names.count >= 2 else {
      fail(.interpretation, message: "Couldn’t split that into separate foods. Try naming them.")
      return
    }
    compositeSessionActive = true
    compositeSessionSource = sourceText
    compositeComponents = []
    compositeRememberedChoices = []
    activeCompositeLookupSignature = nil
    pendingCompositeNames = names
    let list = names.joined(separator: " · ")
    appendSystemTurn("I'll look up \(list) separately and put them in one log.")
    advanceCompositeQueue(generation: generation)
  }

  func advanceCompositeQueue(generation: UInt) {
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
    message = nil
    failureKind = nil
    let position = CompositeMatchingProgress.position(
      confirmedCount: compositeComponents.count,
      remainingAfterActive: pendingCompositeNames.count
    )
    appendSystemTurn(
      CompositeMatchingProgress.queueTurn(
        componentLabel: next,
        index: position.index,
        total: position.total
      )
    )
    operation = Task { [weak self] in
      await self?.runSearch(for: request, generation: generation)
    }
  }

  func finishCompositeAssembly() {
    compositeSessionActive = false
    activeCompositeComponent = nil
    activeCompositeLookupSignature = nil
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

  func commitCompositeComponentIfNeeded() -> Bool {
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
    if let signature = activeCompositeLookupSignature, !signature.isEmpty, details.fdcID > 0 {
      compositeRememberedChoices.append(
        CompositeRememberedChoice(
          lookupSignature: signature,
          fdcID: details.fdcID,
          displayName: details.description,
          brand: details.brandOwner
        )
      )
    }
    let generation = beginOperation()
    if pendingCompositeNames.isEmpty {
      finishCompositeAssembly()
    } else {
      advanceCompositeQueue(generation: generation)
    }
    return true
  }

  func presentInterpretationClarification(
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
    recordFirstActionableUIIfNeeded()
    appendSystemTurn(question.prompt)
  }

  func clearInterpretationClarification(keepDraft: Bool = false) {
    activeQuestion = nil
    clarificationAnswer = ""
    if !keepDraft {
      interpretationDraft = nil
    }
  }

  func runSearch(for request: ParsedFoodRequest, generation: UInt) async {
    let sourceText = loggingSourceText
    let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(in: request, from: sourceText)
    // Keep missing quantity missing until selected USDA details prove that one
    // serving has a safe basis. An explicit amount that could not be recovered
    // also remains missing so post-USDA resolution can ask instead of guessing.
    let withQuantity = ParsedQuantityDefault.applyingDefaultIfNeeded(
      recovered,
      sourceText: sourceText
    )
    parsed = withQuantity
    do {
      try await search(
        queryBuilder.build(from: withQuantity),
        rankingIntent: withQuantity,
        generation: generation,
        allowsAutoSelection: true
      )
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      fail(.search, message: FoodDataUserMessage.searchFailure(error))
    }
  }

  func manualSearchFlow(generation: UInt) async {
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
      try await search(
        request,
        rankingIntent: rankingIntent,
        generation: generation,
        allowsAutoSelection: false
      )
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      fail(.search, message: FoodDataUserMessage.searchFailure(error))
    }
  }

  func search(
    _ request: FoodSearchRequest,
    rankingIntent: ParsedFoodRequest,
    generation: UInt,
    allowsAutoSelection: Bool
  ) async throws {
    stage = .searching
    if compositeSessionActive {
      // Capture exactly the normalized lookup key used for this picker. USDA's display label can
      // be materially different (for example, query "eggs" → "Egg, whole, cooked, scrambled").
      activeCompositeLookupSignature = FoodLookupSignature.normalize(request.query)
    }
    recordUSDARequestDispatchIfNeeded()
    let response = try await AppObservability.measure(.usdaSearchPipeline) {
      let response = try await provider.search(request)
      return response
    }
    guard isCurrentOperation(generation) else { return }
    let preferred = rememberedFoods.load().preferredFdcIDs(forQuery: request.query)
    results = AppObservability.measure(.usdaRanking) {
      resultRanker.rank(response.foods, for: rankingIntent, preferredFdcIDs: preferred)
    }
    AppObservability.recordCount(.rankedSearchResults, .init(results.count))
    if results.isEmpty {
      fail(
        .noResults,
        message: "No USDA foods matched. Edit the search or enter nutrition manually."
      )
      return
    }

    // Strong identity (Big Mac, remembered pick, single clear hit) → skip the picker.
    // User can still choose a different food from review.
    if allowsAutoSelection,
      let auto = FoodSearchAutoSelect.highConfidencePick(
        ranked: results,
        for: rankingIntent,
        preferredFdcIDs: preferred
      )
    {
      selectedResult = auto
      let label = auto.description.trimmingCharacters(in: .whitespacesAndNewlines)
      if !label.isEmpty {
        appendSystemTurn("Using \(label).")
      }
      await selectionFlow(auto, generation: generation)
      return
    }

    stage = .choosing
    recordFirstActionableUIIfNeeded()
  }

  func selectionFlow(_ result: FoodSearchResult, generation: UInt) async {
    stage = .loadingDetails
    message = nil
    do {
      let details = try await AppObservability.measure(.usdaDetailPipeline) {
        try await provider.foodDetails(fdcID: result.fdcID)
      }
      guard isCurrentOperation(generation) else { return }
      self.details = details
      // Default amount if still missing (manual pick without quantity in the parse).
      let sourceText = loggingSourceText
      let request =
        parsed.map {
          let recovered = ParsedQuantityRecovery.recoveringSimpleAmount(
            in: $0,
            from: sourceText
          )
          return ParsedQuantityDefault.applyingDefaultIfNeeded(
            recovered,
            sourceText: sourceText,
            selectedFood: details
          )
        }
        ?? ParsedQuantityDefault.applyingDefaultIfNeeded(
          ParsedFoodRequest(productName: details.description, searchTerms: details.description),
          sourceText: sourceText,
          selectedFood: details
        )
      parsed = request
      apply(resolver.resolve(request, against: details))
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      fail(.details, message: FoodDataUserMessage.detailsFailure(error))
    }
  }

  func fail(_ kind: FailureKind, message: String) {
    clearInterpretationClarification()
    failureKind = kind
    // Keep confirmed composite components; rephrase search/detail failures so recovery is clear.
    let resolvedMessage: String
    if compositeSessionActive,
      let component = activeCompositeComponent,
      kind == .search || kind == .noResults || kind == .details
    {
      let detail: String
      switch kind {
      case .noResults: detail = "No USDA foods matched."
      case .search: detail = "USDA lookup failed."
      case .details: detail = "Couldn’t load nutrition for that food."
      case .interpretation: detail = message
      }
      resolvedMessage = CompositeMatchingProgress.failureMessage(
        componentLabel: component,
        confirmedCount: compositeComponents.count,
        detail: detail
      )
    } else {
      resolvedMessage = message
    }
    self.message = resolvedMessage
    stage = .failed
    recordFirstActionableUIIfNeeded()
    // Single assistant bubble — the recovery card only offers actions, not a second copy.
    if transcript.last?.text != resolvedMessage {
      appendSystemTurn(resolvedMessage)
    }
  }

  func apply(_ outcome: ServingResolutionOutcome) {
    switch outcome {
    case .needsClarification(let explanation):
      if let details {
        presentQuantityClarification(explanation: explanation, food: details)
      } else {
        stage = .clarifying
        recordFirstActionableUIIfNeeded()
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

  func presentQuantityClarification(
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
    recordFirstActionableUIIfNeeded()
    appendSystemTurn(question.prompt)
  }

  /// Records a confirmed USDA pick for future ranking boosts only — never auto-selects.
  func rememberConfirmedSelectionIfPossible() {
    if !compositeComponents.isEmpty {
      var catalog = rememberedFoods.load()
      for choice in compositeRememberedChoices {
        catalog.remember(
          query: choice.lookupSignature,
          fdcID: choice.fdcID,
          displayName: choice.displayName,
          brand: choice.brand
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
