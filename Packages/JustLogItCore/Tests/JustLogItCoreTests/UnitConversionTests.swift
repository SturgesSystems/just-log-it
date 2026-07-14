import Testing

@testable import JustLogItCore

@Test func unitFamilyNormalizesAliasesPluralsAndCase() {
  #expect(UnitConversion.family("Tablespoons") == "tbsp")
  #expect(UnitConversion.family("teaspoon") == "tsp")
  #expect(UnitConversion.family("EGGS") == "egg")
  #expect(UnitConversion.family("cups") == "cup")
  #expect(UnitConversion.family("fl. oz.") == "floz")
  // Weight ounce and fluid ounce must never collapse together.
  #expect(UnitConversion.family("oz") == "oz")
  #expect(UnitConversion.dimension(of: "oz") == .mass)
  #expect(UnitConversion.dimension(of: "floz") == .volume)
}

@Test func unitsCompatibleAcrossEggSizesAndGenericCounts() {
  // Egg-size household words are interchangeable with "egg".
  #expect(UnitConversion.unitsCompatible("egg", "large"))
  #expect(UnitConversion.unitsCompatible("large", "jumbo"))
  // A generic whole count matches any specific count noun.
  #expect(UnitConversion.unitsCompatible("item", "cookie"))
  #expect(UnitConversion.unitsCompatible("cookie", "each"))
  // Two *different specific* count nouns are not interchangeable.
  #expect(!UnitConversion.unitsCompatible("cookie", "burger"))
  // Cross-dimension is never compatible.
  #expect(!UnitConversion.unitsCompatible("g", "cup"))
  #expect(!UnitConversion.unitsCompatible("oz", "floz"))
  // Same family, different spelling/plurality is compatible.
  #expect(UnitConversion.unitsCompatible("cup", "cups"))
}

@Test func conversionsRejectNonPositiveAndNonFiniteInput() {
  #expect(UnitConversion.toGrams(quantity: 0, unit: "g") == nil)
  #expect(UnitConversion.toGrams(quantity: -5, unit: "oz") == nil)
  #expect(UnitConversion.toGrams(quantity: .nan, unit: "g") == nil)
  #expect(UnitConversion.toMilliliters(quantity: -1, unit: "cup") == nil)
  // Cross-dimension conversion is refused (no invented density).
  #expect(UnitConversion.convert(quantity: 1, from: "cup", to: "g") == nil)
  #expect(UnitConversion.toGrams(quantity: 1, unit: "cup") == nil)
}

@Test func volumeAndMassRoundTripAreConsistent() {
  // 1 cup → tbsp → cup returns to 1 within tolerance.
  let tbsp = UnitConversion.convert(quantity: 1, from: "cup", to: "tbsp")!
  let backToCup = UnitConversion.convert(quantity: tbsp, from: "tbsp", to: "cup")!
  #expect(abs(backToCup - 1) < 1e-9)
  // 1 lb ≈ 453.592 g.
  #expect(abs((UnitConversion.toGrams(quantity: 1, unit: "lb") ?? 0) - 453.592_37) < 1e-6)
}
