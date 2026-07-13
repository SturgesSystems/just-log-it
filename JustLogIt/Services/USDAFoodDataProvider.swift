import Foundation
import JustLogItCore

enum FoodDataError: LocalizedError, Equatable {
  case notConfigured
  case invalidRequest
  case invalidResponse
  case unauthorized
  case notFound
  case rateLimited(retryAfter: String?)
  case server(status: Int)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "Food search is not configured yet. You can still enter nutrition manually."
    case .invalidRequest:
      "That search could not be sent. Edit the terms and try again."
    case .invalidResponse:
      "The food service returned information this version of JustLogIt could not read."
    case .unauthorized:
      "The food service configuration was rejected."
    case .notFound:
      "That USDA food is no longer available."
    case .rateLimited(let retryAfter):
      retryAfter.map { "Food search is temporarily rate-limited. Try again after \($0)." }
        ?? "Food search is temporarily rate-limited. Try again later."
    case .server:
      "The food service is temporarily unavailable. Try again later."
    }
  }
}

enum FoodDataProviderFactory {
  static func make(configuration: AppConfiguration = .current) -> any FoodDataProviding {
    let upstream: any FoodDataProviding
    if let baseURL = configuration.proxyBaseURL {
      upstream = USDAFoodDataProvider(endpoint: .proxy(baseURL))
    } else {
      #if DEBUG
        if let key = configuration.debugUSDAAPIKey {
          upstream = USDAFoodDataProvider(endpoint: .directUSDA(apiKey: key))
        } else {
          upstream = UnconfiguredFoodDataProvider()
        }
      #else
        upstream = UnconfiguredFoodDataProvider()
      #endif
    }
    return DiskCachedFoodDataProvider(upstream: upstream)
  }
}

private struct UnconfiguredFoodDataProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    throw FoodDataError.notConfigured
  }
  func foodDetails(fdcID: Int) async throws -> FoodDetails { throw FoodDataError.notConfigured }
}

