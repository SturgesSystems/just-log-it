import Foundation
import JustLogItCore

enum FoodParserArchitecture: Sendable, Equatable {
  case baseline22Field
  case deterministicFastPath
  case fullHybrid
}

enum FoodParserSelectionError: Error, Equatable {
  case conflictingDebugOverrides
}

enum FoodParserFactory {
  /// Release promotes only the closed deterministic family allowlist. Semantic and excluded inputs
  /// continue through the established 22-field parser until full hybrid passes device evaluation.
  static let productionDefault: FoodParserArchitecture = .deterministicFastPath

  static func selectedArchitecture(
    arguments: [String],
    honorsDebugOverrides: Bool
  ) throws -> FoodParserArchitecture {
    guard honorsDebugOverrides else { return productionDefault }
    let overrides: [(String, FoodParserArchitecture)] = [
      ("-baseline-parser", .baseline22Field),
      ("-deterministic-parser", .deterministicFastPath),
      ("-hybrid-parser", .fullHybrid),
    ]
    let selected = overrides.filter { arguments.contains($0.0) }
    guard selected.count <= 1 else { throw FoodParserSelectionError.conflictingDebugOverrides }
    return selected.first?.1 ?? productionDefault
  }

  static func make(arguments: [String] = ProcessInfo.processInfo.arguments)
    -> any FoodDescriptionParsing
  {
    #if DEBUG
      let honorsDebugOverrides = true
    #else
      let honorsDebugOverrides = false
    #endif
    let architecture: FoodParserArchitecture
    do {
      architecture = try selectedArchitecture(
        arguments: arguments,
        honorsDebugOverrides: honorsDebugOverrides
      )
    } catch {
      assertionFailure("Conflicting food parser launch overrides")
      architecture = productionDefault
    }
    AppObservability.recordParserArchitecture(architecture.observationValue)
    switch architecture {
    case .baseline22Field:
      return FoundationModelsFoodParser()
    case .deterministicFastPath:
      return FoundationModelsDeterministicFirstFoodParser()
    case .fullHybrid:
      return FoundationModelsHybridFoodParser()
    }
  }
}

struct FoundationModelsDeterministicFirstFoodParser: ContextualFoodDescriptionParsing,
  FoodDescriptionParserPrewarming
{
  private let parser: DeterministicFirstFoodParser
  private let prewarmAction: @Sendable () async -> Void

  init() {
    let fallback = FoundationModelsFoodParser()
    self.parser = DeterministicFirstFoodParser(fallback: fallback)
    self.prewarmAction = { await fallback.prewarm() }
  }

  init(
    fallback: any FoodDescriptionParsing,
    prewarmAction: @escaping @Sendable () async -> Void = {}
  ) {
    self.parser = DeterministicFirstFoodParser(fallback: fallback)
    self.prewarmAction = prewarmAction
  }

  func prewarm() async {
    await prewarmAction()
  }

  func parse(_ input: String) async throws -> ParsedFoodRequest {
    try await parse(semanticContext: input, groundingText: input)
  }

  func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    let result = try await AppObservability.measure(.hybridPipeline) {
      try await parser.interpret(
        semanticContext: semanticContext,
        groundingText: groundingText
      )
    }
    AppObservability.recordInterpretationPhases(result.phaseDurations)
    AppObservability.recordSemanticInvocation(
      result.usedDeterministicFastPath ? .skipped : .invoked
    )
    AppObservability.recordDeterministicSelection(
      result.promotedFamily?.observationValue ?? .baselineFallback
    )
    if result.usedDeterministicFastPath {
      AppObservability.recordParserRoute(.searchReady)
    }
    return result.request
  }
}

extension AppObservability {
  static func recordInterpretationPhases(_ durations: FoodInterpretationPhaseDurations) {
    recordDuration(.deterministicExtraction, .init(durations.deterministicExtraction))
    recordDuration(.routeDecision, .init(durations.routeDecision))
    if let duration = durations.semanticGroundingAndMerge {
      recordDuration(.semanticGroundingAndMerge, .init(duration))
    }
  }
}

extension FoodParserArchitecture {
  fileprivate var observationValue: AppObservability.ParserArchitecture {
    switch self {
    case .baseline22Field: .baseline22Field
    case .deterministicFastPath: .deterministicFastPath
    case .fullHybrid: .fullHybrid
    }
  }
}

extension DeterministicFoodFamily {
  fileprivate var observationValue: AppObservability.DeterministicSelection {
    switch self {
    case .identityOnly: .identityOnly
    case .countedItem: .countedItem
    case .massMeasured: .massMeasured
    case .volumeMeasured: .volumeMeasured
    case .fractionOfWhole: .fractionOfWhole
    case .fractionOfSizedContainer: .fractionOfSizedContainer
    }
  }
}
