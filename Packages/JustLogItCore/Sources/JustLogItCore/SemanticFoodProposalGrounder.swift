import Foundation

public enum SemanticFactRejection: String, Sendable, Equatable, Codable, CaseIterable {
  case emptyProduct
  case unsupportedProduct
  case unsupportedBrand
  case unsupportedPreparation
  case unsupportedDescriptor
  case unsupportedComponent
  case inconsistentMultiplicity
  case insufficientComponents
}

/// The only semantic value accepted by the authoritative merger. Its initializer is internal so
/// callers cannot accidentally label raw model output as grounded.
public struct GroundedSemanticFoodProposal: Sendable, Equatable {
  public let productName: String
  public let brand: String?
  public let preparation: String?
  public let descriptors: [String]
  public let containsMultipleFoods: Bool
  public let componentNames: [String]

}

public struct SemanticFoodProposalGroundingResult: Sendable, Equatable {
  public let grounded: GroundedSemanticFoodProposal?
  public let rejections: [SemanticFactRejection]

  public init(
    grounded: GroundedSemanticFoodProposal?,
    rejections: [SemanticFactRejection]
  ) {
    self.grounded = grounded
    self.rejections = rejections
  }
}

public struct SemanticFoodProposalGrounder: Sendable {
  public init() {}

  public func ground(
    _ proposal: SemanticFoodProposal,
    against groundingText: String
  ) -> SemanticFoodProposalGroundingResult {
    let cleanedProduct = cleaned(proposal.productName) ?? ""
    let cleanedBrand = cleaned(proposal.brand)
    let cleanedPreparation = cleaned(proposal.preparation)
    let cleanedDescriptors = deduplicated(proposal.descriptors.compactMap(cleaned))
    let cleanedComponents = deduplicated(proposal.componentNames.compactMap(cleaned))
    var rejections: [SemanticFactRejection] = []

    if !proposal.containsMultipleFoods, !cleanedComponents.isEmpty {
      rejections.append(.inconsistentMultiplicity)
      return .init(grounded: nil, rejections: rejections)
    }

    let candidate = ParsedFoodRequest(
      brand: cleanedBrand,
      productName: cleanedProduct,
      preparation: cleanedPreparation,
      descriptors: cleanedDescriptors,
      containsMultipleFoods: proposal.containsMultipleFoods,
      componentNames: cleanedComponents
    )
    let groundedRequest = ParsedFoodRequestGrounder().ground(candidate, in: groundingText)

    if !cleanedProduct.isEmpty, groundedRequest.productName.isEmpty {
      rejections.append(.unsupportedProduct)
    } else if cleanedProduct.isEmpty, !proposal.containsMultipleFoods {
      rejections.append(.emptyProduct)
    }
    if cleanedBrand != nil, groundedRequest.brand == nil { rejections.append(.unsupportedBrand) }
    if cleanedPreparation != nil, groundedRequest.preparation == nil {
      rejections.append(.unsupportedPreparation)
    }
    if groundedRequest.descriptors.count < cleanedDescriptors.count {
      rejections.append(.unsupportedDescriptor)
    }
    if groundedRequest.componentNames.count < cleanedComponents.count {
      rejections.append(.unsupportedComponent)
    }

    let components = deduplicated(groundedRequest.componentNames)
    if proposal.containsMultipleFoods {
      guard groundedRequest.containsMultipleFoods, components.count >= 2 else {
        rejections.append(.insufficientComponents)
        return .init(grounded: nil, rejections: deduplicated(rejections))
      }
      return .init(
        grounded: .init(
          productName: "",
          brand: nil,
          preparation: nil,
          descriptors: [],
          containsMultipleFoods: true,
          componentNames: components
        ),
        rejections: deduplicated(rejections)
      )
    }

    guard !groundedRequest.productName.isEmpty else {
      return .init(grounded: nil, rejections: deduplicated(rejections))
    }
    return .init(
      grounded: .init(
        productName: groundedRequest.productName,
        brand: groundedRequest.brand,
        preparation: groundedRequest.preparation,
        descriptors: deduplicated(groundedRequest.descriptors),
        containsMultipleFoods: false,
        componentNames: []
      ),
      rejections: deduplicated(rejections)
    )
  }

  private func cleaned(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }

  private func deduplicated<T: Hashable>(_ values: [T]) -> [T] {
    var seen = Set<T>()
    return values.filter { seen.insert($0).inserted }
  }

  private func deduplicated(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter {
      seen.insert(
        $0.folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: Locale(identifier: "en_US_POSIX")
        )
      )
      .inserted
    }
  }
}
