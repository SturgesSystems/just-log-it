#if DEBUG
  import Foundation
  import JustLogItCore

  // Deterministic doubles used only when the app launches with `-ui-testing`.
  // They live in shipping source (not the test target) because the running app
  // process selects them at launch.

  struct MockFoodParser: FoodDescriptionParsing {
    func parse(_ input: String) async throws -> ParsedFoodRequest {
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-parser-failure") {
        throw FoodParserError.invalidResponse
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-egg-portions") {
        return ParsedFoodRequest(
          productName: "scrambled eggs",
          searchTerms: "scrambled eggs",
          preparation: "scrambled",
          descriptors: ["large"]
        )
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-ambiguous-egg-portions") {
        return ParsedFoodRequest(
          productName: "scrambled eggs",
          searchTerms: "scrambled eggs",
          preparation: "scrambled"
        )
      }
      return ParsedFoodRequest(productName: input, searchTerms: input, quantity: 1, unit: "serving")
    }
  }

  /// Semantic outcomes injected by UI-test launch arguments. The production hybrid coordinator,
  /// grounder, merger, and clarification policy still run; only the Foundation Models boundary is
  /// replaced so semantic routes can be exercised on Simulator.
  private enum MockHybridSemanticScenario: Sendable {
    case namedDish
    case composite
    case unsafeAmountBinding
    case groundedApproximation
    case unavailable
    case refused
    case invalid

    static var current: Self? {
      let arguments = ProcessInfo.processInfo.arguments
      guard arguments.contains("-hybrid-parser") else { return nil }
      if arguments.contains("-ui-testing-hybrid-named-dish") { return .namedDish }
      if arguments.contains("-ui-testing-hybrid-composite") { return .composite }
      if arguments.contains("-ui-testing-hybrid-unsafe-amount") { return .unsafeAmountBinding }
      if arguments.contains("-ui-testing-hybrid-grounded-approximation") {
        return .groundedApproximation
      }
      if arguments.contains("-ui-testing-hybrid-semantic-unavailable") { return .unavailable }
      if arguments.contains("-ui-testing-hybrid-semantic-refused") { return .refused }
      if arguments.contains("-ui-testing-hybrid-semantic-invalid") { return .invalid }
      return nil
    }
  }

  private struct MockHybridSemanticFoodProposer: SemanticFoodProposing {
    let scenario: MockHybridSemanticScenario

    func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal {
      switch scenario {
      case .namedDish:
        return SemanticFoodProposal(
          productName: "mac and cheese",
          containsMultipleFoods: false
        )
      case .composite:
        return SemanticFoodProposal(
          productName: "",
          containsMultipleFoods: true,
          componentNames: ["eggs", "toast"]
        )
      case .unsafeAmountBinding:
        // The coordinator must reject the unsafe deterministic amount binding before this
        // boundary is called. Keeping a valid proposal here makes an accidental invocation
        // visible in the resulting UI path instead of crashing the test host.
        return SemanticFoodProposal(productName: "protein powder")
      case .groundedApproximation:
        return SemanticFoodProposal(productName: "olive oil")
      case .unavailable:
        throw SemanticFoodProposalError.unavailable
      case .refused:
        throw SemanticFoodProposalError.refused
      case .invalid:
        throw SemanticFoodProposalError.invalidResponse
      }
    }
  }

  struct MockHybridFoodParser: ContextualFoodDescriptionParsing {
    private let interpreter: HybridFoodInterpreter

    init?() {
      guard let scenario = MockHybridSemanticScenario.current else { return nil }
      interpreter = HybridFoodInterpreter(
        proposer: MockHybridSemanticFoodProposer(scenario: scenario)
      )
    }

    func parse(_ input: String) async throws -> ParsedFoodRequest {
      let result = try await interpreter.interpret(
        semanticContext: input,
        groundingText: input
      )
      return try result.appFacingRequest()
    }

    func parse(
      semanticContext: String,
      groundingText: String
    ) async throws -> ParsedFoodRequest {
      let result = try await interpreter.interpret(
        semanticContext: semanticContext,
        groundingText: groundingText
      )
      return try result.appFacingRequest()
    }
  }

  struct MockFoodDataProvider: FoodDataProviding {
    func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
      if usesUnsafeAmountFixture {
        return response(
          FoodSearchResult(
            fdcID: 999_006,
            description: "PROTEIN POWDER",
            dataType: "Branded",
            servingSize: 1,
            servingSizeUnit: "scoop",
            householdServing: "1 scoop"
          )
        )
      }
      if usesGroundedApproximationFixture {
        return response(
          FoodSearchResult(
            fdcID: 999_007,
            description: "OLIVE OIL",
            dataType: "Foundation",
            servingSize: 1,
            servingSizeUnit: "tbsp",
            householdServing: "1 tbsp"
          )
        )
      }
      if usesNamedDishFixture {
        return response(
          FoodSearchResult(
            fdcID: 999_003,
            description: "MACARONI AND CHEESE",
            dataType: "Survey (FNDDS)",
            servingSize: 100,
            servingSizeUnit: "g",
            householdServing: "1 serving"
          )
        )
      }
      if usesCompositeFixture {
        let isToast = request.query.localizedCaseInsensitiveContains("toast")
        return response(
          FoodSearchResult(
            fdcID: isToast ? 999_005 : 999_004,
            description: isToast ? "TOAST, WHITE" : "EGGS, SCRAMBLED",
            dataType: "Survey (FNDDS)",
            servingSize: 100,
            servingSizeUnit: "g",
            householdServing: "1 serving"
          )
        )
      }
      if usesEggPortionFixture {
        return FoodSearchResponse(
          foods: [
            FoodSearchResult(
              fdcID: 999_002,
              description: "EGG, WHOLE, COOKED, SCRAMBLED",
              dataType: "SR Legacy"
            )
          ],
          totalHits: 1,
          currentPage: 1,
          totalPages: 1
        )
      }
      return FoodSearchResponse(
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
      if fdcID == 999_006 {
        return fixtureDetails(
          fdcID: fdcID,
          description: "Protein powder",
          householdServing: "1 scoop",
          calories: 120,
          protein: 24,
          carbohydrate: 3,
          fat: 1.5
        )
      }
      if fdcID == 999_007 {
        return FoodDetails(
          fdcID: fdcID,
          description: "Olive oil",
          dataType: "Foundation",
          servingSize: 13.5,
          servingSizeUnit: "g",
          householdServing: "1 tbsp",
          foodPortions: [
            USDAFoodPortion(gramWeight: 13.5, amount: 1, portionDescription: "1 tbsp")
          ],
          nutrientsPer100Grams: [
            NutrientAmount(key: .energy, amount: 884),
            NutrientAmount(key: .protein, amount: 0),
            NutrientAmount(key: .carbohydrate, amount: 0),
            NutrientAmount(key: .totalFat, amount: 100),
          ]
        )
      }
      if fdcID == 999_003 {
        return fixtureDetails(
          fdcID: fdcID,
          description: "Macaroni and cheese",
          householdServing: "1 serving",
          calories: 164,
          protein: 7,
          carbohydrate: 23,
          fat: 5
        )
      }
      if fdcID == 999_004 || fdcID == 999_005 {
        let isToast = fdcID == 999_005
        return fixtureDetails(
          fdcID: fdcID,
          description: isToast ? "Toast, white" : "Eggs, scrambled",
          householdServing: "1 serving",
          calories: isToast ? 293 : 148,
          protein: isToast ? 9 : 10,
          carbohydrate: isToast ? 54 : 1.6,
          fat: isToast ? 4 : 11
        )
      }
      if usesEggPortionFixture {
        return FoodDetails(
          fdcID: fdcID,
          description: "Egg, whole, cooked, scrambled",
          dataType: "SR Legacy",
          servingSize: 220,
          servingSizeUnit: "g",
          householdServing: "1 cup",
          foodPortions: [
            USDAFoodPortion(gramWeight: 220, amount: 1, portionDescription: "1 cup"),
            USDAFoodPortion(gramWeight: 61, amount: 1, portionDescription: "1 large egg"),
            USDAFoodPortion(gramWeight: 44, amount: 1, portionDescription: "1 small egg"),
          ],
          nutrientsPer100Grams: [
            NutrientAmount(key: .energy, amount: 148),
            NutrientAmount(key: .protein, amount: 10),
            NutrientAmount(key: .carbohydrate, amount: 1.6),
            NutrientAmount(key: .totalFat, amount: 11),
          ]
        )
      }
      return FoodDetails(
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

    private var usesEggPortionFixture: Bool {
      let arguments = ProcessInfo.processInfo.arguments
      return arguments.contains("-ui-testing-egg-portions")
        || arguments.contains("-ui-testing-ambiguous-egg-portions")
    }

    private var usesNamedDishFixture: Bool {
      ProcessInfo.processInfo.arguments.contains("-ui-testing-hybrid-named-dish")
    }

    private var usesCompositeFixture: Bool {
      ProcessInfo.processInfo.arguments.contains("-ui-testing-hybrid-composite")
    }

    private var usesUnsafeAmountFixture: Bool {
      ProcessInfo.processInfo.arguments.contains("-ui-testing-hybrid-unsafe-amount")
    }

    private var usesGroundedApproximationFixture: Bool {
      ProcessInfo.processInfo.arguments.contains("-ui-testing-hybrid-grounded-approximation")
    }

    private func response(_ food: FoodSearchResult) -> FoodSearchResponse {
      FoodSearchResponse(
        foods: [food],
        totalHits: 1,
        currentPage: 1,
        totalPages: 1
      )
    }

    private func fixtureDetails(
      fdcID: Int,
      description: String,
      householdServing: String,
      calories: Double,
      protein: Double,
      carbohydrate: Double,
      fat: Double
    ) -> FoodDetails {
      FoodDetails(
        fdcID: fdcID,
        description: description,
        dataType: "Survey (FNDDS)",
        servingSize: 100,
        servingSizeUnit: "g",
        householdServing: householdServing,
        nutrientsPer100Grams: [
          NutrientAmount(key: .energy, amount: calories),
          NutrientAmount(key: .protein, amount: protein),
          NutrientAmount(key: .carbohydrate, amount: carbohydrate),
          NutrientAmount(key: .totalFat, amount: fat),
        ]
      )
    }
  }
#endif
