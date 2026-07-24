import Foundation

public enum DeterministicFoodFamily: String, Sendable, Equatable, Codable, CaseIterable {
  case identityOnly
  case countedItem
  case massMeasured
  case volumeMeasured
  case fractionOfWhole
  case fractionOfSizedContainer
}

/// Closed, reviewable allowlist for deterministic production promotion. Adding extractor behavior
/// cannot silently promote a new family; the family must also be admitted here.
public struct DeterministicFoodPromotionPolicy: Sendable {
  public static let initialProduction = DeterministicFoodPromotionPolicy(
    promotedFamilies: Set(DeterministicFoodFamily.allCases)
  )

  public let promotedFamilies: Set<DeterministicFoodFamily>

  public init(promotedFamilies: Set<DeterministicFoodFamily>) {
    self.promotedFamilies = promotedFamilies
  }

  public func promotedFamily(for evidence: FoodTextEvidence) -> DeterministicFoodFamily? {
    guard let family = classify(evidence), promotedFamilies.contains(family) else { return nil }
    return family
  }

  public func classify(_ evidence: FoodTextEvidence) -> DeterministicFoodFamily? {
    guard evidence.identityCandidate?.isEmpty == false,
      !evidence.containsPromptInjectionLanguage,
      !evidence.hasUnresolvedQuantity,
      evidence.possibleMultipleFoodConnectors.isEmpty,
      evidence.unresolvedReferences.isEmpty,
      evidence.alternateQuantity == nil
    else { return nil }

    guard evidence.approximationMarkers.isEmpty else { return nil }
    return structurallyClassify(evidence)
  }

  /// Classifies a structurally complete request while deliberately ignoring approximation.
  /// This does not authorize a fast path. It exists so the rejected-route policy can distinguish
  /// a source-grounded estimate that needs confirmation from an unsafe number/unit binding.
  public func structurallyClassify(
    _ evidence: FoodTextEvidence
  ) -> DeterministicFoodFamily? {
    guard evidence.identityCandidate?.isEmpty == false,
      !evidence.containsPromptInjectionLanguage,
      !evidence.hasUnresolvedQuantity,
      evidence.possibleMultipleFoodConnectors.isEmpty,
      evidence.unresolvedReferences.isEmpty,
      evidence.alternateQuantity == nil
    else { return nil }

    if evidence.fraction != nil {
      guard evidence.quantity == nil else { return nil }
      return evidence.container == nil ? .fractionOfWhole : .fractionOfSizedContainer
    }
    guard evidence.container == nil else { return nil }
    guard let quantity = evidence.quantity else { return .identityOnly }
    guard quantity.value.isFinite, quantity.value > 0, let unit = quantity.unit else { return nil }
    switch UnitConversion.dimension(of: unit) {
    case .mass: return .massMeasured
    case .volume: return .volumeMeasured
    case .count, .serving:
      return .countedItem
    case .unknown:
      // Unknown nouns are promoted as counts only for the deliberately small first-slice list.
      // This prevents text such as “2 scoops protein powder” from treating `powder` as the unit.
      return Self.initialCountNouns.contains(UnitConversion.family(unit)) ? .countedItem : nil
    }
  }

  private static let initialCountNouns: Set<String> = [
    "apple", "banana", "cookie", "egg",
  ]
}

/// A typed terminal policy for shapes that the broad deterministic router recognizes but the
/// production allowlist does not promote. Semantic inference is allowed only when the rejected
/// fact is a recognized, source-grounded approximation. It cannot repair a questionable amount
/// binding because the authoritative merger would overlay that binding afterward.
public enum NonPromotedDeterministicDisposition: Sendable, Equatable {
  case semanticInterpretationForGroundedApproximation(DeterministicFoodFamily)
  case manualSearchUnsafeAmountBinding
  case manualSearchDisabledFamily(DeterministicFoodFamily)
  case manualSearchUnsupportedShape
}

public struct NonPromotedDeterministicRoutingPolicy: Sendable {
  public init() {}

