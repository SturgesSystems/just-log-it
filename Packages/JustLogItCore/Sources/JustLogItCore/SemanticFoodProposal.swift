import Foundation

/// A deliberately narrow semantic proposal. Implementations may use an on-device model,
/// PCC, or a test double, but they never own quantity, serving, nutrition, or UI decisions.
public struct SemanticFoodProposal: Sendable, Equatable, Codable {
  public var productName: String
  public var brand: String?
  public var preparation: String?
  public var descriptors: [String]
  public var containsMultipleFoods: Bool
  public var componentNames: [String]

  public init(
    productName: String,
    brand: String? = nil,
    preparation: String? = nil,
    descriptors: [String] = [],
    containsMultipleFoods: Bool = false,
    componentNames: [String] = []
  ) {
    self.productName = productName
    self.brand = brand
    self.preparation = preparation
    self.descriptors = descriptors
    self.containsMultipleFoods = containsMultipleFoods
    self.componentNames = componentNames
  }
}

public struct SemanticFoodProposalInput: Sendable, Equatable {
  /// Bounded context that may include a deterministic clarification question and current reply.
  public let semanticContext: String
  /// User-authored facts only. Model output must be grounded against this value, never context.
  public let groundingText: String

  public init(semanticContext: String, groundingText: String) {
    self.semanticContext = semanticContext
    self.groundingText = groundingText
  }
}

public enum SemanticFoodProposalError: Error, Sendable, Equatable {
  case unavailable
  case refused
  case invalidResponse
}

/// Implementations return facts, not a USDA query, serving assumption, nutrition estimate, or
/// user-facing prose. Grounding is intentionally a separate deterministic step.
public protocol SemanticFoodProposing: Sendable {
  func propose(_ input: SemanticFoodProposalInput) async throws -> SemanticFoodProposal
}
