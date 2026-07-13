import Foundation

/// Normalizes free-text lookup keys so repeat logs can match prior USDA selections.
public enum FoodLookupSignature: Sendable {
  /// Lowercases, strips non-alphanumerics to spaces, collapses whitespace.
  public static func normalize(_ text: String) -> String {
    let mapped = text.precomposedStringWithCanonicalMapping
      .lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
      .joined()
    return
      mapped
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}

/// A previously confirmed USDA selection tied to a normalized lookup signature.
/// Never auto-applies nutrition; ranking may only boost the matching FDC ID.
public struct RememberedFoodSelection: Sendable, Equatable, Codable, Identifiable {
  public var id: String { "\(signature)|\(fdcID)" }
  public var signature: String
  public var fdcID: Int
  public var displayName: String
  public var brand: String?
  public var useCount: Int
  public var lastUsedAt: Date

  public init(
    signature: String,
    fdcID: Int,
    displayName: String,
    brand: String? = nil,
    useCount: Int = 1,
    lastUsedAt: Date = .now
  ) {
    self.signature = FoodLookupSignature.normalize(signature)
    self.fdcID = fdcID
    self.displayName = displayName
    self.brand = brand
    self.useCount = max(1, useCount)
    self.lastUsedAt = lastUsedAt
  }
}

/// Deterministic catalog of remembered selections. Pure domain — no persistence I/O.
public struct RememberedFoodCatalog: Sendable, Equatable, Codable {
  public private(set) var selections: [RememberedFoodSelection]

  public init(selections: [RememberedFoodSelection] = []) {
    self.selections = selections
  }

  /// Records or refreshes a confirmed selection for a lookup signature.
  public mutating func remember(
    query: String,
    fdcID: Int,
    displayName: String,
    brand: String? = nil,
    at date: Date = .now
  ) {
    guard fdcID > 0 else { return }
    let signature = FoodLookupSignature.normalize(query)
    guard !signature.isEmpty else { return }

    if let index = selections.firstIndex(where: { $0.signature == signature && $0.fdcID == fdcID })
    {
      selections[index].useCount += 1
      selections[index].lastUsedAt = date
      selections[index].displayName = displayName
      selections[index].brand = brand
    } else {
      selections.append(
        RememberedFoodSelection(
          signature: signature,
          fdcID: fdcID,
          displayName: displayName,
          brand: brand,
          useCount: 1,
          lastUsedAt: date
        )
      )
    }
  }

  /// FDC IDs previously confirmed for this exact normalized signature.
  public func preferredFdcIDs(forQuery query: String) -> Set<Int> {
    let signature = FoodLookupSignature.normalize(query)
    guard !signature.isEmpty else { return [] }
    return Set(selections.filter { $0.signature == signature }.map(\.fdcID))
  }

  /// Selections ordered by recency then use count for UI surfaces.
  public func rankedForDisplay(limit: Int = 50) -> [RememberedFoodSelection] {
    Array(
      selections.sorted {
        if $0.lastUsedAt != $1.lastUsedAt { return $0.lastUsedAt > $1.lastUsedAt }
        if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
      .prefix(max(0, limit))
    )
  }

  public mutating func remove(signature: String, fdcID: Int) {
    let normalized = FoodLookupSignature.normalize(signature)
    selections.removeAll { $0.signature == normalized && $0.fdcID == fdcID }
  }

  public mutating func removeAll() {
    selections.removeAll()
  }
}
