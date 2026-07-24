import Foundation

/// A stable range into `FoodTextEvidence.normalizedSource`.
///
/// UTF-16 offsets deliberately match `NSRange` and remain deterministic across Swift `String`
/// index implementations. Callers must interpret the range against `normalizedSource`, never the
/// original unnormalized message.
public struct FoodEvidenceSourceRange: Sendable, Equatable, Codable {
  public let location: Int
  public let length: Int

  public init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }
}

public enum FoodEvidenceField: String, Sendable, Equatable, Codable {
  case identity
  case brand
  case preparation
  case descriptor
  case quantity
  case fraction
  case container
  case alternateQuantity
}

/// Source-backed proof for a material deterministic fact. `sourceText` is intentionally retained
/// only in the ephemeral evidence value; it must not be logged or persisted.
public struct FoodEvidenceProvenance: Sendable, Equatable, Codable {
  public let field: FoodEvidenceField
  public let sourceText: String
  public let range: FoodEvidenceSourceRange

  public init(field: FoodEvidenceField, sourceText: String, range: FoodEvidenceSourceRange) {
    self.field = field
    self.sourceText = sourceText
    self.range = range
  }
}

/// Deterministic quantity evidence extracted directly from the person's text.
/// This is authoritative over any later model proposal.
public struct FoodQuantityEvidence: Sendable, Equatable, Codable {
  public let value: Double
  public let unit: String?
  public let sourceText: String

  public init(value: Double, unit: String?, sourceText: String) {
    self.value = value
    self.unit = unit
    self.sourceText = sourceText
  }
}

public struct FoodFractionEvidence: Sendable, Equatable, Codable {
  public let value: Double
  public let wholeUnit: String?

  public init(value: Double, wholeUnit: String?) {
    self.value = value
    self.wholeUnit = wholeUnit
  }
}

public struct FoodContainerEvidence: Sendable, Equatable, Codable {
  public let size: Double
  public let unit: String
  public let containerKind: String?

  public init(size: Double, unit: String, containerKind: String?) {
    self.size = size
    self.unit = unit
    self.containerKind = containerKind
  }
}

/// Facts Swift can prove without invoking a language model.
///
/// The value is intentionally ephemeral. It may contain normalized user text and must not be
/// persisted to diagnostics, analytics, or a new side-channel store.
public struct FoodTextEvidence: Sendable, Equatable, Codable {
  public let normalizedSource: String
  public let identityCandidate: String?
  public let explicitBrand: String?
  public let quantity: FoodQuantityEvidence?
  public let fraction: FoodFractionEvidence?
  public let container: FoodContainerEvidence?
  public let alternateQuantity: FoodQuantityEvidence?
  public let explicitPreparation: String?
  public let explicitDescriptors: [String]
  public let approximationMarkers: [String]
  public let possibleMultipleFoodConnectors: [String]
  public let unresolvedReferences: [String]
  public let strippedLoggingLanguage: [String]
  public let containsPromptInjectionLanguage: Bool
  public let hasUnresolvedQuantity: Bool
  public let provenance: [FoodEvidenceProvenance]

  public init(
    normalizedSource: String,
    identityCandidate: String?,
    explicitBrand: String? = nil,
    quantity: FoodQuantityEvidence? = nil,
    fraction: FoodFractionEvidence? = nil,
    container: FoodContainerEvidence? = nil,
    alternateQuantity: FoodQuantityEvidence? = nil,
    explicitPreparation: String? = nil,
    explicitDescriptors: [String] = [],
    approximationMarkers: [String] = [],
    possibleMultipleFoodConnectors: [String] = [],
    unresolvedReferences: [String] = [],
    strippedLoggingLanguage: [String] = [],
    containsPromptInjectionLanguage: Bool = false,
    hasUnresolvedQuantity: Bool = false,
    provenance: [FoodEvidenceProvenance] = []
  ) {
    self.normalizedSource = normalizedSource
    self.identityCandidate = identityCandidate
    self.explicitBrand = explicitBrand
    self.quantity = quantity
    self.fraction = fraction
    self.container = container
    self.alternateQuantity = alternateQuantity
    self.explicitPreparation = explicitPreparation
    self.explicitDescriptors = explicitDescriptors
    self.approximationMarkers = approximationMarkers
    self.possibleMultipleFoodConnectors = possibleMultipleFoodConnectors
    self.unresolvedReferences = unresolvedReferences
    self.strippedLoggingLanguage = strippedLoggingLanguage
    self.containsPromptInjectionLanguage = containsPromptInjectionLanguage
    self.hasUnresolvedQuantity = hasUnresolvedQuantity
    self.provenance = provenance
  }
}
