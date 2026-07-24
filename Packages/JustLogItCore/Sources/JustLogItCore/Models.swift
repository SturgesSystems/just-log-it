import Foundation

public enum MultipleFoodAssessment: String, Sendable, Equatable, Codable {
  case single
  case multiple
}

public struct ParsedFoodRequest: Sendable, Equatable, Codable {
  public var brand: String?
  public var productName: String
  public var searchTerms: String
  public var quantity: Double?
  public var unit: String?
  public var quantityText: String?
  public var fractionOfWhole: Double?
  public var wholeUnit: String?
  public var containerSize: Double?
  public var containerSizeUnit: String?
  public var alternateQuantity: Double?
  public var alternateUnit: String?
  public var preparation: String?
  public var descriptors: [String]
  public var isApproximate: Bool
  public var containsMultipleFoods: Bool
  /// Deterministic coordinator metadata. Nil preserves legacy/model-first inference behavior.
  public var multipleFoodAssessment: MultipleFoodAssessment?
  public var ambiguityNotes: String?
  /// Distinct foods to look up separately for a composite log (e.g. cereal, milk).
  public var componentNames: [String]
  /// Model judgment: amount is missing or only vague and should be asked before search.
  public var quantityNeedsClarification: Bool
  /// Model judgment: preparation/cook method was not stated but would change lookup.
  public var preparationNeedsClarification: Bool
  /// Model-authored user-facing question. Non-empty means soft-clarify before USDA.
  public var clarificationPrompt: String?
  /// Model-authored optional chips for `clarificationPrompt` (may be empty).
  public var clarificationSuggestions: [String]

  public init(
    brand: String? = nil,
    productName: String,
    searchTerms: String = "",
    quantity: Double? = nil,
    unit: String? = nil,
    quantityText: String? = nil,
    fractionOfWhole: Double? = nil,
    wholeUnit: String? = nil,
    containerSize: Double? = nil,
    containerSizeUnit: String? = nil,
    alternateQuantity: Double? = nil,
    alternateUnit: String? = nil,
    preparation: String? = nil,
    descriptors: [String] = [],
    isApproximate: Bool = false,
    containsMultipleFoods: Bool = false,
    multipleFoodAssessment: MultipleFoodAssessment? = nil,
    ambiguityNotes: String? = nil,
    componentNames: [String] = [],
    quantityNeedsClarification: Bool = false,
    preparationNeedsClarification: Bool = false,
    clarificationPrompt: String? = nil,
    clarificationSuggestions: [String] = []
  ) {
    self.brand = brand
    self.productName = productName
    self.searchTerms = searchTerms
    self.quantity = quantity
    self.unit = unit
    self.quantityText = quantityText
    self.fractionOfWhole = fractionOfWhole
    self.wholeUnit = wholeUnit
    self.containerSize = containerSize
    self.containerSizeUnit = containerSizeUnit
    self.alternateQuantity = alternateQuantity
    self.alternateUnit = alternateUnit
    self.preparation = preparation
    self.descriptors = descriptors
    self.isApproximate = isApproximate
    self.containsMultipleFoods = containsMultipleFoods
    self.multipleFoodAssessment = multipleFoodAssessment
    self.ambiguityNotes = ambiguityNotes
    self.componentNames = componentNames
    self.quantityNeedsClarification = quantityNeedsClarification
    self.preparationNeedsClarification = preparationNeedsClarification
    self.clarificationPrompt = clarificationPrompt
    self.clarificationSuggestions = clarificationSuggestions
  }
}

public protocol FoodDescriptionParsing: Sendable {
  func parse(_ input: String) async throws -> ParsedFoodRequest
  func parse(semanticContext: String, groundingText: String) async throws -> ParsedFoodRequest
}

extension FoodDescriptionParsing {
  /// Compatibility path for parsers that do not distinguish assistant context from user evidence.
  /// Hybrid implementations override this requirement and ground only against `groundingText`.
  public func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    try await parse(semanticContext)
  }
}

public struct FoodSearchRequest: Sendable, Equatable, Codable {
  public var query: String
  public var normalizedKey: String
  public var dataTypes: [String]
  public var page: Int
  public var pageSize: Int

