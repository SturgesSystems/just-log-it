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

  private let parser: any FoodDescriptionParsing
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

  init(
    parser: (any FoodDescriptionParsing)? = nil,
    provider: (any FoodDataProviding)? = nil,
    numberParser: LocalizedNumberParser = LocalizedNumberParser(),
    rememberedFoods: (any RememberedFoodStoring)? = nil
  ) {
    self.numberParser = numberParser
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
    let generation = beginOperation()
    operation = Task { [weak self] in
      await self?.submitFlow(generation: generation)
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
  func submitClarificationAnswer() {
    let answer = clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !answer.isEmpty, let question = activeQuestion, let draft = interpretationDraft else {
      return
    }
    let updated = clarificationPolicy.applyUserAnswer(answer, to: draft, for: question)
    interpretationDraft = updated
    clarificationAnswer = ""
    routeInterpretationDecision(
      clarificationPolicy.decide(updated),
      sourceText: updated.sourceText.isEmpty ? input : updated.sourceText,
      generation: beginOperation()
    )
  }

  func chooseClarificationSuggestion(_ suggestion: String) {
    clarificationAnswer = suggestion
    submitClarificationAnswer()
  }

  func resolveWithServings() {
    guard
      let servings = numberParser.parse(clarificationServings, minimum: .greaterThanZero),
      let details
    else {
      message = "Enter a valid number of USDA servings."
      return
    }
    apply(resolver.manualServings(servings, food: details))
  }

  func resolveWithGrams() {
    guard
      let grams = numberParser.parse(clarificationGrams, minimum: .greaterThanZero),
      let details
    else {
      message = "Enter a valid gram amount."
      return
    }
    apply(resolver.manualGrams(grams, food: details))
  }

  func makeRecord() throws -> FoodLogEntryRecord {
    guard let parsed, let details, let resolution else { throw FoodParserError.invalidResponse }
    return try FoodLogEntryRecord(
      originalText: input,
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

  func markSaved() {
    rememberConfirmedSelectionIfPossible()
    stage = .completed
    message = "Entry saved on this device."
  }

  func markManualSaved() {
    reset()
    stage = .completed
    message = "Manual entry saved on this device."
  }

  func markSaveFailed() {
    stage = .reviewing
    message = "The entry could not be saved. Your review has not been discarded."
  }

  func reset() {
    invalidateOperation()
    input = ""
    manualSearchTerms = ""
    parsed = nil
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    message = nil
    failureKind = nil
    clearInterpretationClarification()
    clarificationServings = ""
    clarificationGrams = ""
    stage = .idle
  }

  func cancel() {
    invalidateOperation()
    clearInterpretationClarification()
    stage = .idle
    message = nil
    failureKind = nil
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

  private func submitFlow(generation: UInt) async {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      fail(.interpretation, message: "Enter a food description first.")
      return
    }
    stage = .parsing
    message = nil
    failureKind = nil
    clearInterpretationClarification()
    let request: ParsedFoodRequest
    do {
      let parsed = try await parser.parse(text)
      guard isCurrentOperation(generation) else { return }

      let draft = interpretationValidator.draft(
        from: parsed,
        sourceText: text,
        evidenceKind: .typedText
      )
      interpretationDraft = draft
      switch clarificationPolicy.decide(draft) {
      case .proceed(let proceeded):
        self.parsed = proceeded
        manualSearchTerms = queryBuilder.build(from: proceeded).query
        request = proceeded
      case .clarify(let question):
        presentInterpretationClarification(question, draft: draft, sourceText: text)
        return
      case .requireEdit(let message):
        manualSearchTerms = text
        fail(.interpretation, message: message)
        return
      case .fallbackManual(let message):
        manualSearchTerms = text
        fail(.interpretation, message: message)
        return
      }
    } catch is CancellationError {
      return
    } catch {
      guard isCurrentOperation(generation) else { return }
      manualSearchTerms = text
      let failureMessage =
        (error as? FoodParserError)?.errorDescription
        ?? "On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually."
      fail(
        .interpretation,
        message: failureMessage
      )
      return
    }

    await runSearch(for: request, generation: generation)
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
  }

  private func clearInterpretationClarification(keepDraft: Bool = false) {
    activeQuestion = nil
    clarificationAnswer = ""
    if !keepDraft {
      interpretationDraft = nil
    }
  }

  private func runSearch(for request: ParsedFoodRequest, generation: UInt) async {
    do {
      try await search(
        queryBuilder.build(from: request), rankingIntent: request, generation: generation)
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
    } else {
      stage = .choosing
    }
  }

  private func selectionFlow(_ result: FoodSearchResult, generation: UInt) async {
    stage = .loadingDetails
    message = nil
    do {
      let details = try await provider.foodDetails(fdcID: result.fdcID)
      guard isCurrentOperation(generation) else { return }
      self.details = details
      guard let parsed else {
        stage = .clarifying
        message = "Enter the amount you ate."
        return
      }
      apply(resolver.resolve(parsed, against: details))
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
  }

  private func apply(_ outcome: ServingResolutionOutcome) {
    switch outcome {
    case .needsClarification(let explanation):
      stage = .clarifying
      message = explanation
    case .resolved(let resolution):
      guard let details else { return }
      do {
        nutrients = try calculator.calculate(food: details, resolution: resolution)
        guard nutrients.contains(where: { $0.key == .energy }) else {
          stage = .clarifying
          message =
            "This USDA record does not provide enough compatible nutrition data. Choose another result or enter nutrition manually."
          return
        }
        self.resolution = resolution
        message = nil
        stage = .reviewing
      } catch {
        stage = .clarifying
        message =
          "The serving and nutrition bases could not be combined safely. Enter servings or grams."
      }
    }
  }

  /// Records a confirmed USDA pick for future ranking boosts only — never auto-selects.
  private func rememberConfirmedSelectionIfPossible() {
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
