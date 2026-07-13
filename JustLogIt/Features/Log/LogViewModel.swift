import Foundation
import JustLogItCore
import SwiftData
import SwiftUI

@MainActor
final class LogViewModel: ObservableObject {
  enum Stage: Equatable {
    case idle
    case parsing
    case searching
    case choosing
    case loadingDetails
    case clarifying
    case reviewing
    case completed
    case failed
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
  @Published var clarificationServings = ""
  @Published var clarificationGrams = ""
  @Published var showManualEntry = false

  private let parser: any FoodDescriptionParsing
  private let provider: any FoodDataProviding
  private let queryBuilder = FoodSearchQueryBuilder()
  private let resolver = ServingResolutionService()
  private let calculator = NutritionCalculator()
  private var operation: Task<Void, Never>?

  init(parser: (any FoodDescriptionParsing)? = nil, provider: (any FoodDataProviding)? = nil) {
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
    operation?.cancel()
    operation = Task { [weak self] in
      await self?.submitFlow()
    }
  }

  func searchManually() {
    operation?.cancel()
    operation = Task { [weak self] in
      await self?.manualSearchFlow()
    }
  }

  func select(_ result: FoodSearchResult) {
    operation?.cancel()
    selectedResult = result
    operation = Task { [weak self] in
      await self?.selectionFlow(result)
    }
  }

  func resolveWithServings() {
    guard let servings = Double(clarificationServings), let details else {
      message = "Enter a valid number of USDA servings."
      return
    }
    apply(resolver.manualServings(servings, food: details))
  }

  func resolveWithGrams() {
    guard let grams = Double(clarificationGrams), let details else {
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
    operation?.cancel()
    input = ""
    manualSearchTerms = ""
    parsed = nil
    results = []
    selectedResult = nil
    details = nil
    resolution = nil
    nutrients = []
    message = nil
    clarificationServings = ""
    clarificationGrams = ""
    stage = .idle
  }

  func cancel() {
    operation?.cancel()
    stage = .idle
    message = nil
  }

  private func submitFlow() async {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      stage = .failed
      message = "Enter a food description first."
      return
    }
    stage = .parsing
    message = nil
    do {
      let parsed = try await parser.parse(text)
      try Task.checkCancellation()
      self.parsed = parsed
      manualSearchTerms = queryBuilder.build(from: parsed).query
      if parsed.containsMultipleFoods {
        message =
          "This looks like multiple foods. This MVP will continue with the principal food only; the original text will be preserved."
      }
      try await search(queryBuilder.build(from: parsed))
    } catch is CancellationError {
      return
    } catch {
      manualSearchTerms = text
      stage = .failed
      message =
        if let parserError = error as? FoodParserError {
          parserError.errorDescription
        } else {
          "On-device interpretation wasn’t available. Edit the search terms or enter nutrition manually."
        }
    }
  }

  private func manualSearchFlow() async {
    let request = queryBuilder.manual(manualSearchTerms)
    guard !request.query.isEmpty else {
      stage = .failed
      message = "Enter food search terms first."
      return
    }
    if parsed == nil {
      parsed = ParsedFoodRequest(productName: request.query, searchTerms: request.query)
    }
    do {
      try await search(request)
    } catch is CancellationError {
      return
    } catch {
      stage = .failed
      message = (error as? LocalizedError)?.errorDescription ?? "Food search failed."
    }
  }

  private func search(_ request: FoodSearchRequest) async throws {
    stage = .searching
    let response = try await provider.search(request)
    try Task.checkCancellation()
    results = response.foods
    if results.isEmpty {
      stage = .failed
      message = "No USDA foods matched. Edit the search or enter nutrition manually."
    } else {
      stage = .choosing
    }
  }

  private func selectionFlow(_ result: FoodSearchResult) async {
    stage = .loadingDetails
    message = nil
    do {
      let details = try await provider.foodDetails(fdcID: result.fdcID)
      try Task.checkCancellation()
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
      stage = .failed
      message =
        (error as? LocalizedError)?.errorDescription
        ?? "The selected food details could not be loaded."
    }
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
