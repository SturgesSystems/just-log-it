import JustLogItCore
import SwiftUI

struct FoodSelectionReceipt: View {
  let result: FoodSearchResult

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(result.displayDescription)
          .font(.subheadline.weight(.semibold))
        if let brand = result.brandName ?? result.brandOwner, !brand.isEmpty {
          Text(brand)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Selected food, \(result.displayDescription)")
  }
}

struct USDAResultRow: View {
  let result: FoodSearchResult

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(result.displayDescription)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
        if let brand = result.brandName ?? result.brandOwner, !brand.isEmpty {
          Text(brand)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
          if let serving = result.servingDescription {
            Text(serving)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Text(result.shortDataType)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Selects this USDA food")
  }
}

/// One composite item: identity + amount + its own macros.
struct CompositeComponentNutritionView: View {
  let component: CompositeComponentSnapshot
  /// When false, only the four primary macros (no "More nutrients" disclosure).
  var showExtended: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(component.displayName)
          .font(.subheadline.weight(.semibold))
        if let brand = component.brand, !brand.isEmpty {
          Text(brand)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 6) {
          Text(component.quantityDisplay)
            .font(.caption)
            .foregroundStyle(.secondary)
          if component.isApproximate {
            Label("approx.", systemImage: "tilde")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .labelStyle(.titleAndIcon)
          }
        }
      }
      MacroSummaryView(nutrients: component.nutrients, showExtended: showExtended)
    }
    .accessibilityElement(children: .combine)
  }
}

struct MacroSummaryView: View {
  let nutrients: [NutrientAmount]
  var showExtended: Bool = true

  private let primaryKeys: [NutrientKey] = [.energy, .protein, .carbohydrate, .totalFat]

  var body: some View {
    let primary = primaryKeys.compactMap { key in nutrients.first(where: { $0.key == key }) }
    let remaining = nutrients.filter { !primaryKeys.contains($0.key) }

    VStack(alignment: .leading, spacing: 12) {
      if primary.isEmpty {
        Label("Nutrition unavailable", systemImage: "questionmark.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        HStack(alignment: .top, spacing: 8) {
          ForEach(primary) { nutrient in
            MacroValue(nutrient: nutrient)
              .frame(maxWidth: .infinity)
          }
        }
      }

      if showExtended, !remaining.isEmpty {
        DisclosureGroup("More nutrients") {
          NutrientSummaryView(nutrients: remaining)
            .padding(.top, 8)
        }
        .font(.caption)
      }
    }
  }
}

private struct MacroValue: View {
  let nutrient: NutrientAmount

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(nutrient.key.displayName)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(nutrient.formattedAmount)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}

struct NutrientSummaryView: View {
  let nutrients: [NutrientAmount]

  var body: some View {
    if nutrients.isEmpty {
      Label("Nutrition unavailable", systemImage: "questionmark.circle")
        .foregroundStyle(.secondary)
    } else {
      VStack(spacing: 12) {
        ForEach(nutrients) { nutrient in
          LabeledContent(nutrient.key.displayName, value: nutrient.formattedAmount)
            .accessibilityElement(children: .combine)
        }
      }
    }
  }
}

extension FoodSearchResult {
  var displayDescription: String {
    description == description.uppercased() ? description.localizedCapitalized : description
  }

  var servingDescription: String? {
    if let householdServing, !householdServing.isEmpty { return householdServing }
    if let servingSize, let servingSizeUnit {
      return "\(servingSize.formatted()) \(servingSizeUnit)"
    }
    return nil
  }

  var shortDataType: String {
    if dataType.localizedCaseInsensitiveContains("branded") { return "Branded" }
    if dataType.localizedCaseInsensitiveContains("survey") { return "Survey" }
    if dataType.localizedCaseInsensitiveContains("foundation") { return "Foundation food" }
    return dataType
  }
}

extension NutrientAmount {
  var formattedAmount: String {
    "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
  }
}
