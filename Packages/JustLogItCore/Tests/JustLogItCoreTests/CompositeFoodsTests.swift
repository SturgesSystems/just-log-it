import Foundation
import Testing

@testable import JustLogItCore

@Test func nutrientAggregationSumsLikeKeysDeterministically() {
  let eggs = [
    NutrientAmount(key: .energy, amount: 148),
    NutrientAmount(key: .protein, amount: 10),
  ]
  let butter = [
    NutrientAmount(key: .energy, amount: 102),
    NutrientAmount(key: .totalFat, amount: 11.5),
  ]

  let total = NutrientAggregation.sum([eggs, butter])

  #expect(total.map(\.key) == [.energy, .protein, .totalFat])
  #expect(total.first(where: { $0.key == .energy })?.amount == 250)
  #expect(total.first(where: { $0.key == .protein })?.amount == 10)
  #expect(total.first(where: { $0.key == .totalFat })?.amount == 11.5)
}

@Test func nutrientAggregationOmitsMissingKeysRatherThanZeroing() {
  let onlyEnergy = [NutrientAmount(key: .energy, amount: 50)]
  let onlyProtein = [NutrientAmount(key: .protein, amount: 5)]

  let total = NutrientAggregation.sum([onlyEnergy, onlyProtein])

  #expect(total.map(\.key) == [.energy, .protein])
  #expect(total.contains(where: { $0.key == .carbohydrate }) == false)
}

@Test func nutrientAggregationDiscardsNonfiniteAndNegativeAmounts() {
  let dirty = [
    NutrientAmount(key: .energy, amount: 100),
    NutrientAmount(key: .protein, amount: -3),
    NutrientAmount(key: .carbohydrate, amount: .nan),
    NutrientAmount(key: .totalFat, amount: .infinity),
  ]
  let clean = [NutrientAmount(key: .energy, amount: 50)]

  let total = NutrientAggregation.sum([dirty, clean])

  #expect(total.map(\.key) == [.energy])
  #expect(total.first?.amount == 150)
}

@Test func nutrientAggregationEmptyInputYieldsEmptyResult() {
  #expect(NutrientAggregation.sum([]) == [])
  #expect(NutrientAggregation.sum([[], []]) == [])
}

@Test func compositeDraftBuilderAggregatesAndNames() {
  let components = [
    CompositeComponentSnapshot(
      displayName: "Eggs, scrambled",
      quantityDisplay: "2 large",
      nutrients: [
        NutrientAmount(key: .energy, amount: 180),
        NutrientAmount(key: .protein, amount: 12),
      ]
    ),
    CompositeComponentSnapshot(
      displayName: "Butter",
      brand: "Generic",
      fdcID: 1001,
      quantityDisplay: "1 tsp",
      nutrients: [NutrientAmount(key: .energy, amount: 34)],
      isApproximate: true
    ),
  ]

  let draft = CompositeDraftBuilder.make(components: components)

  #expect(draft.name == "Eggs, scrambled + Butter")
  #expect(draft.components.count == 2)
  #expect(draft.totalNutrients.first(where: { $0.key == .energy })?.amount == 214)
  #expect(draft.components[1].isApproximate)
}

@Test func compositeDraftBuilderUsesExplicitNameAndMultiFoodHelper() {
  let components = [
    CompositeComponentSnapshot(
      displayName: "Toast",
      quantityDisplay: "1 slice",
      nutrients: [NutrientAmount(key: .energy, amount: 80)]
    ),
    CompositeComponentSnapshot(
      displayName: "Jam",
      quantityDisplay: "1 tbsp",
      nutrients: [NutrientAmount(key: .energy, amount: 50)]
    ),
  ]

  let named = CompositeDraftBuilder.make(name: "Breakfast toast", components: components)
  #expect(named.name == "Breakfast toast")

  let fromSource = CompositeDraftBuilder.makeFromMultiFoodConfirmation(
    sourceText: "toast and jam",
    components: components
  )
  #expect(fromSource.name == "toast and jam")
  #expect(fromSource.totalNutrients.first(where: { $0.key == .energy })?.amount == 130)
}

@Test func compositeComponentSnapshotRoundTripsCodable() throws {
  let component = CompositeComponentSnapshot(
    displayName: "Oat milk",
    brand: "Oatly",
    fdcID: 42,
    quantityDisplay: "1 cup",
    nutrients: [NutrientAmount(key: .energy, amount: 120)],
    isApproximate: false
  )
  let data = try JSONEncoder().encode([component])
  let decoded = try JSONDecoder().decode([CompositeComponentSnapshot].self, from: data)
  #expect(decoded == [component])
}

@Test func compositeMatchingProgressReportsIndexAndTotal() {
  let first = CompositeMatchingProgress.position(confirmedCount: 0, remainingAfterActive: 1)
  #expect(first.index == 1)
  #expect(first.total == 2)

  let second = CompositeMatchingProgress.position(confirmedCount: 1, remainingAfterActive: 0)
  #expect(second.index == 2)
  #expect(second.total == 2)

  let only = CompositeMatchingProgress.position(confirmedCount: 0, remainingAfterActive: 0)
  #expect(only.index == 1)
  #expect(only.total == 1)
}

@Test func compositeMatchingProgressMessagesIncludeNameAndOrdinal() {
  #expect(
    CompositeMatchingProgress.searchingMessage(componentLabel: "fries", index: 2, total: 2)
      == "Matching fries (2 of 2)…"
  )
  #expect(
    CompositeMatchingProgress.queueTurn(componentLabel: "  large fries ", index: 2, total: 2)
      == "Matching large fries (2 of 2)."
  )
  #expect(
    CompositeMatchingProgress.pickerCaption(componentLabel: "fries", index: 2, total: 2)
      == "fries · 2 of 2"
  )
  #expect(
    CompositeMatchingProgress.searchingMessage(componentLabel: "eggs", index: 1, total: 1)
      == "Matching eggs…"
  )
}

@Test func compositeMatchingProgressFailureKeepsConfirmedItemsInCopy() {
  let withPrior = CompositeMatchingProgress.failureMessage(
    componentLabel: "fries",
    confirmedCount: 1,
    detail: "No USDA foods matched."
  )
  #expect(withPrior.contains("Couldn’t match fries."))
  #expect(withPrior.contains("No USDA foods matched."))
  #expect(withPrior.contains("1 other item remains in this meal"))
  #expect(withPrior.contains("skip this item"))

  let firstOnly = CompositeMatchingProgress.failureMessage(
    componentLabel: "eggs",
    confirmedCount: 0,
    detail: ""
  )
  #expect(firstOnly.contains("Couldn’t match eggs."))
  #expect(firstOnly.contains("Edit the search"))
  #expect(firstOnly.contains("skip this item"))
  #expect(!firstOnly.contains("other item"))
}
