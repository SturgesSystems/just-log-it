import Foundation
import XCTest

@testable import LoggingEval

final class ParserContractParityTests: XCTestCase {
  func testStandaloneEvaluatorMatchesShippingSchemaPromptUseCasesAndReasoningPolicy() throws {
    let repositoryRoot = repositoryRoot
    let shipping = try String(
      contentsOf: repositoryRoot.appending(
        path: "JustLogIt/Services/FoundationModelsFoodParser.swift"),
      encoding: .utf8
    )
    let evaluator = try String(
      contentsOf: repositoryRoot.appending(
        path: "Tools/LoggingEval/Sources/LoggingEval/MacFoundationModelsFoodParser.swift"),
      encoding: .utf8
    )

    XCTAssertEqual(
      normalized(try region(in: evaluator, from: "@Generable(", to: "private let promptProfile:")),
      normalized(
        try region(in: shipping, from: "@Generable(", to: "enum FoundationModelsPromptProfile:"))
    )

    let evaluatorProfiles = try region(
      in: evaluator, from: "enum PromptProfile:", to: "enum ModelUseCase:"
    ).replacingOccurrences(of: "PromptProfile", with: "FoundationModelsPromptProfile")
    XCTAssertEqual(
      normalized(evaluatorProfiles),
      normalized(
        try region(
          in: shipping,
          from: "enum FoundationModelsPromptProfile:",
          to: "/// Experimental model choice"
        ))
    )

    let evaluatorUseCases = try region(
      in: evaluator, from: "enum ModelUseCase:", to: "/// Evaluator-only comparison"
    ).replacingOccurrences(of: "ModelUseCase", with: "FoundationModelsModelUseCase")
    XCTAssertEqual(
      normalized(evaluatorUseCases),
      normalized(
        try region(
          in: shipping,
          from: "enum FoundationModelsModelUseCase:",
          to: "/// Evaluation dimension"
        ))
    )

    let evaluatorReasoningPolicy = try region(
      in: evaluator, from: "enum ReasoningPolicy:", to: "enum ParseError:"
    ).replacingOccurrences(of: "ReasoningPolicy", with: "FoundationModelsReasoningPolicy")
    let shippingReasoningPolicy = try region(
      in: shipping,
      from: "enum FoundationModelsReasoningPolicy:",
      to: "/// Optional capability"
    )
    XCTAssertEqual(
      normalized(evaluatorReasoningPolicy),
      normalized(
        shippingReasoningPolicy
          .replacingOccurrences(of: "#if DEBUG", with: "")
          .replacingOccurrences(of: "#endif", with: "")
      )
    )
    XCTAssertEqual(
      MacFoundationModelsFoodParser.ReasoningPolicy.allCases.map(\.rawValue),
      ["capabilityAwareLight", "disabled"]
    )
    XCTAssertEqual(
      MacFoundationModelsFoodParser.contextOptions(
        supportsReasoning: true,
        reasoningPolicy: .capabilityAwareLight
      ).reasoningLevel,
      .light
    )
    XCTAssertNil(
      MacFoundationModelsFoodParser.contextOptions(
        supportsReasoning: true,
        reasoningPolicy: .disabled
      ).reasoningLevel
    )
    XCTAssertTrue(
      shipping.contains("model.capabilities.contains(.reasoning)"))
    XCTAssertTrue(
      evaluator.contains("model.capabilities.contains(.reasoning)"))
  }

  func testMinimalSemanticSchemaPromptAndGenerationLimitsMatchShipping() throws {
    let shipping = try String(
      contentsOf: repositoryRoot.appending(
        path: "JustLogIt/Services/FoundationModelsSemanticFoodProposer.swift"),
      encoding: .utf8
    )
    let evaluator = try String(
      contentsOf: repositoryRoot.appending(
        path: "Tools/LoggingEval/Sources/LoggingEval/MacFoundationModelsSemanticFoodProposer.swift"),
      encoding: .utf8
    )

    XCTAssertEqual(
      normalized(try markedRegion(in: shipping, marker: "SEMANTIC-PARITY-SCHEMA")),
      normalized(try markedRegion(in: evaluator, marker: "SEMANTIC-PARITY-SCHEMA"))
    )
    let shippingPrompt = try markedRegion(in: shipping, marker: "SEMANTIC-PARITY-PROMPT")
      .replacingOccurrences(
        of: "FoundationModelsSemanticPromptProfile",
        with: "PromptProfile"
      )
    XCTAssertEqual(
      normalized(shippingPrompt),
      normalized(try markedRegion(in: evaluator, marker: "SEMANTIC-PARITY-PROMPT"))
    )
    for contract in [
      "maximumResponseTokens: 192",
      "samplingMode: .greedy",
      "temperature: 0",
      "model.capabilities.contains(.reasoning)",
      "Interpret the current food facts:",
    ] {
      XCTAssertTrue(shipping.contains(contract), "Shipping proposer lost \(contract)")
      XCTAssertTrue(evaluator.contains(contract), "Evaluator proposer lost \(contract)")
    }
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func markedRegion(in source: String, marker: String) throws -> String {
    try region(
      in: source,
      from: "// \(marker)-BEGIN",
      to: "// \(marker)-END"
    )
  }

  private func region(in source: String, from start: String, to end: String) throws -> String {
    guard let startRange = source.range(of: start),
      let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
    else {
      throw NSError(domain: "ParserContractParity", code: 1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
  }

  private func normalized(_ source: String) -> String {
    source
      .replacingOccurrences(of: "private struct", with: "struct")
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
      .replacingOccurrences(of: " )", with: ")")
      .replacingOccurrences(of: "( ", with: "(")
      .replacingOccurrences(of: " ,", with: ",")
  }
}
