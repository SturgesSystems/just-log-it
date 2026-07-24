import Foundation

public protocol ContextualFoodDescriptionParsing: FoodDescriptionParsing {
  func parse(semanticContext: String, groundingText: String) async throws -> ParsedFoodRequest
}

/// Content-free timings for work the app owns and can measure directly. Foundation Models does
/// not expose model-loading duration, so callers must keep session acquisition, prewarm, and
/// response generation as separate observable intervals instead of inferring a loading time.
public struct FoodInterpretationPhaseDurations: Sendable, Equatable {
  public let deterministicExtraction: Duration
  public let routeDecision: Duration
  public let semanticGroundingAndMerge: Duration?

  public init(
    deterministicExtraction: Duration,
    routeDecision: Duration,
    semanticGroundingAndMerge: Duration? = nil
  ) {
    self.deterministicExtraction = deterministicExtraction
    self.routeDecision = routeDecision
    self.semanticGroundingAndMerge = semanticGroundingAndMerge
  }
}

public struct HybridFoodInterpretationResult: Sendable, Equatable {
  public let evidence: FoodTextEvidence
  public let initialDecision: FoodInterpretationRoutingDecision
  public let finalDecision: FoodInterpretationRoutingDecision
  public let request: ParsedFoodRequest
  public let terminalResolution: FoodInterpretationTerminalResolution
  public let modelInvoked: Bool
  public let semanticRejections: [SemanticFactRejection]
  public let phaseDurations: FoodInterpretationPhaseDurations

  public init(
    evidence: FoodTextEvidence,
    initialDecision: FoodInterpretationRoutingDecision,
    finalDecision: FoodInterpretationRoutingDecision,
    request: ParsedFoodRequest,
    terminalResolution: FoodInterpretationTerminalResolution? = nil,
    modelInvoked: Bool,
    semanticRejections: [SemanticFactRejection] = [],
    phaseDurations: FoodInterpretationPhaseDurations = .init(
      deterministicExtraction: .zero,
      routeDecision: .zero
    )
  ) {
    self.evidence = evidence
    self.initialDecision = initialDecision
    self.finalDecision = finalDecision
    self.request = request
    self.terminalResolution =
      terminalResolution
      ?? FoodInterpretationTerminalResolver().resolve(
        request,
        sourceText: evidence.normalizedSource,
        searchRoute: finalDecision.route
      )
    self.modelInvoked = modelInvoked
    self.semanticRejections = semanticRejections
    self.phaseDurations = phaseDurations
  }
}

/// Executes exactly one selected route. A deterministic or clarification route never invokes the
/// semantic proposer, and a semantic route invokes it at most once.
public struct HybridFoodInterpreter: ContextualFoodDescriptionParsing, Sendable {
  private let proposer: any SemanticFoodProposing
  private let extractor: FoodTextEvidenceExtractor
  private let routingPolicy: HybridInterpretationRoutingPolicy
  private let proposalGrounder: SemanticFoodProposalGrounder
  private let merger: SemanticFoodProposalMerger
  private let promotionPolicy: DeterministicFoodPromotionPolicy
  private let nonPromotedPolicy: NonPromotedDeterministicRoutingPolicy
  private let terminalResolver: FoodInterpretationTerminalResolver

