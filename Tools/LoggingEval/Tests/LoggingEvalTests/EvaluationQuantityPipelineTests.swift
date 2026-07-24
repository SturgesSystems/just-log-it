import JustLogItCore
import XCTest

@testable import LoggingEval

final class EvaluationQuantityPipelineTests: XCTestCase {
  func testRunnerReportsRawAndRecoveredQuantitySeparately() async {
    let runner = EvalRunner(provider: EmptyFoodProvider(), parseMode: .fake)
    let report = await runner.run(cases: [
      EvalCaseInput(
        id: "eggs",
        description: "2 large eggs",
        parsedOverride: ParsedFoodRequest(productName: "eggs", searchTerms: "eggs")
      )
    ])

    let result = report.cases[0]
    XCTAssertFalse(report.includesInputText)
    XCTAssertNil(result.input)
    XCTAssertNil(result.rawQuantity)
    XCTAssertNil(result.rawUnit)
    XCTAssertEqual(result.quantity, 2)
    XCTAssertEqual(UnitConversion.family(result.unit ?? ""), "egg")
    XCTAssertTrue(result.sourceHadExplicitAmount)
    XCTAssertTrue(result.quantityRecoveredFromSource)
    XCTAssertTrue(result.checks["explicitSourceQuantityPreserved"] == true)
  }

  func testRecoversExplicitEggCountBeforeUSDAEvaluation() {
    let raw = ParsedFoodRequest(productName: "eggs", searchTerms: "eggs")

    let prepared = EvaluationQuantityPipeline.prepare(raw, sourceText: "2 large eggs")

    XCTAssertNil(raw.quantity)
    XCTAssertEqual(prepared.effective.quantity, 2)
    XCTAssertEqual(UnitConversion.family(prepared.effective.unit ?? ""), "egg")
    XCTAssertTrue(prepared.sourceHadExplicitAmount)
    XCTAssertTrue(prepared.quantityRecoveredFromSource)
    XCTAssertFalse(prepared.quantityDefaultedToOneServing)
    XCTAssertTrue(prepared.explicitSourceQuantityPreserved)
  }

  func testDoesNotDefaultWhenExplicitAmountCannotBeRecoveredSafely() {
    let raw = ParsedFoodRequest(
      productName: "meal",
      searchTerms: "meal",
      containsMultipleFoods: true,
      componentNames: ["eggs", "bacon"]
    )

    let prepared = EvaluationQuantityPipeline.prepare(
      raw,
      sourceText: "2 eggs and 3 bacon strips"
    )

    XCTAssertNil(prepared.effective.quantity)
    XCTAssertTrue(prepared.sourceHadExplicitAmount)
    XCTAssertFalse(prepared.quantityRecoveredFromSource)
    XCTAssertFalse(prepared.quantityDefaultedToOneServing)
    XCTAssertFalse(prepared.explicitSourceQuantityPreserved)
  }

  func testBareIdentityStaysMissingBeforeUSDASelection() {
    let raw = ParsedFoodRequest(productName: "banana", searchTerms: "banana")

    let prepared = EvaluationQuantityPipeline.prepare(raw, sourceText: "banana")

    XCTAssertNil(prepared.effective.quantity)
    XCTAssertNil(prepared.effective.unit)
    XCTAssertFalse(prepared.sourceHadExplicitAmount)
    XCTAssertFalse(prepared.quantityRecoveredFromSource)
    XCTAssertFalse(prepared.quantityDefaultedToOneServing)
    XCTAssertTrue(prepared.explicitSourceQuantityPreserved)
  }

  func testRunnerRequiresPickerForGenericIdentityWithoutFetchingDetailsOrDefaultingServing() async {
    let runner = EvalRunner(provider: ServingBackedFoodProvider(), parseMode: .fake)
    let report = await runner.run(cases: [
      EvalCaseInput(
        id: "banana",
        description: "banana",
        parsedOverride: ParsedFoodRequest(productName: "banana", searchTerms: "banana")
      )
    ])

    let result = report.cases[0]
    XCTAssertNil(result.quantity)
    XCTAssertNil(result.unit)
    XCTAssertFalse(result.quantityDefaultedToOneServing)
    XCTAssertEqual(result.selectionStatus, "pickerRequired")
    XCTAssertEqual(result.resolutionStatus, "pickerRequired")
    XCTAssertTrue(result.checks["pickerRequired"] == true)
    XCTAssertTrue(result.passed)
  }

  func testRunnerResolvesOnlyHighConfidenceExactDistinctiveMatch() async {
    let runner = EvalRunner(provider: StrongExactFoodProvider(), parseMode: .fake)
    let report = await runner.run(cases: [
      EvalCaseInput(
        id: "big-mac",
        description: "1 Big Mac",
        parsedOverride: ParsedFoodRequest(
          productName: "Big Mac",
          searchTerms: "Big Mac",
          quantity: 1,
          unit: "item"
        )
      )
    ])

    let result = report.cases[0]
    XCTAssertEqual(result.selectionStatus, "autoSelected")
    XCTAssertEqual(result.resolutionStatus, "resolved")
    XCTAssertEqual(result.topFdcID, 42)
    XCTAssertEqual(result.consumedGrams, 205)
  }

  func testRunnerIncludesRawInputOnlyWithExplicitOptIn() async {
    let runner = EvalRunner(
      provider: EmptyFoodProvider(),
      parseMode: .fake,
      includeInput: true
    )
    let report = await runner.run(cases: [
      EvalCaseInput(
        id: "private-prompt",
        description: "my private food description",
        parsedOverride: ParsedFoodRequest(productName: "food", searchTerms: "food")
      )
    ])

    XCTAssertTrue(report.includesInputText)
    XCTAssertEqual(report.cases[0].input, "my private food description")
  }

