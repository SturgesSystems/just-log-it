import Foundation
import JustLogItCore

/// Minimal direct USDA FoodData Central client for offline-of-app evaluation.
/// API key is read only from the environment / caller — never hardcoded.
struct USDAClient: FoodDataProviding, Sendable {
  enum ClientError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidURL
    case invalidRequest
    case http(status: Int)
    case decode

    var description: String {
      switch self {
      case .missingAPIKey: "USDA_API_KEY is not set"
      case .invalidURL: "Could not build USDA URL"
      case .invalidRequest: "Invalid USDA request"
      case .http(let status): "USDA HTTP \(status)"
      case .decode: "Could not decode USDA response"
      }
    }
  }

  private let apiKey: String
  private let session: URLSession
  private let decoder = JSONDecoder()

  init(apiKey: String, session: URLSession = .shared) {
    self.apiKey = apiKey
    self.session = session
  }

  static func fromEnvironment() throws -> USDAClient {
    let key =
      ProcessInfo.processInfo.environment["USDA_API_KEY"]?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !key.isEmpty else { throw ClientError.missingAPIKey }
    return USDAClient(apiKey: key)
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    guard !request.query.isEmpty else { throw ClientError.invalidRequest }
    guard
      var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
    else {
      throw ClientError.invalidURL
    }
    components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
    guard let url = components.url else { throw ClientError.invalidURL }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.timeoutInterval = 20
    let body = SearchBody(
      query: request.query,
      dataType: request.dataTypes.isEmpty ? nil : request.dataTypes,
      pageSize: request.pageSize,
      pageNumber: request.page
    )
    urlRequest.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await session.data(for: urlRequest)
    try validate(response)
    do {
      return try decoder.decode(SearchResponseDTO.self, from: data).domain
    } catch {
      throw ClientError.decode
    }
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    guard fdcID > 0 else { throw ClientError.invalidRequest }
    guard
      var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcID)")
    else {
      throw ClientError.invalidURL
    }
    components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
    guard let url = components.url else { throw ClientError.invalidURL }

    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 20
    let (data, response) = try await session.data(for: urlRequest)
    try validate(response)
    do {
      return try decoder.decode(DetailsDTO.self, from: data).domain
    } catch {
      throw ClientError.decode
    }
  }

  private func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw ClientError.http(status: -1) }
    guard (200..<300).contains(http.statusCode) else {
      throw ClientError.http(status: http.statusCode)
    }
  }
}

// MARK: - DTOs (evaluation subset)

private struct SearchBody: Encodable {
  let query: String
  let dataType: [String]?
  let pageSize: Int
  let pageNumber: Int
}

private struct SearchResponseDTO: Decodable {
  let totalHits: Int?
  let currentPage: Int?
  let totalPages: Int?
  let foods: [SearchFoodDTO]

  var domain: FoodSearchResponse {
    FoodSearchResponse(
      foods: foods.map(\.domain),
      totalHits: totalHits ?? foods.count,
      currentPage: currentPage ?? 1,
      totalPages: totalPages ?? 1
    )
  }
}

private struct SearchFoodDTO: Decodable {
  let fdcId: Int
  let description: String
  let dataType: String
  let brandOwner: String?
  let brandName: String?
  let gtinUpc: String?
  let servingSize: Double?
  let servingSizeUnit: String?
  let householdServingFullText: String?

  var domain: FoodSearchResult {
    FoodSearchResult(
      fdcID: fdcId,
      description: description,
      brandOwner: brandOwner,
      brandName: brandName,
      dataType: dataType,
      gtinUPC: gtinUpc,
      servingSize: servingSize,
      servingSizeUnit: servingSizeUnit,
      householdServing: householdServingFullText
    )
  }
}

private struct DetailsDTO: Decodable {
  let fdcId: Int
  let description: String
  let dataType: String
  let brandOwner: String?
  let servingSize: Double?
  let servingSizeUnit: String?
  let householdServingFullText: String?
  let publicationDate: String?
  let foodNutrients: [FoodNutrientDTO]?
  let foodPortions: [FoodPortionDTO]?

