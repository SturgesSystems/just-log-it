import Foundation

/// Grounds a semantic proposal and overlays deterministic evidence as the authority.
public struct SemanticFoodProposalMerger: Sendable {
  public init() {}

  public func merge(
    _ proposal: SemanticFoodProposal,
    with evidence: FoodTextEvidence,
    groundingText: String? = nil
  ) -> ParsedFoodRequest {
    let result = SemanticFoodProposalGrounder().ground(
      proposal,
      against: groundingText ?? evidence.normalizedSource
    )
    guard let grounded = result.grounded else {
      return request(with: evidence, productName: "")
    }
    return merge(grounded, with: evidence)
  }

  public func merge(
    _ grounded: GroundedSemanticFoodProposal,
    with evidence: FoodTextEvidence
  ) -> ParsedFoodRequest {
    let components = deduplicated(grounded.componentNames)
    let isComposite = grounded.containsMultipleFoods
    let productName = isComposite ? "" : grounded.productName
    let explicitDescriptors = evidence.explicitDescriptors.compactMap(cleaned)
    let descriptors = deduplicated(explicitDescriptors + grounded.descriptors)

    return request(
      with: evidence,
      productName: productName,
      brand: evidence.explicitBrand ?? grounded.brand,
      preparation: evidence.explicitPreparation ?? grounded.preparation,
      descriptors: descriptors,
      containsMultipleFoods: isComposite,
      componentNames: isComposite ? components : []
    )
  }

  /// Builds the same request shape for a route that does not need semantic interpretation.
  public func deterministicRequest(from evidence: FoodTextEvidence) -> ParsedFoodRequest? {
    guard let identity = cleaned(evidence.identityCandidate) else { return nil }
    return request(
      with: evidence,
      productName: identity,
      brand: evidence.explicitBrand,
      preparation: evidence.explicitPreparation,
      descriptors: deduplicated(evidence.explicitDescriptors)
    )
  }

  private func request(
    with evidence: FoodTextEvidence,
    productName: String,
    brand: String? = nil,
    preparation: String? = nil,
    descriptors: [String] = [],
    containsMultipleFoods: Bool = false,
    componentNames: [String] = []
  ) -> ParsedFoodRequest {
    // A source-level amount near one component does not describe the aggregate meal. Quantities
    // stay in the source-supported component labels and are recovered by CompositeComponentRequest
    // when each component is resolved independently.
    let carriesWholeFoodAmount = !containsMultipleFoods
    return ParsedFoodRequest(
      brand: brand,
      productName: productName,
      searchTerms: productName,
      quantity: carriesWholeFoodAmount ? evidence.quantity?.value : nil,
      unit: carriesWholeFoodAmount ? evidence.quantity?.unit : nil,
      quantityText: carriesWholeFoodAmount ? evidence.quantity?.sourceText : nil,
      fractionOfWhole: carriesWholeFoodAmount ? evidence.fraction?.value : nil,
      wholeUnit: carriesWholeFoodAmount ? evidence.fraction?.wholeUnit : nil,
      containerSize: carriesWholeFoodAmount ? evidence.container?.size : nil,
      containerSizeUnit: carriesWholeFoodAmount ? evidence.container?.unit : nil,
      alternateQuantity: carriesWholeFoodAmount ? evidence.alternateQuantity?.value : nil,
      alternateUnit: carriesWholeFoodAmount ? evidence.alternateQuantity?.unit : nil,
      preparation: preparation,
      descriptors: descriptors,
      isApproximate: !evidence.approximationMarkers.isEmpty,
      containsMultipleFoods: containsMultipleFoods,
      multipleFoodAssessment: containsMultipleFoods ? .multiple : .single,
      componentNames: componentNames
    )
  }

  private func cleaned(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }

  private func deduplicated(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { value in
      seen.insert(
        value.folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: Locale(identifier: "en_US_POSIX")
        )
      )
      .inserted
    }
  }
}
