import CoreTransferable
import JustLogItCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension LogView {
  // MARK: - Live assistant cards (no text fields)

  @ViewBuilder
  var clarificationAttachments: some View {
    if let question = model.activeQuestion {
      // Prompt is already in the transcript; only show tap-to-send *answers*, never
      // follow-up questions the model sometimes puts in clarificationSuggestions.
      let answers = Self.answerChips(from: question.suggestedAnswers)
      if !answers.isEmpty {
        assistantCard {
          VStack(alignment: .leading, spacing: 10) {
            Text("Quick picks")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("clarification-title")
            suggestionChips(
              answers,
              idPrefix: "clarification-suggestion"
            ) { model.chooseClarificationSuggestion($0) }
          }
        }
      } else {
        Text(question.prompt)
          .font(.caption)
          .foregroundStyle(.clear)
          .frame(height: 0)
          .accessibilityIdentifier("clarification-prompt")
          .accessibilityHidden(true)
      }
    }
  }

  /// Defensive UI filter (policy already strips most junk). Chips = sendable answers only.
  private static func answerChips(from suggestions: [String]) -> [String] {
    let noise: Set<String> = [
      "warm", "hot", "cold", "cooked", "raw", "yummy", "delicious", "tasty", "good", "great",
      "something", "food", "meal", "snack",
    ]
    return suggestions
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { chip in
        guard !chip.isEmpty, chip.count <= 48 else { return false }
        if chip.hasSuffix("?") { return false }
        if noise.contains(chip.lowercased()) { return false }
        let lower = chip.lowercased()
        if lower.hasPrefix("how ") || lower.hasPrefix("what ") || lower.hasPrefix("which ") {
          return false
        }
        return true
      }
  }

  @ViewBuilder
  var whenEatenAttachments: some View {
    assistantCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("When did you eat this?")
          .font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("when-eaten-title")
        suggestionChips(
          model.whenEatenSuggestionChips,
          idPrefix: "when-eaten-suggestion"
        ) { model.applyWhenEatenSuggestion($0) }
      }
    }
  }

  var quantityAttachments: some View {
    assistantCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("How much did you eat?")
          .font(.subheadline.weight(.semibold))

        if let details = model.details {
          VStack(alignment: .leading, spacing: 2) {
            Text(details.description)
              .font(.subheadline.weight(.medium))
            Text("USDA serving · \(details.householdServing ?? servingText(details))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if let message = model.message {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("status-message")
        }

        if let suggestions = model.activeQuestion?.suggestedAnswers, !suggestions.isEmpty {
          suggestionChips(suggestions, idPrefix: "quantity-suggestion") {
            model.chooseClarificationSuggestion($0)
          }
        }

        Text("Use the bar below — pick a unit and send.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  /// Units offered in the quantity dock (conversion uses USDA household + grams when needed).
  var quantityUnitChoices: [String] {
    var units = ["serving", "g", "cup", "tbsp", "tsp", "oz", "fl oz", "ml", "bowl"]
    if let household = model.details?.householdServing?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !household.isEmpty
    {
      // Prefer showing the USDA household label in the menu when useful.
      let lower = household.lowercased()
      if lower.contains("cup"), !units.contains("cup") { units.insert("cup", at: 2) }
    }
    return units
  }

  var resultPickerCard: some View {
    // Compact chat widget: filter on top, scrollable results — not in the dock.
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text("USDA matches")
              .font(.subheadline.weight(.semibold))
            if let component = model.activeCompositeComponent {
              Text(component)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 8)
          Text("\(displayedUSDAResults.count) of \(model.results.count)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("usda-result-count")
        }

        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          TextField("Filter or re-search USDA…", text: $usdaFilter)
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit(requeryUSDAFromFilter)
            .accessibilityIdentifier("manual-search")
          if !usdaFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
              requeryUSDAFromFilter()
            } label: {
              Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search USDA")
            .accessibilityIdentifier("search-usda-button")
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))

        if !usdaFilter.isEmpty, displayedUSDAResults.isEmpty {
          Text("No local matches. Tap search to query USDA.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(displayedUSDAResults) { result in
              Button {
                model.select(result)
              } label: {
                USDAResultRow(result: result)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("usda-result-\(result.fdcID)")
            }
          }
        }
        .frame(maxHeight: 220)
        .scrollIndicators(.visible)
      }
      .padding(12)
      .frame(maxWidth: 360, alignment: .leading)
      .background(ChatPalette.assistantFill, in: .rect(cornerRadius: 18))
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
      }
      Spacer(minLength: 28)
    }
  }

  func requeryUSDAFromFilter() {
    let q = usdaFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    model.manualSearchTerms = q
    usdaFilter = ""
    focusedField = nil
    searchManually()
  }

  var nutritionReviewCard: some View {
    assistantCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.compositeComponents.isEmpty ? "Here’s what I’ll log" : "Here’s the meal")
          .font(.subheadline.weight(.semibold))

        if !model.compositeComponents.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(model.compositeComponents.enumerated()), id: \.offset) { _, component in
              CompositeComponentNutritionView(component: component, showExtended: false)
            }
            Divider()
            Text("Meal total")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            MacroSummaryView(nutrients: model.nutrients)
          }
        } else if let details = model.details, let resolution = model.resolution {
          VStack(alignment: .leading, spacing: 4) {
            Text(details.description)
              .font(.headline)
            if let brand = details.brandOwner, !brand.isEmpty {
              Text(brand)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Label(resolution.displayText, systemImage: "scalemass")
              .font(.subheadline)
            if model.parsed?.isApproximate == true {
              Label("Approximate quantity", systemImage: "tilde")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          MacroSummaryView(nutrients: model.nutrients)
        }

        if let inference = model.consumedAtInference, inference.isClear {
          Label(inference.displayLabel, systemImage: "clock")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("review-consumed-at")
          Text(model.consumedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }

        if model.compositeComponents.isEmpty, let fdcID = model.details?.fdcID {
          Text("USDA FoodData Central · FDC \(fdcID)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        if let message = model.message {
          Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("status-message")
        }

        if model.compositeComponents.isEmpty {
          HStack(spacing: 16) {
            Button("Adjust amount") {
              model.adjustQuantity()
            }
            .accessibilityIdentifier("adjust-amount")
            Button("Choose a different food") {
              model.searchManually()
            }
          }
          .font(.subheadline)
        }
      }
    }
  }

  var confirmationCard: some View {
    assistantCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Confirm this log?")
          .font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("confirm-log-title")

        if !model.compositeComponents.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(model.compositeComponents.enumerated()), id: \.offset) { _, component in
              CompositeComponentNutritionView(component: component, showExtended: false)
            }
            Divider()
            Text("Meal total")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            MacroSummaryView(nutrients: model.nutrients)
            Label(
              model.consumedAt.formatted(date: .abbreviated, time: .shortened),
              systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("confirm-consumed-at")
          }
        } else if let details = model.details, let resolution = model.resolution {
          VStack(alignment: .leading, spacing: 4) {
            Text(details.description)
              .font(.headline)
            if let brand = details.brandOwner, !brand.isEmpty {
              Text(brand)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Label(resolution.displayText, systemImage: "scalemass")
              .font(.subheadline)
            Label(
              model.consumedAt.formatted(date: .abbreviated, time: .shortened),
              systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("confirm-consumed-at")
          }
          MacroSummaryView(nutrients: model.nutrients)
        }

        if let message = model.message {
          Label(message, systemImage: "info.circle.fill")
            .font(.caption)
            .foregroundStyle(message.contains("could not be saved") ? .red : .secondary)
            .accessibilityIdentifier("status-message")
        }
      }
    }
  }

  var completionCard: some View {
    assistantCard {
      VStack(alignment: .leading, spacing: 12) {
        Label("Logged", systemImage: "checkmark.circle.fill")
          .font(.headline)
          .foregroundStyle(.green)
        Text("Saved on this device.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if let message = model.message {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("status-message")
        }

        if model.lastSavedEntryID != nil || model.lastSavedRecognizedFoodID != nil {
          HStack(spacing: 8) {
            if let entryID = model.lastSavedEntryID {
              Button {
                onOpenEntry?(entryID)
              } label: {
                Label("Entry", systemImage: "list.bullet.rectangle")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .accessibilityIdentifier("open-log-entry")
            }
            if let foodID = model.lastSavedRecognizedFoodID {
              Button {
                onOpenFood?(foodID)
              } label: {
                Label("Food", systemImage: "fork.knife")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .accessibilityIdentifier("open-food")
            }
          }
        }
      }
    }
  }

  var recoveryCard: some View {
    // Message text already appears as an assistant bubble from `fail`.
    // This card is only recovery actions so we don't repeat the same line twice.
    assistantCard {
      VStack(alignment: .leading, spacing: 10) {
        Label(recoveryTitle, systemImage: "exclamationmark.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.orange)
          .accessibilityIdentifier("recovery-title")
        // Hidden a11y copy for UI tests that still look for status-message.
        Text(model.message ?? "Try simpler wording or enter nutrition manually.")
          .font(.caption)
          .foregroundStyle(.clear)
          .frame(height: 0)
          .accessibilityIdentifier("status-message")
          .accessibilityHidden(true)
        HStack(spacing: 12) {
          Button(recoveryActionTitle) { performRecoveryAction() }
            .font(.subheadline.weight(.medium))
          Button("Enter manually") {
            focusedField = nil
            model.showManualEntry = true
          }
          .font(.subheadline)
        }
      }
    }
  }

  var recoveryTitle: String {
    switch model.failureKind {
    case .interpretation: "Couldn’t read that"
    case .search: "Couldn’t reach USDA"
    case .noResults: "No matches"
    case .details: "Couldn’t load that food"
    case nil: "Something went wrong"
    }
  }

  var recoveryActionTitle: String {
    switch model.failureKind {
    case .interpretation, nil: "Edit message"
    case .search, .noResults: "Edit search"
    case .details: "Search again"
    }
  }

  func performRecoveryAction() {
    switch model.failureKind {
    case .interpretation, nil:
      model.cancel()
      focusedField = .composer
    case .search, .noResults:
      focusedField = .composer
    case .details:
      searchManually()
    }
  }

}