private actor USDAFoodDataProvider: FoodDataProviding {
  enum Endpoint: Sendable {
    case proxy(URL)
    #if DEBUG
      case directUSDA(apiKey: String)
    #endif
  }

  private let endpoint: Endpoint
  private let session: URLSession
  private let decoder = JSONDecoder()

  init(endpoint: Endpoint, session: URLSession = .shared) {
    self.endpoint = endpoint
    self.session = session
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    guard !request.query.isEmpty, (1...50).contains(request.pageSize), request.page > 0 else {
      throw FoodDataError.invalidRequest
    }
    var urlRequest = try searchURLRequest(request)
    urlRequest.timeoutInterval = 12
    let (data, response) = try await session.data(for: urlRequest)
    try validate(response)
    do {
      return try decoder.decode(USDASearchResponseDTO.self, from: data).domain
    } catch {
      throw FoodDataError.invalidResponse
    }
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    guard fdcID > 0 else { throw FoodDataError.invalidRequest }
    var urlRequest = try detailsURLRequest(fdcID: fdcID)
    urlRequest.timeoutInterval = 12
    let (data, response) = try await session.data(for: urlRequest)
    try validate(response)
    do {
      return try decoder.decode(USDAFoodDetailsDTO.self, from: data).domain
    } catch {
      throw FoodDataError.invalidResponse
    }
  }

  private func searchURLRequest(_ request: FoodSearchRequest) throws -> URLRequest {
    let body = USDASearchBody(
      query: request.query,
      dataType: request.dataTypes.isEmpty ? nil : request.dataTypes,
      pageSize: request.pageSize,
      pageNumber: request.page
    )
    let url: URL
    switch endpoint {
    case .proxy(let baseURL):
      url = baseURL.appending(path: "v1/foods/search")
    #if DEBUG
      case .directUSDA(let apiKey):
        guard
          var components = URLComponents(
            string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        else {
          throw FoodDataError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let built = components.url else { throw FoodDataError.invalidRequest }
        url = built
    #endif
    }
    var result = URLRequest(url: url)
    result.httpMethod = "POST"
    result.setValue("application/json", forHTTPHeaderField: "Content-Type")
    result.httpBody = try JSONEncoder().encode(body)
    return result
  }

  private func detailsURLRequest(fdcID: Int) throws -> URLRequest {
    let url: URL
    switch endpoint {
    case .proxy(let baseURL):
      url = baseURL.appending(path: "v1/foods/\(fdcID)")
    #if DEBUG
      case .directUSDA(let apiKey):
        guard
          var components = URLComponents(
            string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcID)")
        else {
          throw FoodDataError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let built = components.url else { throw FoodDataError.invalidRequest }
        url = built
    #endif
    }
    return URLRequest(url: url)
  }

  private func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw FoodDataError.invalidResponse }
    switch http.statusCode {
    case 200..<300:
      return
    case 400:
      throw FoodDataError.invalidRequest
    case 401, 403:
      throw FoodDataError.unauthorized
    case 404:
      throw FoodDataError.notFound
    case 429:
      throw FoodDataError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    case 500...599:
      throw FoodDataError.server(status: http.statusCode)
    default:
      throw FoodDataError.invalidResponse
    }
  }
}

actor DiskCachedFoodDataProvider: FoodDataProviding {
  private struct Envelope<Value: Codable & Sendable>: Codable, Sendable {
    let value: Value
    let expiresAt: Date
  }

  private let upstream: any FoodDataProviding
  private let directory: URL
  private let now: @Sendable () -> Date
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    upstream: any FoodDataProviding,
    directory: URL? = nil,
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.upstream = upstream
    self.now = now
    if let directory {
      self.directory = directory
    } else {
      let base =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      self.directory = base.appending(path: "JustLogItFoodData", directoryHint: .isDirectory)
    }
  }

  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    let url = fileURL(
      kind: "search",
      key:
        "\(request.normalizedKey)-\(request.page)-\(request.pageSize)-\(request.dataTypes.joined(separator: ","))"
    )
    if let cached: FoodSearchResponse = read(url) { return cached }
    let response = try await upstream.search(request)
    write(response, to: url, ttl: response.foods.isEmpty ? 15 * 60 : 7 * 24 * 60 * 60)
    return response
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    let url = fileURL(kind: "details", key: String(fdcID))
    if let cached: FoodDetails = read(url) { return cached }
    let response = try await upstream.foodDetails(fdcID: fdcID)
    write(response, to: url, ttl: 30 * 24 * 60 * 60)
    return response
  }

  private func read<Value: Codable & Sendable>(_ url: URL) -> Value? {
    guard let data = try? Data(contentsOf: url),
      let envelope = try? decoder.decode(Envelope<Value>.self, from: data),
      envelope.expiresAt > now()
    else { return nil }
    return envelope.value
  }

  private func write<Value: Codable & Sendable>(_ value: Value, to url: URL, ttl: TimeInterval) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let envelope = Envelope(value: value, expiresAt: now().addingTimeInterval(ttl))
      try encoder.encode(envelope).write(to: url, options: .atomic)
    } catch {
      // Cache failure must never prevent a food lookup.
    }
  }

  private func fileURL(kind: String, key: String) -> URL {
    let safe = Data(key.utf8).base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
    return directory.appending(path: "\(kind)-\(safe).json")
  }
}

private struct USDASearchBody: Encodable {
  let query: String
  let dataType: [String]?
  let pageSize: Int
  let pageNumber: Int
}

private struct USDASearchResponseDTO: Decodable {
  let totalHits: Int?
  let currentPage: Int?
  let totalPages: Int?
  let foods: [USDASearchFoodDTO]

  var domain: FoodSearchResponse {
    FoodSearchResponse(
      foods: foods.map(\.domain),
      totalHits: totalHits ?? foods.count,
      currentPage: currentPage ?? 1,
      totalPages: totalPages ?? 1
    )
  }
}

private struct USDASearchFoodDTO: Decodable {
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

private struct USDAFoodDetailsDTO: Decodable {
  let fdcId: Int
  let description: String
  let dataType: String
  let brandOwner: String?
  let servingSize: Double?
  let servingSizeUnit: String?
  let householdServingFullText: String?
  let publicationDate: String?
  let foodNutrients: [USDAFoodNutrientDTO]?
  let labelNutrients: USDALabelNutrientsDTO?
  let foodPortions: [USDAFoodPortionDTO]?

