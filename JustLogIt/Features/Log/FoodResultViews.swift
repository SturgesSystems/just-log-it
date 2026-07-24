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
      // Soft selection affordance — reads as a tappable choice, not just text.
      Image(systemName: "circle")
        .font(.body.weight(.medium))
        .foregroundStyle(Color.accentColor.opacity(0.55))
        .accessibilityHidden(true)

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
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
    }
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

  private let macroKeys: [NutrientKey] = [.protein, .carbohydrate, .totalFat]
  private let primaryKeys: [NutrientKey] = [.energy, .protein, .carbohydrate, .totalFat]

  var body: some View {
    let energy = nutrients.first(where: { $0.key == .energy })
    let macros = macroKeys.compactMap { key in nutrients.first(where: { $0.key == key }) }
    let remaining = nutrients.filter { !primaryKeys.contains($0.key) }

    VStack(alignment: .leading, spacing: 10) {
      if energy == nil, macros.isEmpty {
        Label("Nutrition unavailable", systemImage: "questionmark.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        // Calories lead; macros sit one tier below so energy is scannable first.
        if let energy {
          MacroValue(nutrient: energy, prominence: .hero)
        }

        if !macros.isEmpty {
          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 8),
              GridItem(.flexible(), spacing: 8),
              GridItem(.flexible(), spacing: 8),
            ],
            alignment: .leading,
            spacing: 8
          ) {
            ForEach(macros) { nutrient in
              MacroValue(nutrient: nutrient, prominence: .secondary)
            }
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
  enum Prominence {
    case hero
    case secondary
  }

  let nutrient: NutrientAmount
  var prominence: Prominence = .secondary

  var body: some View {
    VStack(alignment: .leading, spacing: prominence == .hero ? 4 : 2) {
      Text(nutrient.key.displayName)
        .font(prominence == .hero ? .caption.weight(.semibold) : .caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Text(nutrient.formattedAmount)
        .font(prominence == .hero ? .title3.weight(.bold) : .subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(prominence == .hero ? 12 : 8)
    .background(
      Color(.tertiarySystemFill),
      in: .rect(cornerRadius: prominence == .hero ? 12 : 10)
    )
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