  public init(
    query: String, normalizedKey: String, dataTypes: [String], page: Int = 1, pageSize: Int = 50
  ) {
    self.query = query
    self.normalizedKey = normalizedKey
    self.dataTypes = dataTypes
    self.page = page
    self.pageSize = pageSize
  }
}

public struct FoodSearchResult: Identifiable, Sendable, Equatable, Codable {
  public var id: Int { fdcID }
  public let fdcID: Int
  public let description: String
  public let brandOwner: String?
  public let brandName: String?
  public let dataType: String
  public let gtinUPC: String?
  public let servingSize: Double?
  public let servingSizeUnit: String?
  public let householdServing: String?

  public init(
    fdcID: Int, description: String, brandOwner: String? = nil, brandName: String? = nil,
    dataType: String, gtinUPC: String? = nil, servingSize: Double? = nil,
    servingSizeUnit: String? = nil, householdServing: String? = nil
  ) {
    self.fdcID = fdcID
    self.description = description
    self.brandOwner = brandOwner
    self.brandName = brandName
    self.dataType = dataType
    self.gtinUPC = gtinUPC
    self.servingSize = servingSize
    self.servingSizeUnit = servingSizeUnit
    self.householdServing = householdServing
  }
}

public struct FoodSearchResponse: Sendable, Equatable, Codable {
  public let foods: [FoodSearchResult]
  public let totalHits: Int
  public let currentPage: Int
  public let totalPages: Int

  public init(foods: [FoodSearchResult], totalHits: Int, currentPage: Int, totalPages: Int) {
    self.foods = foods
    self.totalHits = totalHits
    self.currentPage = currentPage
    self.totalPages = totalPages
  }
}

public enum NutrientKey: String, CaseIterable, Sendable, Codable {
  case energy
  case protein
  case carbohydrate
  case totalFat
  case saturatedFat
  case monounsaturatedFat
  case polyunsaturatedFat
  case cholesterol
  case fiber
  case totalSugar
  case addedSugar
  case sodium
  case calcium
  case iron
  case potassium
  case vitaminD
  case caffeine
  case water
  case biotin
  case chloride
  case chromium
  case copper
  case folate
  case iodine
  case magnesium
  case manganese
  case molybdenum
  case niacin
  case pantothenicAcid
  case phosphorus
  case riboflavin
  case selenium
  case thiamin
  case vitaminA
  case vitaminB12
  case vitaminB6
  case vitaminC
  case vitaminE
  case vitaminK
  case zinc

  public var displayName: String {
    switch self {
    case .energy: "Calories"
    case .protein: "Protein"
    case .carbohydrate: "Carbohydrates"
    case .totalFat: "Total Fat"
    case .saturatedFat: "Saturated Fat"
    case .monounsaturatedFat: "Monounsaturated Fat"
    case .polyunsaturatedFat: "Polyunsaturated Fat"
    case .cholesterol: "Cholesterol"
    case .fiber: "Fiber"
    case .totalSugar: "Total Sugar"
    case .addedSugar: "Added Sugar"
    case .sodium: "Sodium"
    case .calcium: "Calcium"
    case .iron: "Iron"
    case .potassium: "Potassium"
    case .vitaminD: "Vitamin D"
    case .caffeine: "Caffeine"
    case .water: "Water"
    case .biotin: "Biotin"
    case .chloride: "Chloride"
    case .chromium: "Chromium"
    case .copper: "Copper"
    case .folate: "Folate"
    case .iodine: "Iodine"
    case .magnesium: "Magnesium"
    case .manganese: "Manganese"
    case .molybdenum: "Molybdenum"
    case .niacin: "Niacin"
    case .pantothenicAcid: "Pantothenic Acid"
    case .phosphorus: "Phosphorus"
    case .riboflavin: "Riboflavin"
    case .selenium: "Selenium"
    case .thiamin: "Thiamin"
    case .vitaminA: "Vitamin A"
    case .vitaminB12: "Vitamin B12"
    case .vitaminB6: "Vitamin B6"
    case .vitaminC: "Vitamin C"
    case .vitaminE: "Vitamin E"
    case .vitaminK: "Vitamin K"
    case .zinc: "Zinc"
    }
  }