  func testDefaultEncodedReportDoesNotContainRawInput() async throws {
    let secretPrompt = "private family recipe phrase"
    let report = await EvalRunner(provider: EmptyFoodProvider(), parseMode: .fake).run(cases: [
      EvalCaseInput(
        id: "redaction-probe",
        description: secretPrompt,
        parsedOverride: ParsedFoodRequest(productName: "food", searchTerms: "food")
      )
    ])

    let data = try JSONEncoder().encode(report)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.contains(secretPrompt))
    XCTAssertFalse(report.includesInputText)
  }

  func testCompetingDerivativeKeepsDistinctiveExactMatchInPicker() async {
    let runner = EvalRunner(provider: CompetingExactFoodProvider(), parseMode: .fake)
    let report = await runner.run(cases: [
      EvalCaseInput(
        id: "competing-big-mac",
        description: "1 Big Mac",
        parsedOverride: ParsedFoodRequest(
          productName: "Big Mac",
          searchTerms: "Big Mac",
          quantity: 1,
          unit: "item"
        )
      )
    ])

    let result = report.cases[0]
    XCTAssertEqual(result.topDescription, "Big Mac")
    XCTAssertEqual(result.selectionStatus, "pickerRequired")
    XCTAssertEqual(result.resolutionStatus, "pickerRequired")
  }

  func testNumericProductIdentityIsNotReportedAsExplicitAmount() {
    let raw = ParsedFoodRequest(productName: "7 Layer Dip", searchTerms: "7 Layer Dip")

    let prepared = EvaluationQuantityPipeline.prepare(raw, sourceText: "7 Layer Dip")

    XCTAssertFalse(prepared.sourceHadExplicitAmount)
    XCTAssertNil(prepared.effective.quantity)
  }

  func testReportCannotPassWhenExplicitSourceQuantityWasLost() {
    var report = passingReport()
    report.checks["explicitSourceQuantityPreserved"] = false

    XCTAssertFalse(report.passed)
  }

  private func passingReport() -> EvalCaseReport {
    EvalCaseReport(
      id: "test",
      input: "2 eggs and 3 bacon strips",
      parseSource: "parsedJSON",
      modelAvailability: nil,
      warmState: "notApplicable",
      parseLatencyMs: nil,
      semanticResponseLatencyMs: nil,
      prewarmLatencyMs: nil,
      inputTokenCount: nil,
      cachedInputTokenCount: nil,
      outputTokenCount: nil,
      reasoningTokenCount: nil,
      totalTokenCount: nil,
      brand: nil,
      productName: "meal",
      rawQuantity: nil,
      rawUnit: nil,
      quantity: nil,
      unit: nil,
      sourceHadExplicitAmount: true,
      quantityRecoveredFromSource: false,
      quantityDefaultedToOneServing: false,
      fractionOfWhole: nil,
      containerSize: nil,
      containerSizeUnit: nil,
      containsMultipleFoods: true,
      searchQuery: "meal",
      topFdcID: 1,
      topDescription: "meal",
      topDataType: "Foundation",
      selectionStatus: "autoSelected",
      resolutionStatus: "needsClarification",
      resolutionDisplay: "Enter the amount you ate.",
      consumedGrams: nil,
      hasEnergy: true,
      energyKcal: nil,
      checks: [
        "energyNutrientPresent": true,
        "consumedGramsFinitePositiveWhenQuantityPresent": true,
        "servingResolved": false,
        "inputHadQuantity": false,
        "explicitSourceQuantityPreserved": true,
      ],
      error: nil
    )
  }
}

private struct EmptyFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(foods: [], totalHits: 0, currentPage: 1, totalPages: 0)
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw EmptyFoodProviderError.unexpectedDetailsRequest
  }
}

private struct ServingBackedFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [FoodSearchResult(fdcID: 1, description: "Banana", dataType: "Branded")],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "Banana",
      dataType: "Branded",
      servingSize: 100,
      servingSizeUnit: "g",
      householdServing: "1 banana",
      nutrientsPer100Grams: [.init(key: .energy, amount: 89)],
      nutrientsPerServing: [.init(key: .energy, amount: 89)]
    )
  }
}

private struct StrongExactFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [FoodSearchResult(fdcID: 42, description: "Big Mac", dataType: "Foundation")],
      totalHits: 1,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    FoodDetails(
      fdcID: fdcID,
      description: "Big Mac",
      dataType: "Foundation",
      servingSize: 205,
      servingSizeUnit: "g",
      householdServing: "1 item",
      nutrientsPer100Grams: [.init(key: .energy, amount: 261)],
      nutrientsPerServing: [.init(key: .energy, amount: 535)]
    )
  }
}

private struct CompetingExactFoodProvider: FoodDataProviding {
  func search(_ request: FoodSearchRequest) async throws -> FoodSearchResponse {
    FoodSearchResponse(
      foods: [
        FoodSearchResult(fdcID: 42, description: "Big Mac", dataType: "Foundation"),
        FoodSearchResult(
          fdcID: 43,
          description: "Big Mac with cheese",
          dataType: "Foundation"
        ),
      ],
      totalHits: 2,
      currentPage: 1,
      totalPages: 1
    )
  }

  func foodDetails(fdcID: Int) async throws -> FoodDetails {
    throw EmptyFoodProviderError.unexpectedDetailsRequest
  }
}

private enum EmptyFoodProviderError: Error {
  case unexpectedDetailsRequest
}