  var domain: FoodDetails {
    let per100Grams = NutrientMap.canonicalize(foodNutrients ?? [])
    let resolved = FoodPortionServing.resolve(
      servingSize: servingSize,
      servingSizeUnit: servingSizeUnit,
      householdServing: householdServingFullText,
      portions: (foodPortions ?? []).map(\.domain)
    )
    let perServing = NutrientMap.servingFromPer100(
      per100Grams: per100Grams,
      servingSize: resolved.servingSize,
      servingSizeUnit: resolved.servingSizeUnit
    )
    return FoodDetails(
      fdcID: fdcId,
      description: description,
      brandOwner: brandOwner,
      dataType: dataType,
      servingSize: resolved.servingSize,
      servingSizeUnit: resolved.servingSizeUnit,
      householdServing: resolved.householdServing,
      nutrientsPer100Grams: per100Grams,
      nutrientsPerServing: perServing,
      publicationDate: publicationDate
    )
  }
}

private struct FoodPortionDTO: Decodable {
  struct MeasureUnitDTO: Decodable {
    let name: String?
    let abbreviation: String?
  }

  let gramWeight: Double?
  let amount: Double?
  let value: Double?
  let modifier: String?
  let portionDescription: String?
  let measureUnit: MeasureUnitDTO?

  var domain: USDAFoodPortion {
    USDAFoodPortion(
      gramWeight: gramWeight,
      amount: amount ?? value,
      modifier: modifier,
      portionDescription: portionDescription,
      measureUnitName: measureUnit?.name,
      measureUnitAbbreviation: measureUnit?.abbreviation
    )
  }
}

private struct FoodNutrientDTO: Decodable {
  struct NutrientDTO: Decodable {
    let id: Int?
    let name: String
    let unitName: String
  }

  let nutrient: NutrientDTO
  let amount: Double?
}

private enum NutrientMap {
  static func canonicalize(_ values: [FoodNutrientDTO]) -> [NutrientAmount] {
    var selected: [NutrientKey: NutrientAmount] = [:]
    for value in values {
      guard let amount = value.amount, amount.isFinite, amount >= 0,
        let key = key(name: value.nutrient.name, id: value.nutrient.id)
      else { continue }
      if selected[key] == nil {
        if let normalized = normalize(key: key, amount: amount, sourceUnit: value.nutrient.unitName)
        {
          selected[key] = normalized
        }
      }
    }
    return NutrientKey.allCases.compactMap { selected[$0] }
  }

  static func key(name: String, id: Int?) -> NutrientKey? {
    if let id {
      switch id {
      case 1008, 2047, 2048: return .energy
      case 1003: return .protein
      case 1005: return .carbohydrate
      case 1004: return .totalFat
      default: break
      }
    }
    let value = name.lowercased()
    if value.contains("energy") { return .energy }
    if value == "protein" { return .protein }
    if value.contains("carbohydrate") { return .carbohydrate }
    if value.contains("total lipid") || value == "total fat" { return .totalFat }
    return nil
  }

  static func normalize(key: NutrientKey, amount: Double, sourceUnit: String) -> NutrientAmount? {
    let source = sourceUnit.lowercased()
    let target = key.canonicalUnit
    let converted: Double
    switch (source, target) {
    case ("kj", "kcal"): converted = amount / 4.184
    case ("kcal", "kcal"), ("g", "g"), ("mg", "mg"): converted = amount
    default:
      if source == target { converted = amount } else { return nil }
    }
    return NutrientAmount(key: key, amount: converted)
  }

  /// Scale per-100 g nutrients to one serving when the serving is in grams.
  static func servingFromPer100(
    per100Grams: [NutrientAmount],
    servingSize: Double?,
    servingSizeUnit: String?
  ) -> [NutrientAmount] {
    guard let servingSize, servingSize.isFinite, servingSize > 0,
      servingSizeUnit?.caseInsensitiveCompare("g") == .orderedSame
    else { return [] }
    let multiplier = servingSize / 100
    return per100Grams.map {
      NutrientAmount(key: $0.key, amount: $0.amount * multiplier, unit: $0.unit)
    }
  }
}
