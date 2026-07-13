import Foundation

/// Exact unit conversion within mass and within volume (US culinary).
///
/// Cross-dimension (cup → grams) is **not** invented here: that needs a food-specific
/// density. Callers use USDA `servingSize` grams + household volume as the bridge.
public enum UnitConversion: Sendable {
  public enum Dimension: Sendable, Equatable {
    case mass
    case volume
    case count
    case serving
    case unknown
  }

  /// Canonical family key for comparison/conversion (e.g. "g", "oz", "cup", "egg").
  public static func family(_ unit: String) -> String {
    let c = normalize(unit)
    switch c {
    case "g", "gram", "grams": return "g"
    case "mg", "milligram", "milligrams": return "mg"
    case "kg", "kilogram", "kilograms": return "kg"
    case "oz", "ounce", "ounces": return "oz"  // weight ounce
    case "lb", "lbs", "pound", "pounds": return "lb"
    // Fluid ounce — never treat as weight ounce.
    case "floz", "fl.oz", "fl.oz.", "fluidounce", "fluidounces":
      return "floz"
    case "ml", "milliliter", "milliliters", "millilitre", "millilitres": return "ml"
    case "l", "liter", "liters", "litre", "litres": return "l"
    case "tsp", "teaspoon", "teaspoons": return "tsp"
    case "tbsp", "tbs", "tablespoon", "tablespoons": return "tbsp"
    case "cup", "cups", "c": return "cup"
    case "pint", "pints", "pt": return "pint"
    case "quart", "quarts", "qt": return "quart"
    case "serving", "servings", "srv": return "serving"
    case "slice", "slices": return "slice"
    case "piece", "pieces", "pc", "pcs": return "piece"
    case "item", "items": return "item"
    case "each": return "each"
    case "burger", "burgers": return "burger"
    case "cookie", "cookies": return "cookie"
    case "egg", "eggs": return "egg"
    case "bar", "bars": return "bar"
    case "sandwich", "sandwiches": return "sandwich"
    case "bottle", "bottles": return "bottle"
    case "can", "cans": return "can"
    case "container", "containers": return "container"
    case "bun", "buns": return "bun"
    case "patty", "patties": return "patty"
    case "link", "links": return "link"
    case "nugget", "nuggets": return "nugget"
    case "wing", "wings": return "wing"
    case "thigh", "thighs": return "thigh"
    case "breast", "breasts": return "breast"
    case "tortilla", "tortillas": return "tortilla"
    case "wrap", "wraps": return "wrap"
    case "bowl", "bowls": return "bowl"
    case "tray", "trays": return "tray"
    case "large", "medium", "small", "jumbo": return c
    default:
      if c.hasSuffix("s"), c.count > 2 { return String(c.dropLast()) }
      return c
    }
  }

  public static func dimension(of unit: String) -> Dimension {
    switch family(unit) {
    case "g", "mg", "kg", "oz", "lb": return .mass
    case "ml", "l", "tsp", "tbsp", "cup", "pint", "quart", "floz": return .volume
    case "serving": return .serving
    case "slice", "piece", "item", "each", "burger", "cookie", "egg", "bar", "sandwich", "bottle",
      "can", "container", "bun", "patty", "link", "nugget", "wing", "thigh", "breast", "tortilla",
      "wrap", "bowl", "tray", "large", "medium", "small", "jumbo":
      return .count
    default: return .unknown
    }
  }

  public static func unitsCompatible(_ lhs: String, _ rhs: String) -> Bool {
    let a = family(lhs)
    let b = family(rhs)
    if a == b { return true }
    // Egg size words often appear as household unit ("1 large").
    let eggSizes: Set<String> = ["egg", "large", "medium", "small", "jumbo"]
    if eggSizes.contains(a) && eggSizes.contains(b) { return true }
    // Generic whole-item counts ("item", "each", "piece") match any other discrete count
    // when USDA household text uses a food-specific noun ("1 McDonald's Big Mac").
    let genericWhole: Set<String> = ["item", "each", "piece"]
    if genericWhole.contains(a) || genericWhole.contains(b) {
      if dimension(of: lhs) == .count && dimension(of: rhs) == .count { return true }
    }
    return false
  }

  /// Convert quantity into grams when `unit` is a mass unit.
  public static func toGrams(quantity: Double, unit: String) -> Double? {
    guard quantity.isFinite, quantity > 0 else { return nil }
    return switch family(unit) {
    case "g": quantity
    case "mg": quantity / 1_000
    case "kg": quantity * 1_000
    case "oz": quantity * 28.349_523_125
    case "lb": quantity * 453.592_37
    default: nil
    }
  }

  /// Convert quantity into milliliters when `unit` is a volume unit (US measures).
  public static func toMilliliters(quantity: Double, unit: String) -> Double? {
    guard quantity.isFinite, quantity > 0 else { return nil }
    return switch family(unit) {
    case "ml": quantity
    case "l": quantity * 1_000
    case "tsp": quantity * 4.928_921_593_75
    case "tbsp": quantity * 14.786_764_781_25
    case "floz": quantity * 29.573_529_562_5
    case "cup": quantity * 236.588_236_5
    case "pint": quantity * 473.176_473
    case "quart": quantity * 946.352_946
    default: nil
    }
  }

  /// Convert between two units of the **same** dimension (mass↔mass or volume↔volume).
  public static func convert(quantity: Double, from: String, to: String) -> Double? {
    guard quantity.isFinite, quantity > 0 else { return nil }
    let fromDim = dimension(of: from)
    let toDim = dimension(of: to)
    guard fromDim == toDim, fromDim == .mass || fromDim == .volume else { return nil }

    if fromDim == .mass {
      guard let grams = toGrams(quantity: quantity, unit: from) else { return nil }
      return fromGrams(grams, to: to)
    }

    guard let ml = toMilliliters(quantity: quantity, unit: from) else { return nil }
    return fromMilliliters(ml, to: to)
  }

  /// Scale factor: how many `to` units equal one `from` unit, same dimension only.
  public static func ratio(from: String, to: String) -> Double? {
    convert(quantity: 1, from: from, to: to)
  }

  // MARK: - Private

  private static func fromGrams(_ grams: Double, to unit: String) -> Double? {
    switch family(unit) {
    case "g": grams
    case "mg": grams * 1_000
    case "kg": grams / 1_000
    case "oz": grams / 28.349_523_125
    case "lb": grams / 453.592_37
    default: nil
    }
  }

  private static func fromMilliliters(_ ml: Double, to unit: String) -> Double? {
    switch family(unit) {
    case "ml": ml
    case "l": ml / 1_000
    case "tsp": ml / 4.928_921_593_75
    case "tbsp": ml / 14.786_764_781_25
    case "floz": ml / 29.573_529_562_5
    case "cup": ml / 236.588_236_5
    case "pint": ml / 473.176_473
    case "quart": ml / 946.352_946
    default: nil
    }
  }

  private static func normalize(_ unit: String) -> String {
    var s =
      unit.lowercased()
      .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    // "fl oz" / "fl. oz" → floz
    s = s.replacingOccurrences(of: " ", with: "")
    s = s.replacingOccurrences(of: "fluidounce", with: "floz")
    if s.hasPrefix("fl") && s.hasSuffix("oz") { return "floz" }
    return s
  }
}