  public var canonicalUnit: String {
    switch self {
    case .energy: "kcal"
    case .protein, .carbohydrate, .totalFat, .saturatedFat, .monounsaturatedFat,
      .polyunsaturatedFat, .fiber, .totalSugar, .addedSugar:
      "g"
    case .cholesterol, .sodium, .calcium, .iron, .potassium, .caffeine, .chloride,
      .copper, .magnesium, .manganese, .niacin, .pantothenicAcid, .phosphorus,
      .riboflavin, .thiamin, .vitaminB6, .vitaminC, .vitaminE, .zinc:
      "mg"
    case .vitaminD, .biotin, .chromium, .folate, .iodine, .molybdenum, .selenium,
      .vitaminA, .vitaminB12, .vitaminK:
      "µg"
    case .water: "mL"
    }
  }
}

public struct NutrientAmount: Sendable, Equatable, Codable, Identifiable {
  public var id: NutrientKey { key }
  public let key: NutrientKey
  public let amount: Double
  public let unit: String

  public init(key: NutrientKey, amount: Double, unit: String? = nil) {
    self.key = key
    self.amount = amount
    self.unit = unit ?? key.canonicalUnit
  }
}

public struct FoodDetails: Sendable, Equatable, Codable {
  public let fdcID: Int
  public let description: String
  public let brandOwner: String?
  public let dataType: String
  public let servingSize: Double?
  public let servingSizeUnit: String?
  public let householdServing: String?
  /// Every usable USDA `foodPortions[]` row. `servingSize`/`householdServing` remain the
  /// preferred default for backward compatibility, while amount resolution can use the
  /// specific row that matches what the user actually entered.
  public let foodPortions: [USDAFoodPortion]
  public let nutrientsPer100Grams: [NutrientAmount]
  public let nutrientsPerServing: [NutrientAmount]
  public let publicationDate: String?

  public init(
    fdcID: Int, description: String, brandOwner: String? = nil, dataType: String,
    servingSize: Double? = nil, servingSizeUnit: String? = nil, householdServing: String? = nil,
    foodPortions: [USDAFoodPortion] = [],
    nutrientsPer100Grams: [NutrientAmount] = [], nutrientsPerServing: [NutrientAmount] = [],
    publicationDate: String? = nil
  ) {
    self.fdcID = fdcID
    self.description = description
    self.brandOwner = brandOwner
    self.dataType = dataType
    self.servingSize = servingSize
    self.servingSizeUnit = servingSizeUnit
    self.householdServing = householdServing
    self.foodPortions = foodPortions
    self.nutrientsPer100Grams = nutrientsPer100Grams
    self.nutrientsPerServing = nutrientsPerServing
    self.publicationDate = publicationDate
  }

  private enum CodingKeys: String, CodingKey {
    case fdcID, description, brandOwner, dataType, servingSize, servingSizeUnit, householdServing
    case foodPortions, nutrientsPer100Grams, nutrientsPerServing, publicationDate
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fdcID = try container.decode(Int.self, forKey: .fdcID)
    description = try container.decode(String.self, forKey: .description)
    brandOwner = try container.decodeIfPresent(String.self, forKey: .brandOwner)
    dataType = try container.decode(String.self, forKey: .dataType)
    servingSize = try container.decodeIfPresent(Double.self, forKey: .servingSize)
    servingSizeUnit = try container.decodeIfPresent(String.self, forKey: .servingSizeUnit)
    householdServing = try container.decodeIfPresent(String.self, forKey: .householdServing)
    foodPortions =
      try container.decodeIfPresent([USDAFoodPortion].self, forKey: .foodPortions) ?? []
    nutrientsPer100Grams =
      try container.decodeIfPresent([NutrientAmount].self, forKey: .nutrientsPer100Grams) ?? []
    nutrientsPerServing =
      try container.decodeIfPresent([NutrientAmount].self, forKey: .nutrientsPerServing) ?? []
    publicationDate = try container.decodeIfPresent(String.self, forKey: .publicationDate)
  }
}

public protocol FoodDataProviding: Sendable {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse
  func foodDetails(fdcID: Int) async throws -> FoodDetails
}
