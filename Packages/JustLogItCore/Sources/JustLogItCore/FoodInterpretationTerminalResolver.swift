import Foundation

/// The authoritative pre-USDA terminal outcome shared by the hybrid coordinator, app, and
/// evaluation tools. Keeping the validated draft and policy decision together prevents callers
/// from reporting a route that the UI would subsequently replace with clarification or recovery.
public struct FoodInterpretationTerminalResolution: Sendable, Equatable {
  public let draft: FoodInterpretationDraft
  public let decision: ClarificationDecision
  public let route: FoodInterpretationRoute

  public init(
    draft: FoodInterpretationDraft,
    decision: ClarificationDecision,
    route: FoodInterpretationRoute
  ) {
    self.draft = draft
    self.decision = decision
    self.route = route
  }
}

/// Runs the same deterministic validation and clarification policy at every interpretation
/// boundary. `searchRoute` records which architecture produced a search-ready request; policy
/// outcomes always win when they instead require a composite, clarification, or manual recovery.
public struct FoodInterpretationTerminalResolver: Sendable {
  private let validator: FoodInterpretationValidator
  private let clarificationPolicy: ClarificationPolicy

  public init(
    validator: FoodInterpretationValidator = .init(),
    clarificationPolicy: ClarificationPolicy = .init()
  ) {
    self.validator = validator
    self.clarificationPolicy = clarificationPolicy
  }

  public func resolve(
    _ request: ParsedFoodRequest,
    sourceText: String,
    evidenceKind: EvidenceSourceKind = .typedText,
    turnCount: Int = 0,
    searchRoute: FoodInterpretationRoute
  ) -> FoodInterpretationTerminalResolution {
    let draft = validator.draft(
      from: request,
      sourceText: sourceText,
      evidenceKind: evidenceKind,
      turnCount: turnCount
    )
    let decision = clarificationPolicy.decide(draft)
    let route: FoodInterpretationRoute =
      switch decision {
      case .proceed:
        searchRoute
      case .beginComposite:
        .composite
      case .clarify:
        .clarification
      case .requireEdit, .fallbackManual:
        .manualSearch
      }
    return .init(draft: draft, decision: decision, route: route)
  }
}
