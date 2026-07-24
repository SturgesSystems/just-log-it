import JustLogItCore
import SwiftData
import SwiftUI

/// A single local quick-start item for the Log empty state.
struct RecentFoodItem: Identifiable, Hashable, Sendable {
  let id: String
  let displayName: String
  let brand: String?

  /// Text inserted into the composer when tapped (food name only — does not auto-save).
  var composerText: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var chipLabel: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Horizontal row of recent local foods for the idle Log empty state.
/// Hidden entirely when `foods` is empty. Data must stay on-device.
struct RecentFoodsBar: View {
  let foods: [RecentFoodItem]
  let onSelect: (RecentFoodItem) -> Void

  var body: some View {
    if !foods.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("Recent foods")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
          .accessibilityAddTraits(.isHeader)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(foods) { food in
              Button {
                onSelect(food)
              } label: {
                Text(food.chipLabel)
                  .font(.subheadline)
                  .lineLimit(1)
                  .minimumScaleFactor(0.8)
                  .padding(.horizontal, 14)
                  .padding(.vertical, 10)
                  .background(ChatPalette.chipFill, in: Capsule())
                  .overlay {
                    Capsule()
                      .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(accessibilityLabel(for: food))
              .accessibilityHint("Starts a log with this food name. Review before saving.")
              .accessibilityIdentifier("recent-food-chip")
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("recent-foods-bar")
    }
  }

  private func accessibilityLabel(for food: RecentFoodItem) -> String {
    if let brand = food.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
      return "\(food.displayName), \(brand)"
    }
    return food.displayName
  }
}

// MARK: - Sourcing (local only)

enum RecentFoodsSource {
  /// Prefer confirmed `RecognizedFoodRecord` rows (SwiftData). If none, fall back to
  /// remembered USDA selections (`RememberedFoodStore`). Never invents foods or nutrition.
  static func items(
    recognized: [RecognizedFoodRecord],
    rememberedStore: any RememberedFoodStoring = UserDefaultsRememberedFoodStore(),
    limit: Int = 5
  ) -> [RecentFoodItem] {
    let capped = max(0, limit)
    guard capped > 0 else { return [] }

    let fromRecognized = recognized
      .prefix(capped)
      .compactMap { record -> RecentFoodItem? in
        let name = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return RecentFoodItem(
          id: "recognized-\(record.id.uuidString)",
          displayName: name,
          brand: record.brand
        )
      }

    if !fromRecognized.isEmpty {
      return Array(fromRecognized)
    }

    return rememberedStore.load()
      .rankedForDisplay(limit: capped)
      .compactMap { selection -> RecentFoodItem? in
        let name = selection.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return RecentFoodItem(
          id: "remembered-\(selection.id)",
          displayName: name,
          brand: selection.brand
        )
      }
  }
}