  public init(
    proposer: any SemanticFoodProposing,
    extractor: FoodTextEvidenceExtractor = .init(),
    routingPolicy: HybridInterpretationRoutingPolicy = .init(),
    proposalGrounder: SemanticFoodProposalGrounder = .init(),
    merger: SemanticFoodProposalMerger = .init(),
    promotionPolicy: DeterministicFoodPromotionPolicy = .initialProduction,
    nonPromotedPolicy: NonPromotedDeterministicRoutingPolicy = .init(),
    terminalResolver: FoodInterpretationTerminalResolver = .init()
  ) {
    self.proposer = proposer
    self.extractor = extractor
    self.routingPolicy = routingPolicy
    self.proposalGrounder = proposalGrounder
    self.merger = merger
    self.promotionPolicy = promotionPolicy
    self.nonPromotedPolicy = nonPromotedPolicy
    self.terminalResolver = terminalResolver
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
    groundingText: String,
    turnCount: Int = 0
  ) async throws -> HybridFoodInterpretationResult {
    let extractionStarted = ContinuousClock.now
    let evidence = extractor.extract(from: groundingText)
    let extractionDuration = extractionStarted.duration(to: .now)
    let routeStarted = ContinuousClock.now
    let initial = routingPolicy.decide(for: evidence)
    let promotedFamily = promotionPolicy.promotedFamily(for: evidence)
    let routeDuration = routeStarted.duration(to: .now)
    let initialDurations = FoodInterpretationPhaseDurations(
      deterministicExtraction: extractionDuration,
      routeDecision: routeDuration
    )

    switch initial.route {
    case .deterministicSearch:
      guard promotedFamily != nil, let request = merger.deterministicRequest(from: evidence) else {
        return try await nonPromotedResult(
          for: evidence,
          semanticContext: semanticContext,
          groundingText: groundingText,
          initial: initial,
          turnCount: turnCount,
          phaseDurations: initialDurations
        )
      }
      return result(
        evidence, initial, initial, request, sourceText: groundingText, turnCount: turnCount,
        modelInvoked: false,
        phaseDurations: initialDurations)

    case .clarification:
      let request = clarificationRequest(for: evidence, reasons: initial.reasons)
      let proposedFinal =
        request.clarificationPrompt?.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty == false
        ? initial
        : FoodInterpretationRoutingDecision(route: .manualSearch, reasons: initial.reasons)
      return result(
        evidence,
        initial,
        proposedFinal,
        request,
        sourceText: groundingText,
        turnCount: turnCount,
        modelInvoked: false,
        phaseDurations: initialDurations
      )

    case .onDeviceSemantic:
      return try await semanticResult(
        semanticContext: semanticContext,
        groundingText: groundingText,
        evidence: evidence,
        initial: initial,
        turnCount: turnCount,
        phaseDurations: initialDurations
      )

    case .composite, .manualSearch, .pccCandidate:
      // The phase-one policy does not emit these as initial routes. Preserve a safe local result
      // if a future injected policy does so before the coordinator grows a dedicated handler.
      return result(
        evidence, initial, initial, emptyRequest(), sourceText: groundingText,
        turnCount: turnCount, modelInvoked: false,
        phaseDurations: initialDurations)
    }
  }

