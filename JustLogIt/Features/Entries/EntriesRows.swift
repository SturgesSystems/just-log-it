import AppIntents
import JustLogItCore
import SwiftData
import SwiftUI

struct EntryRow: View {
  let entry: FoodLogEntryRecord

  private var carbs: Double? {
    entry.nutrients.first(where: { $0.key == .carbohydrate })?.amount
  }

  private var fat: Double? {
    entry.nutrients.first(where: { $0.key == .totalFat })?.amount
  }

  private var hasMacroChips: Bool {
    entry.protein != nil || carbs != nil || fat != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.displayName)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
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
              .font(.title3.weight(.semibold).monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text("cal")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
          }
          .accessibilityHidden(true)
        }
      }

      if hasMacroChips {
        HStack(spacing: 6) {
          if let protein = entry.protein {
            MacroChip(label: "P", value: protein)
          }
          if let carbs {
            MacroChip(label: "C", value: carbs)
          }
          if let fat {
            MacroChip(label: "F", value: fat)
          }
          Spacer(minLength: 0)
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          metadata
          Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: 4) { metadata }
      }

      Text(entry.consumedAt, format: .dateTime.hour().minute())
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowAccessibilityLabel)
    // On-screen App Entity awareness (Spike A). Not Spotlight-indexed.
    .appEntityIdentifier(
      EntityIdentifier(for: FoodLogEntryEntity.self, identifier: entry.id)
    )
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
    if let carbs {
      parts.append(
        "\(carbs.formatted(.number.precision(.fractionLength(0...1)))) g carbs"
      )
    }
    if let fat {
      parts.append(
        "\(fat.formatted(.number.precision(.fractionLength(0...1)))) g fat"
      )
    }
    parts.append(entry.source.rawValue)
    parts.append(entry.consumedAt.formatted(.dateTime.hour().minute()))
    return parts.joined(separator: ", ")
  }

  @ViewBuilder
  private var metadata: some View {
    Text(entry.quantityDisplay)
      .font(.caption)
      .foregroundStyle(.secondary)
    if entry.isCompositeEntry {
      CompositeBadge()
    }
    Text(entry.source.rawValue)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

struct RecognizedFoodRow: View {
  let food: RecognizedFoodRecord

  private var protein: Double? {
    food.nutrients?.first(where: { $0.key == .protein })?.amount
  }

  private var carbs: Double? {
    food.nutrients?.first(where: { $0.key == .carbohydrate })?.amount
  }

  private var fat: Double? {
    food.nutrients?.first(where: { $0.key == .totalFat })?.amount
  }

  private var calories: Double? {
    food.nutrients?.first(where: { $0.key == .energy })?.amount
  }

  private var hasMacroChips: Bool {
    protein != nil || carbs != nil || fat != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(food.displayName)
            .font(.body.weight(.semibold))
            .lineLimit(2)
          if let brand = food.brand, !brand.isEmpty {
            Text(brand)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 12)
        VStack(alignment: .trailing, spacing: 0) {
          if let calories {
            Text(calories.formatted(.number.precision(.fractionLength(0))))
              .font(.title3.weight(.semibold).monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text("cal")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
          } else {
            Text("×\(food.useCount)")
              .font(.subheadline.monospacedDigit().weight(.medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
        }
        .accessibilityHidden(true)
      }

      if hasMacroChips {
        HStack(spacing: 6) {
          if let protein {
            MacroChip(label: "P", value: protein)
          }
          if let carbs {
            MacroChip(label: "C", value: carbs)
          }
          if let fat {
            MacroChip(label: "F", value: fat)
          }
          Spacer(minLength: 0)
        }
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          foodMetadata
          Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: 4) { foodMetadata }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
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
    Text("Used \(food.useCount)× · \(food.lastUsedAt.formatted(.relative(presentation: .named)))")
  }

  private var accessibilityLabel: String {
    var parts = [food.displayName]
    if let brand = food.brand, !brand.isEmpty { parts.append(brand) }
    parts.append("Used \(food.useCount) times")
    if let calories {
      parts.append(
        "\(calories.formatted(.number.precision(.fractionLength(0)))) calories"
      )
    }
    if let protein {
      parts.append(
        "\(protein.formatted(.number.precision(.fractionLength(0...1)))) g protein"
      )
    }
    if let carbs {
      parts.append(
        "\(carbs.formatted(.number.precision(.fractionLength(0...1)))) g carbs"
      )
    }
    if let fat {
      parts.append(
        "\(fat.formatted(.number.precision(.fractionLength(0...1)))) g fat"
      )
    }
    if let hint = food.servingHint, !hint.isEmpty { parts.append(hint) }
    if let fdcID = food.fdcID { parts.append("FDC \(fdcID)") }
    return parts.joined(separator: ", ")
  }
}

// MARK: - Shared chips

struct MacroChip: View {
  let label: String
  let value: Double

  var body: some View {
    HStack(spacing: 3) {
      Text(label)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
      Text(formattedValue)
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color(.tertiarySystemFill), in: Capsule())
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label) \(formattedValue)")
  }

  private var formattedValue: String {
    "\(value.formatted(.number.precision(.fractionLength(0...1))))g"
  }
}

struct CompositeBadge: View {
  var body: some View {
    Label("Composite", systemImage: "square.stack.3d.up")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(Color.accentColor)
      .background(Color.accentColor.opacity(0.14), in: Capsule())
      .labelStyle(.titleAndIcon)
      .accessibilityLabel("Composite meal")
  }
}
