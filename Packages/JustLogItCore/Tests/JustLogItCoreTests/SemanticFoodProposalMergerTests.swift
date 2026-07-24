import Testing

@testable import JustLogItCore

private let proposalMerger = SemanticFoodProposalMerger()

@Test func deterministicRequestCarriesOnlyExtractedFacts() throws {
  let evidence = FoodTextEvidenceExtractor().extract(from: "two large scrambled eggs")
  let request = try #require(proposalMerger.deterministicRequest(from: evidence))

  #expect(request.productName == "large scrambled eggs")
  #expect(request.searchTerms == request.productName)
  #expect(request.quantity == 2)
  #expect(UnitConversion.family(request.unit ?? "") == "egg")
  #expect(request.preparation == "scrambled")
  #expect(request.descriptors == ["large"])
  #expect(request.clarificationPrompt == nil)
}

@Test func mergeCannotReplaceExplicitQuantityPreparationOrSize() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "two large scrambled eggs")
  let proposal = SemanticFoodProposal(
    productName: "eggs",
    preparation: "fried",
    descriptors: ["small"]
  )

  let request = proposalMerger.merge(proposal, with: evidence)

  #expect(request.productName == "eggs")
  #expect(request.quantity == 2)
  #expect(UnitConversion.family(request.unit ?? "") == "egg")
  #expect(request.preparation == "scrambled")
  #expect(request.descriptors == ["large"])
}

@Test func mergeCannotReplaceSyntaxDeclaredBrand() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "Oreo brand cookies")
  let grounded = GroundedSemanticFoodProposal(
    productName: "cookies",
    brand: "Hostess",
    preparation: nil,
    descriptors: [],
    containsMultipleFoods: false,
    componentNames: []
  )

  let request = proposalMerger.merge(grounded, with: evidence)

  #expect(request.brand == "Oreo")
  #expect(request.productName == "cookies")
}

@Test func hallucinatedIdentityBrandAndDescriptorsAreRejected() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "one Oreo cookie")
  let proposal = SemanticFoodProposal(
    productName: "chocolate cake",
    brand: "Hostess",
    preparation: "baked",
    descriptors: ["family size"]
  )

  let request = proposalMerger.merge(proposal, with: evidence)

  #expect(request.productName.isEmpty)
  #expect(request.searchTerms.isEmpty)
  #expect(request.brand == nil)
  #expect(request.preparation == nil)
  #expect(request.descriptors.isEmpty)
  #expect(request.quantity == 1)
}

@Test func staleContextProposalIsRejectedAgainstCurrentSource() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "one banana")
  let proposal = SemanticFoodProposal(productName: "pepperoni pizza")

  let request = proposalMerger.merge(proposal, with: evidence)

  #expect(request.productName.isEmpty)
  #expect(request.quantity == 1)
  #expect(UnitConversion.family(request.unit ?? "") == "banana")
}

@Test func groundedCompositeKeepsOnlySourceComponents() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "cereal with milk")
  let proposal = SemanticFoodProposal(
    productName: "breakfast",
    containsMultipleFoods: true,
    componentNames: ["cereal", "milk", "banana"]
  )

  let request = proposalMerger.merge(proposal, with: evidence)

  #expect(request.productName.isEmpty)
  #expect(request.containsMultipleFoods)
  #expect(request.componentNames == ["cereal", "milk"])
}

@Test func unsupportedCompositeClaimCollapsesSafely() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "apple")
  let proposal = SemanticFoodProposal(
    productName: "apple",
    containsMultipleFoods: true,
    componentNames: ["apple", "peanut butter"]
  )

  let request = proposalMerger.merge(proposal, with: evidence)

  #expect(request.productName.isEmpty)
  #expect(!request.containsMultipleFoods)
  #expect(request.componentNames.isEmpty)
}

@Test func emptySemanticProposalDoesNotPromoteExtractorGuess() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "the other half of that burrito bowl")

  let request = proposalMerger.merge(.init(productName: ""), with: evidence)

  #expect(request.productName.isEmpty)
  #expect(request.searchTerms.isEmpty)
}

@Test func semanticProposalCannotAuthorSearchOrClarificationText() {
  let proposal = SemanticFoodProposal(productName: "apple")
  let evidence = FoodTextEvidenceExtractor().extract(from: "apple")

  let request = proposalMerger.merge(proposal, with: evidence)

  #expect(request.searchTerms == "apple")
  #expect(request.clarificationPrompt == nil)
  #expect(request.clarificationSuggestions.isEmpty)
  #expect(!request.quantityNeedsClarification)
  #expect(!request.preparationNeedsClarification)
}

@Test func modelConfirmedSingleDishWithConjunctionIsNotResplitAsComposite() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "mac and cheese")
  let request = proposalMerger.merge(
    .init(productName: "mac and cheese", containsMultipleFoods: false),
    with: evidence
  )
  let draft = FoodInterpretationValidator().draft(
    from: request,
    sourceText: "mac and cheese"
  )

  #expect(request.multipleFoodAssessment == .single)
  guard case .proceed(let proceeded) = ClarificationPolicy().decide(draft) else {
    Issue.record("A confirmed single named dish must not become a component workflow")
    return
  }
  #expect(proceeded.productName == "mac and cheese")
  #expect(!proceeded.containsMultipleFoods)
}

@Test func trueCompositeNeverCarriesAComponentAmountAsWholeMealAmount() {
  let evidence = FoodTextEvidenceExtractor().extract(from: "two eggs and a slice of toast")
  let request = proposalMerger.merge(
    .init(
      productName: "",
      containsMultipleFoods: true,
      componentNames: ["two eggs", "a slice of toast"]
    ),
    with: evidence
  )

  #expect(request.containsMultipleFoods)
  #expect(request.componentNames == ["two eggs", "a slice of toast"])
  #expect(request.quantity == nil)
  #expect(request.unit == nil)
  #expect(request.quantityText == nil)
  #expect(request.fractionOfWhole == nil)
  #expect(request.containerSize == nil)
}

@Test func semanticGrounderRejectsStructurallyInconsistentMultiplicity() {
  let grounder = SemanticFoodProposalGrounder()

  let singleWithComponents = grounder.ground(
    .init(
      productName: "eggs and toast",
      containsMultipleFoods: false,
      componentNames: ["eggs", "toast"]
    ),
    against: "eggs and toast"
  )
  #expect(singleWithComponents.grounded == nil)
  #expect(singleWithComponents.rejections == [.inconsistentMultiplicity])

  let multipleWithOneComponent = grounder.ground(
    .init(productName: "", containsMultipleFoods: true, componentNames: ["eggs"]),
    against: "eggs and toast"
  )
  #expect(multipleWithOneComponent.grounded == nil)
  #expect(multipleWithOneComponent.rejections.contains(.insufficientComponents))
}

@Test func semanticGrounderDeduplicatesComponentsCaseInsensitively() throws {
  let result = SemanticFoodProposalGrounder().ground(
    .init(
      productName: "",
      containsMultipleFoods: true,
      componentNames: ["Eggs", "eggs", "toast", "Toast"]
    ),
    against: "Eggs and toast"
  )

  let grounded = try #require(result.grounded)
  #expect(grounded.componentNames == ["Eggs", "toast"])
  #expect(result.rejections.isEmpty)
}