  private func semanticResult(
    semanticContext: String,
    groundingText: String,
    evidence: FoodTextEvidence,
    initial: FoodInterpretationRoutingDecision,
    turnCount: Int,
    phaseDurations: FoodInterpretationPhaseDurations,
    finalReasons: [FoodInterpretationRouteReason]? = nil
  ) async throws -> HybridFoodInterpretationResult {
    do {
      let proposal = try await proposer.propose(
        .init(semanticContext: semanticContext, groundingText: groundingText)
      )
      // A cancelled, non-cooperative implementation must not publish a late model answer.
      try Task.checkCancellation()
      let groundingStarted = ContinuousClock.now
      let grounding = proposalGrounder.ground(proposal, against: groundingText)
      guard let grounded = grounding.grounded else {
        let groundingDuration = groundingStarted.duration(to: .now)
        let final = FoodInterpretationRoutingDecision(
          route: .manualSearch,
          reasons: [.invalidOnDeviceProposal]
        )
        return result(
          evidence,
          initial,
          final,
          emptyRequest(),
          sourceText: groundingText,
          turnCount: turnCount,
          modelInvoked: true,
          rejections: grounding.rejections,
          phaseDurations: .init(
            deterministicExtraction: phaseDurations.deterministicExtraction,
            routeDecision: phaseDurations.routeDecision,
            semanticGroundingAndMerge: groundingDuration
          )
        )
      }
      let request = merger.merge(grounded, with: evidence)
      let groundingDuration = groundingStarted.duration(to: .now)
      let final = FoodInterpretationRoutingDecision(
        route: request.containsMultipleFoods ? .composite : .onDeviceSemantic,
        reasons: finalReasons ?? initial.reasons
      )
      return result(
        evidence,
        initial,
        final,
        request,
        sourceText: groundingText,
        turnCount: turnCount,
        modelInvoked: true,
        rejections: grounding.rejections,
        phaseDurations: .init(
          deterministicExtraction: phaseDurations.deterministicExtraction,
          routeDecision: phaseDurations.routeDecision,
          semanticGroundingAndMerge: groundingDuration
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as SemanticFoodProposalError {
      let reason: FoodInterpretationRouteReason =
        error == .unavailable
        ? .semanticUnavailable
        : error == .refused ? .semanticRefused : .invalidOnDeviceProposal
      let final = FoodInterpretationRoutingDecision(route: .manualSearch, reasons: [reason])
      return result(
        evidence, initial, final, emptyRequest(), sourceText: groundingText,
        turnCount: turnCount, modelInvoked: true,
        phaseDurations: phaseDurations)
    } catch {
      // SemanticFoodProposing has an untyped throws contract. Treat an implementation-specific
      // failure as an invalid proposal so it cannot escape into the logging flow.
      let final = FoodInterpretationRoutingDecision(
        route: .manualSearch,
        reasons: [.invalidOnDeviceProposal]
      )
      return result(
        evidence, initial, final, emptyRequest(), sourceText: groundingText,
        turnCount: turnCount, modelInvoked: true,
        phaseDurations: phaseDurations)
    }
  }

  private func clarificationRequest(
    for evidence: FoodTextEvidence,
    reasons: [FoodInterpretationRouteReason]
  ) -> ParsedFoodRequest {
    guard !reasons.contains(.promptInjectionLanguage),
      var request = merger.deterministicRequest(from: evidence)
    else { return emptyRequest() }
    request.quantityNeedsClarification =
      reasons.contains(.unresolvedQuantity)
    if request.quantityNeedsClarification {
      request.clarificationPrompt = "How much did you have?"
    }
    return request
  }

  private func nonPromotedResult(
    for evidence: FoodTextEvidence,
    semanticContext: String,
    groundingText: String,
    initial: FoodInterpretationRoutingDecision,
    turnCount: Int,
    phaseDurations: FoodInterpretationPhaseDurations
  ) async throws -> HybridFoodInterpretationResult {
    switch nonPromotedPolicy.decide(for: evidence, promotionPolicy: promotionPolicy) {
    case .semanticInterpretationForGroundedApproximation:
      return try await semanticResult(
        semanticContext: semanticContext,
        groundingText: groundingText,
        evidence: evidence,
        initial: initial,
        turnCount: turnCount,
        phaseDurations: phaseDurations,
        finalReasons: [.groundedApproximation]
      )
    case .manualSearchUnsafeAmountBinding:
      return manualSearchResult(
        evidence, initial, sourceText: groundingText, turnCount: turnCount,
        reason: .unsafeAmountBinding, phaseDurations: phaseDurations)
    case .manualSearchDisabledFamily:
      return manualSearchResult(
        evidence, initial, sourceText: groundingText, turnCount: turnCount,
        reason: .deterministicFamilyDisabled, phaseDurations: phaseDurations)
    case .manualSearchUnsupportedShape:
      return manualSearchResult(
        evidence, initial, sourceText: groundingText, turnCount: turnCount,
        reason: .unsupportedDeterministicShape,
        phaseDurations: phaseDurations)
    }
  }

  private func manualSearchResult(
    _ evidence: FoodTextEvidence,
    _ initial: FoodInterpretationRoutingDecision,
    sourceText: String,
    turnCount: Int,
    reason: FoodInterpretationRouteReason,
    phaseDurations: FoodInterpretationPhaseDurations
  ) -> HybridFoodInterpretationResult {
    result(
      evidence,
      initial,
      .init(route: .manualSearch, reasons: [reason]),
      emptyRequest(),
      sourceText: sourceText,
      turnCount: turnCount,
      modelInvoked: false,
      phaseDurations: phaseDurations
    )
  }

  private func emptyRequest() -> ParsedFoodRequest {
    ParsedFoodRequest(productName: "", searchTerms: "")
  }

  private func result(
    _ evidence: FoodTextEvidence,
    _ initial: FoodInterpretationRoutingDecision,
    _ final: FoodInterpretationRoutingDecision,
    _ request: ParsedFoodRequest,
    sourceText: String,
    turnCount: Int,
    modelInvoked: Bool,
    rejections: [SemanticFactRejection] = [],
    phaseDurations: FoodInterpretationPhaseDurations
  ) -> HybridFoodInterpretationResult {
    let policyResolution = terminalResolver.resolve(
      request,
      sourceText: sourceText,
      turnCount: turnCount,
      searchRoute: final.route
    )
    let terminalResolution: FoodInterpretationTerminalResolution =
      switch final.route {
      case .manualSearch:
        .init(
          draft: policyResolution.draft,
          decision: .requireEdit(
            "Edit the USDA search terms or enter nutrition manually."
          ),
          route: .manualSearch
        )
      case .pccCandidate:
        .init(
          draft: policyResolution.draft,
          decision: .fallbackManual(
            "Enhanced interpretation is not available. Edit the search or enter nutrition manually."
          ),
          route: .pccCandidate
        )
      case .deterministicSearch, .onDeviceSemantic, .clarification, .composite:
        policyResolution
      }
    let resolvedFinal: FoodInterpretationRoutingDecision =
      switch final.route {
      case .manualSearch, .pccCandidate:
        final
      case .deterministicSearch, .onDeviceSemantic, .clarification, .composite:
        .init(route: terminalResolution.route, reasons: final.reasons)
      }
    return .init(
      evidence: evidence,
      initialDecision: initial,
      finalDecision: resolvedFinal,
      request: request,
      terminalResolution: terminalResolution,
      modelInvoked: modelInvoked,
      semanticRejections: rejections,
      phaseDurations: phaseDurations
    )
  }
}