  public func decide(
    for evidence: FoodTextEvidence,
    promotionPolicy: DeterministicFoodPromotionPolicy
  ) -> NonPromotedDeterministicDisposition {
    if !evidence.approximationMarkers.isEmpty,
      let family = promotionPolicy.structurallyClassify(evidence)
    {
      guard promotionPolicy.promotedFamilies.contains(family) else {
        return .manualSearchDisabledFamily(family)
      }
      return .semanticInterpretationForGroundedApproximation(family)
    }

    if let family = promotionPolicy.classify(evidence) {
      return .manualSearchDisabledFamily(family)
    }

    if let quantity = evidence.quantity,
      let unit = quantity.unit,
      UnitConversion.dimension(of: unit) == .unknown
    {
      return .manualSearchUnsafeAmountBinding
    }

    return .manualSearchUnsupportedShape
  }
}

public struct DeterministicFirstFoodParsingResult: Sendable, Equatable {
  public let request: ParsedFoodRequest
  public let routingDecision: FoodInterpretationRoutingDecision
  public let usedDeterministicFastPath: Bool
  public let promotedFamily: DeterministicFoodFamily?
  public let phaseDurations: FoodInterpretationPhaseDurations

  public init(
    request: ParsedFoodRequest,
    routingDecision: FoodInterpretationRoutingDecision,
    usedDeterministicFastPath: Bool,
    promotedFamily: DeterministicFoodFamily?,
    phaseDurations: FoodInterpretationPhaseDurations = .init(
      deterministicExtraction: .zero,
      routeDecision: .zero
    )
  ) {
    self.request = request
    self.routingDecision = routingDecision
    self.usedDeterministicFastPath = usedDeterministicFastPath
    self.promotedFamily = promotedFamily
    self.phaseDurations = phaseDurations
  }
}

/// Promotes only the conservative deterministic-search family. Every other family is delegated to
/// the supplied parser, allowing the shipping model-first implementation to remain the fallback
/// until the minimal semantic candidate passes its physical-device promotion gate.
public struct DeterministicFirstFoodParser: ContextualFoodDescriptionParsing, Sendable {
  private let fallback: any FoodDescriptionParsing
  private let extractor: FoodTextEvidenceExtractor
  private let routingPolicy: HybridInterpretationRoutingPolicy
  private let merger: SemanticFoodProposalMerger
  private let promotionPolicy: DeterministicFoodPromotionPolicy

  public init(
    fallback: any FoodDescriptionParsing,
    extractor: FoodTextEvidenceExtractor = .init(),
    routingPolicy: HybridInterpretationRoutingPolicy = .init(),
    merger: SemanticFoodProposalMerger = .init(),
    promotionPolicy: DeterministicFoodPromotionPolicy = .initialProduction
  ) {
    self.fallback = fallback
    self.extractor = extractor
    self.routingPolicy = routingPolicy
    self.merger = merger
    self.promotionPolicy = promotionPolicy
  }

  public func parse(_ input: String) async throws -> ParsedFoodRequest {
    try await parse(semanticContext: input, groundingText: input)
  }

  public func parse(
    semanticContext: String,
    groundingText: String
  ) async throws -> ParsedFoodRequest {
    try await interpret(semanticContext: semanticContext, groundingText: groundingText).request
  }

  public func interpret(
    semanticContext: String,
    groundingText: String
  ) async throws -> DeterministicFirstFoodParsingResult {
    try Task.checkCancellation()
    let extractionStarted = ContinuousClock.now
    let evidence = extractor.extract(from: groundingText)
    let extractionDuration = extractionStarted.duration(to: .now)
    let routeStarted = ContinuousClock.now
    let decision = routingPolicy.decide(for: evidence)
    let family = promotionPolicy.promotedFamily(for: evidence)
    let routeDuration = routeStarted.duration(to: .now)
    let phaseDurations = FoodInterpretationPhaseDurations(
      deterministicExtraction: extractionDuration,
      routeDecision: routeDuration
    )
    if decision.route == .deterministicSearch,
      let family,
      let request = merger.deterministicRequest(from: evidence)
    {
      return .init(
        request: request,
        routingDecision: decision,
        usedDeterministicFastPath: true,
        promotedFamily: family,
        phaseDurations: phaseDurations
      )
    }

    let request = try await fallback.parse(
      semanticContext: semanticContext,
      groundingText: groundingText
    )
    try Task.checkCancellation()
    return .init(
      request: request,
      routingDecision: decision,
      usedDeterministicFastPath: false,
      promotedFamily: nil,
      phaseDurations: phaseDurations
    )
  }
}
