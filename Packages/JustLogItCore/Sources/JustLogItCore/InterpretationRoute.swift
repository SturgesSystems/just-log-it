import Foundation

public enum FoodInterpretationRoute: String, Sendable, Equatable, Codable, CaseIterable {
  case deterministicSearch
  case onDeviceSemantic
  case clarification
  case composite
  case manualSearch
  case pccCandidate
}

public enum FoodInterpretationRouteReason: String, Sendable, Equatable, Codable, CaseIterable {
  case completeDeterministicEvidence
  case missingIdentity
  case possibleMultipleFoods
  case unresolvedReference
  case unresolvedQuantity
  case promptInjectionLanguage
  case photoObservation
  case invalidOnDeviceProposal
  case semanticUnavailable
  case semanticRefused
  case deterministicShapeNotPromoted
  case groundedApproximation
  case unsafeAmountBinding
  case deterministicFamilyDisabled
  case unsupportedDeterministicShape
  case unresolvedMultipleFoods
  case complexPhotoObservation
}

public struct FoodInterpretationRoutingDecision: Sendable, Equatable, Codable {
  public let route: FoodInterpretationRoute
  public let reasons: [FoodInterpretationRouteReason]

  public init(route: FoodInterpretationRoute, reasons: [FoodInterpretationRouteReason]) {
    self.route = route
    self.reasons = reasons
  }
}

/// Conservative phase-one policy. It is intentionally not wired into the shipping view model.
public struct HybridInterpretationRoutingPolicy: Sendable {
  public init() {}

  public func decide(for evidence: FoodTextEvidence) -> FoodInterpretationRoutingDecision {
    if evidence.containsPromptInjectionLanguage {
      return .init(route: .clarification, reasons: [.promptInjectionLanguage])
    }
    guard evidence.identityCandidate != nil else {
      return .init(route: .clarification, reasons: [.missingIdentity])
    }
    if evidence.hasUnresolvedQuantity {
      return .init(route: .clarification, reasons: [.unresolvedQuantity])
    }

    var semanticReasons: [FoodInterpretationRouteReason] = []
    if !evidence.unresolvedReferences.isEmpty {
      semanticReasons.append(.unresolvedReference)
    }
    if !evidence.possibleMultipleFoodConnectors.isEmpty {
      semanticReasons.append(.possibleMultipleFoods)
    }
    if !semanticReasons.isEmpty {
      return .init(route: .onDeviceSemantic, reasons: semanticReasons)
    }

    return .init(route: .deterministicSearch, reasons: [.completeDeterministicEvidence])
  }
}