  var domain: FoodDetails {
    let per100Grams = NutrientMapper.canonicalize(foodNutrients ?? [])
    let labeledServing = labelNutrients?.domain ?? []
    let resolved = FoodPortionServing.resolve(
      servingSize: servingSize,
      servingSizeUnit: servingSizeUnit,
      householdServing: householdServingFullText,
      portions: (foodPortions ?? []).map(\.domain)
    )
    let perServing = NutrientMapper.mergedServingNutrients(
      label: labeledServing,
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

private struct USDAFoodPortionDTO: Decodable {
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

private struct USDAFoodNutrientDTO: Decodable {
  struct NutrientDTO: Decodable {
    let id: Int?
    let name: String
    let unitName: String
  }

  let nutrient: NutrientDTO
  let amount: Double?

  var domain: NutrientAmount? {
    guard let amount, amount.isFinite, amount >= 0,
      let key = NutrientMapper.key(name: nutrient.name, id: nutrient.id)
    else { return nil }
    return NutrientMapper.normalize(key: key, amount: amount, sourceUnit: nutrient.unitName)
  }
}

private struct USDALabelValueDTO: Decodable { let value: Double? }

private struct USDALabelNutrientsDTO: Decodable {
  let calories: USDALabelValueDTO?
  let fat: USDALabelValueDTO?
  let saturatedFat: USDALabelValueDTO?
  let cholesterol: USDALabelValueDTO?
  let sodium: USDALabelValueDTO?
  let carbohydrates: USDALabelValueDTO?
  let fiber: USDALabelValueDTO?
  let sugars: USDALabelValueDTO?
  let addedSugar: USDALabelValueDTO?
  let protein: USDALabelValueDTO?
  let calcium: USDALabelValueDTO?
  let iron: USDALabelValueDTO?
  let potassium: USDALabelValueDTO?
  let vitaminD: USDALabelValueDTO?

  var domain: [NutrientAmount] {
    [
      value(.energy, calories), value(.totalFat, fat), value(.saturatedFat, saturatedFat),
      value(.cholesterol, cholesterol), value(.sodium, sodium), value(.carbohydrate, carbohydrates),
      value(.fiber, fiber), value(.totalSugar, sugars), value(.addedSugar, addedSugar),
      value(.protein, protein), value(.calcium, calcium), value(.iron, iron),
      value(.potassium, potassium), value(.vitaminD, vitaminD),
    ].compactMap { $0 }
  }

  private func value(_ key: NutrientKey, _ dto: USDALabelValueDTO?) -> NutrientAmount? {
    guard let amount = dto?.value, amount.isFinite, amount >= 0 else { return nil }
    return NutrientAmount(key: key, amount: amount)
  }
}

private enum NutrientMapper {
  static func key(name: String, id: Int?) -> NutrientKey? {
    if let id, let mapped = keysByUSDAID[id] { return mapped }
    let value = name.lowercased()
    if value.contains("energy") { return .energy }
    if value == "protein" { return .protein }
    if value.contains("carbohydrate") { return .carbohydrate }
    if value.contains("total lipid") || value == "total fat" { return .totalFat }
    if value.contains("fatty acids, total saturated") || value == "saturated fat" {
      return .saturatedFat
    }
    if value.contains("monounsaturated") { return .monounsaturatedFat }
    if value.contains("polyunsaturated") { return .polyunsaturatedFat }
    if value == "cholesterol" { return .cholesterol }
    if value.contains("fiber") { return .fiber }
    if value.contains("sugars, total") || value == "total sugars" { return .totalSugar }
    if value.contains("sugars, added") || value == "added sugars" { return .addedSugar }
    if value == "sodium, na" || value == "sodium" { return .sodium }
    if value.hasPrefix("calcium") { return .calcium }
    if value.hasPrefix("iron") { return .iron }
    if value.hasPrefix("potassium") { return .potassium }
    if value.contains("vitamin d") { return .vitaminD }
    if value == "caffeine" { return .caffeine }
    if value == "water" { return .water }
    if value.contains("biotin") { return .biotin }
    if value.hasPrefix("chloride") { return .chloride }
    if value.hasPrefix("chromium") { return .chromium }
    if value.hasPrefix("copper") { return .copper }
    if value.hasPrefix("folate, total") { return .folate }
    if value.hasPrefix("iodine") { return .iodine }
    if value.hasPrefix("magnesium") { return .magnesium }
    if value.hasPrefix("manganese") { return .manganese }
    if value.hasPrefix("molybdenum") { return .molybdenum }
    if value.hasPrefix("niacin") { return .niacin }
    if value.contains("pantothenic acid") { return .pantothenicAcid }
    if value.hasPrefix("phosphorus") { return .phosphorus }
    if value.hasPrefix("riboflavin") { return .riboflavin }
    if value.hasPrefix("selenium") { return .selenium }
    if value.hasPrefix("thiamin") { return .thiamin }
    if value.contains("vitamin a, rae") { return .vitaminA }
    if value.contains("vitamin b-12") || value.contains("vitamin b12") { return .vitaminB12 }
    if value.contains("vitamin b-6") || value.contains("vitamin b6") { return .vitaminB6 }
    if value.contains("vitamin c") { return .vitaminC }
    if value.contains("vitamin e") && value.contains("alpha") { return .vitaminE }
    if value.contains("vitamin k") { return .vitaminK }
    if value.hasPrefix("zinc") { return .zinc }
    return nil
  }

  static func canonicalize(_ values: [USDAFoodNutrientDTO]) -> [NutrientAmount] {
    var selected: [NutrientKey: (priority: Int, nutrient: NutrientAmount)] = [:]
    for value in values {
      guard let nutrient = value.domain else { continue }
      let priority = mappingPriority(
        key: nutrient.key, id: value.nutrient.id, sourceUnit: value.nutrient.unitName)
      if selected[nutrient.key].map({ priority < $0.priority }) ?? true {
        selected[nutrient.key] = (priority, nutrient)
      }
    }
    return NutrientKey.allCases.compactMap { selected[$0]?.nutrient }
  }

  static func mergedServingNutrients(
    label: [NutrientAmount],
    per100Grams: [NutrientAmount],
    servingSize: Double?,
    servingSizeUnit: String?
  ) -> [NutrientAmount] {
    var values = Dictionary(uniqueKeysWithValues: label.map { ($0.key, $0) })
    guard let servingSize, servingSize.isFinite, servingSize > 0,
      servingSizeUnit?.caseInsensitiveCompare("g") == .orderedSame
    else { return NutrientKey.allCases.compactMap { values[$0] } }
    let multiplier = servingSize / 100
    for nutrient in per100Grams where values[nutrient.key] == nil {
      values[nutrient.key] = NutrientAmount(
        key: nutrient.key, amount: nutrient.amount * multiplier, unit: nutrient.unit)
    }
    return NutrientKey.allCases.compactMap { values[$0] }
  }

  private static let keysByUSDAID: [Int: NutrientKey] = [
    1003: .protein, 1004: .totalFat, 1005: .carbohydrate, 1008: .energy,
    1057: .caffeine, 1078: .water, 1079: .fiber, 1087: .calcium, 1088: .chloride,
    1089: .iron, 1090: .magnesium, 1091: .phosphorus, 1092: .potassium,
    1093: .sodium, 1095: .zinc, 1096: .chromium, 1098: .copper, 1100: .iodine,
    1101: .manganese, 1102: .molybdenum, 1103: .selenium, 1106: .vitaminA,
    1109: .vitaminE, 1114: .vitaminD, 1162: .vitaminC, 1165: .thiamin,
    1166: .riboflavin, 1167: .niacin, 1170: .pantothenicAcid, 1175: .vitaminB6,
    1176: .biotin, 1177: .folate, 1178: .vitaminB12, 1185: .vitaminK,
    1235: .addedSugar, 1253: .cholesterol, 1258: .saturatedFat,
    1292: .monounsaturatedFat, 1293: .polyunsaturatedFat, 2000: .totalSugar,
    2047: .energy, 2048: .energy,
  ]

  private static func mappingPriority(key: NutrientKey, id: Int?, sourceUnit: String) -> Int {
    if key == .energy {
      if id == 1008 && sourceUnit.caseInsensitiveCompare("kcal") == .orderedSame { return 0 }
      if sourceUnit.caseInsensitiveCompare("kcal") == .orderedSame { return 1 }
      if id == 1008 { return 2 }
      return 3
    }
    return keysByUSDAID[id ?? -1] == key ? 0 : 1
  }

  static func normalize(key: NutrientKey, amount: Double, sourceUnit: String) -> NutrientAmount? {
    let source = sourceUnit.lowercased().replacingOccurrences(of: "μ", with: "µ")
    let target = key.canonicalUnit
    let converted: Double
    switch (source, target) {
    case ("kj", "kcal"): converted = amount / 4.184
    case ("kcal", "kcal"), ("g", "g"), ("mg", "mg"), ("µg", "µg"), ("ug", "µg"):
      converted = amount
    case ("g", "mg"): converted = amount * 1_000
    case ("g", "µg"): converted = amount * 1_000_000
    case ("mg", "g"): converted = amount / 1_000
    case ("mg", "µg"): converted = amount * 1_000
    case ("µg", "mg"), ("ug", "mg"): converted = amount / 1_000
    case ("µg", "g"), ("ug", "g"): converted = amount / 1_000_000
    case ("g", "ml"), ("ml", "ml"): converted = amount
    default: return nil
    }
    return NutrientAmount(key: key, amount: converted)
  }
}
