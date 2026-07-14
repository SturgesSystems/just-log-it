import JustLogItCore
import SwiftData
import SwiftUI

struct EntryRow: View {
  let entry: FoodLogEntryRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.displayName)
            .font(.headline)
            .lineLimit(2)
          if let brand = entry.brand, !brand.isEmpty {
            Text(brand)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 12)
        if let calories = entry.calories {
          VStack(alignment: .trailing, spacing: 0) {
            Text(calories.formatted(.number.precision(.fractionLength(0))))
              .font(.headline.monospacedDigit())
            Text("cal")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          metadata
          Spacer()
        }
        VStack(alignment: .leading, spacing: 3) { metadata }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Text(entry.consumedAt, format: .dateTime.hour().minute())
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowAccessibilityLabel)
  }

  private var rowAccessibilityLabel: String {
    var parts = [entry.displayName]
    if let brand = entry.brand, !brand.isEmpty {
      parts.append(brand)
    }
    if let calories = entry.calories {
      parts.append(
        "\(calories.formatted(.number.precision(.fractionLength(0)))) calories"
      )
    }
    parts.append(entry.quantityDisplay)
    if entry.isCompositeEntry {
      parts.append("Composite meal")
    }
    if let protein = entry.protein {
      parts.append(
        "\(protein.formatted(.number.precision(.fractionLength(0...1)))) g protein"
      )
    }
    parts.append(entry.source.rawValue)
    parts.append(entry.consumedAt.formatted(.dateTime.hour().minute()))
    return parts.joined(separator: ", ")
  }

  @ViewBuilder
  private var metadata: some View {
    Text(entry.quantityDisplay)
    if entry.isCompositeEntry {
      Text("Composite")
    }
    if let protein = entry.protein {
      Text("\(protein.formatted(.number.precision(.fractionLength(0...1)))) g protein")
    }
    Text(entry.source.rawValue)
  }
}

struct RecognizedFoodRow: View {
  let food: RecognizedFoodRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(food.displayName)
          .font(.headline)
          .lineLimit(2)
        Spacer(minLength: 12)
        Text("×\(food.useCount)")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      if let brand = food.brand, !brand.isEmpty {
        Text(brand)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          foodMetadata
          Spacer()
        }
        VStack(alignment: .leading, spacing: 3) { foodMetadata }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var foodMetadata: some View {
    if let hint = food.servingHint, !hint.isEmpty {
      Text(hint)
    }
    if let fdcID = food.fdcID {
      Text("FDC \(fdcID)")
    }
    Text("Last used \(food.lastUsedAt.formatted(.relative(presentation: .named)))")
  }

  private var accessibilityLabel: String {
    var parts = [food.displayName]
    if let brand = food.brand, !brand.isEmpty { parts.append(brand) }
    parts.append("Used \(food.useCount) times")
    if let hint = food.servingHint, !hint.isEmpty { parts.append(hint) }
    if let fdcID = food.fdcID { parts.append("FDC \(fdcID)") }
    return parts.joined(separator: ", ")
  }
}
