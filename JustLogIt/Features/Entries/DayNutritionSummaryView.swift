import JustLogItCore
import SwiftUI

/// Attractive card summarizing today's logged nutrition from a `TodayNutritionSnapshot`.
struct DayNutritionSummaryView: View {
  let snapshot: TodayNutritionSnapshot
  /// True when at least one of today's entries carried a primary macro value.
  let hasAnyMacro: Bool

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// True when any protein/carbs/fat grams are present to visualize.
  private var hasMacroBreakdown: Bool {
    snapshot.proteinGrams > 0 || snapshot.carbohydrateGrams > 0 || snapshot.fatGrams > 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("Today")
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 8)
        Text(entryCountLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }

      if hasAnyMacro {
        HStack(alignment: .bottom, spacing: 0) {
          VStack(alignment: .leading, spacing: 2) {
            Text(formattedCalories)
              .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .accessibilityLabel("\(formattedCalories) calories")
            Text("cal")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }

          Spacer(minLength: 12)

          if hasMacroBreakdown {
            HStack(spacing: 8) {
              summaryMacro(label: "P", value: snapshot.proteinGrams, unit: "g", tint: MacroBarColor.protein)
              summaryMacro(label: "C", value: snapshot.carbohydrateGrams, unit: "g", tint: MacroBarColor.carbs)
              summaryMacro(label: "F", value: snapshot.fatGrams, unit: "g", tint: MacroBarColor.fat)
            }
          }
        }

        if hasMacroBreakdown {
          MacroProportionBar(
            protein: snapshot.proteinGrams,
            carbs: snapshot.carbohydrateGrams,
            fat: snapshot.fatGrams
          )
        }
      } else {
        Label("Nutrition not available for today’s entries", systemImage: "chart.bar.doc.horizontal")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            // Primary at 6% nearly vanishes on dark surfaces; lift slightly in dark.
            .strokeBorder(
              Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06),
              lineWidth: 1
            )
        }
        .shadow(
          color: cardShadowColor,
          radius: reduceMotion ? 0 : (colorScheme == .dark ? 10 : 8),
          y: reduceMotion ? 0 : (colorScheme == .dark ? 4 : 2)
        )
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today-nutrition-summary")
    .accessibilityLabel(accessibilityLabel)
  }

  private var cardShadowColor: Color {
    if reduceMotion { return .clear }
    return colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.04)
  }

  private var entryCountLabel: String {
    snapshot.entryCount == 1 ? "1 entry" : "\(snapshot.entryCount) entries"
  }

  private var formattedCalories: String {
    snapshot.calories.formatted(.number.precision(.fractionLength(0)))
  }

  private var accessibilityLabel: String {
    guard hasAnyMacro else {
      return "Today’s nutrition, \(entryCountLabel), nutrition not available"
    }
    var parts = [
      "Today’s nutrition, \(entryCountLabel)",
      "\(formattedCalories) calories",
    ]
    if hasMacroBreakdown {
      parts.append(contentsOf: [
        "\(formatMacro(snapshot.proteinGrams)) grams protein",
        "\(formatMacro(snapshot.carbohydrateGrams)) grams carbs",
        "\(formatMacro(snapshot.fatGrams)) grams fat",
      ])
    }
    return parts.joined(separator: ", ")
  }

  private func summaryMacro(label: String, value: Double, unit: String, tint: Color) -> some View {
    VStack(spacing: 3) {
      HStack(spacing: 4) {
        Circle()
          .fill(tint)
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
        Text(label)
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
      }
      Text("\(formatMacro(value))\(unit)")
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(minWidth: 44)
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
  }

  private func formatMacro(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }
}

/// Shared tints for P/C/F chips and the proportion bar.
private enum MacroBarColor {
  static let protein = Color.blue
  static let carbs = Color.orange
  static let fat = Color.purple
}

/// Horizontal segmented bar of protein / carbs / fat by gram share (pure SwiftUI).
private struct MacroProportionBar: View {
  let protein: Double
  let carbs: Double
  let fat: Double

  private var total: Double { max(protein + carbs + fat, 0) }

  private var segments: [(grams: Double, color: Color)] {
    [
      (protein, MacroBarColor.protein),
      (carbs, MacroBarColor.carbs),
      (fat, MacroBarColor.fat),
    ].filter { $0.grams > 0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geo in
        let spacing: CGFloat = 2
        let count = segments.count
        let available = max(geo.size.width - spacing * CGFloat(max(count - 1, 0)), 0)
        HStack(spacing: spacing) {
          ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            let fraction = total > 0 ? segment.grams / total : 0
            Capsule()
              .fill(segment.color.gradient)
              .frame(width: available * fraction)
          }
        }
      }
      .frame(height: 8)
      .clipShape(Capsule())
      .accessibilityHidden(true)

      HStack(spacing: 12) {
        legend(color: MacroBarColor.protein, label: "Protein")
        legend(color: MacroBarColor.carbs, label: "Carbs")
        legend(color: MacroBarColor.fat, label: "Fat")
        Spacer(minLength: 0)
      }
    }
  }

  private func legend(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
      Capsule()
        .fill(color)
        .frame(width: 10, height: 4)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .accessibilityHidden(true)
  }
}

/// Compact strip when the log list has history but nothing logged today.
struct DayNutritionEmptyStrip: View {
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "sun.max")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("No meals logged today")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.tertiarySystemFill))
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today-nutrition-summary")
    .accessibilityLabel("No meals logged today")
  }
}
