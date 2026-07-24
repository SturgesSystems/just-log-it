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

        if let message = model.message {
          Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("when-eaten-error")
        }

        Divider()
        DatePicker(
          "Exact date and time",
          selection: $model.consumedAt,
          displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .accessibilityIdentifier("when-eaten-date-picker")

        Button("Use this date and time") {
          model.useSelectedWhenEatenDate()
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("use-when-eaten-date")
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
          .accessibilityElement(children: .combine)
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
            if let caption = model.compositePickerCaption {
              Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("composite-component-caption")
            }
          }
          Spacer(minLength: 8)
          Text("\(displayedUSDAResults.count) of \(model.results.count)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("usda-result-count")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          usdaPickerHeaderAccessibilityLabel
        )

        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
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
        .background(
          Color(.tertiarySystemFill),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )

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
      .padding(14)
      .frame(maxWidth: 360, alignment: .leading)
      .chatCardChrome()
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
            VStack(alignment: .leading, spacing: 2) {
              Text(details.description)
                .font(.headline)
              if let brand = details.brandOwner, !brand.isEmpty {
                Text(brand)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .accessibilityElement(children: .combine)
            Button {
              model.editAmountFromReview()
            } label: {
              HStack(spacing: 6) {
                Label(resolution.displayText, systemImage: "scalemass")
                Image(systemName: "pencil")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.tertiary)
                  .accessibilityHidden(true)
              }
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Amount, \(resolution.displayText). Tap to edit.")
            .accessibilityIdentifier("review-amount")
            if model.parsed?.isApproximate == true {
              Label("Approximate quantity", systemImage: "tilde")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          MacroSummaryView(nutrients: model.nutrients)
        }

        Button {
          model.editTimeFromReview()
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Label(reviewTimeLabel, systemImage: "clock")
              Image(systemName: "pencil")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(model.consumedAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "Time, \(reviewTimeLabel), \(model.consumedAt.formatted(date: .abbreviated, time: .shortened)). Tap to edit."
        )
        .accessibilityIdentifier("review-consumed-at")

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
              model.editAmountFromReview()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityIdentifier("adjust-amount")
            Button("Choose a different food") {
              model.searchManually()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          }
          .font(.subheadline)
        } else {
          Text("Meal amounts are set per item — tap the time to change when you ate.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
  }

  /// Label for the review time row (prefers inference wording, else formatted clock).
  var reviewTimeLabel: String {
    if let inference = model.consumedAtInference {
      let label = inference.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      if !label.isEmpty { return label }
    }
    return model.consumedAt.formatted(date: .omitted, time: .shortened)
  }

  var confirmationCard: some View {
    assistantCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Confirm this log?")
          .font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("confirm-log-title")

        if usesVolatileStore {
          Label(
            "This entry can’t be saved because local storage didn’t open. Your review is still here; relaunch after fixing storage.",
            systemImage: "externaldrive.badge.exclamationmark"
          )
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityIdentifier("volatile-confirmation-warning")
        }

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
            Button {
              model.editTimeFromReview()
            } label: {
              HStack(spacing: 6) {
                Label(
                  model.consumedAt.formatted(date: .abbreviated, time: .shortened),
                  systemImage: "clock"
                )
                Image(systemName: "pencil")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.tertiary)
                  .accessibilityHidden(true)
              }
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "Time, \(model.consumedAt.formatted(date: .abbreviated, time: .shortened)). Tap to edit."
            )
            .accessibilityIdentifier("confirm-consumed-at")
          }
        } else if let details = model.details, let resolution = model.resolution {
          VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
              Text(details.description)
                .font(.headline)
              if let brand = details.brandOwner, !brand.isEmpty {
                Text(brand)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .accessibilityElement(children: .combine)
            Button {
              model.editAmountFromReview()
            } label: {
              HStack(spacing: 6) {
                Label(resolution.displayText, systemImage: "scalemass")
                Image(systemName: "pencil")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.tertiary)
                  .accessibilityHidden(true)
              }
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Amount, \(resolution.displayText). Tap to edit.")
            .accessibilityIdentifier("confirm-amount")
            Button {
              model.editTimeFromReview()
            } label: {
              HStack(spacing: 6) {
                Label(
                  model.consumedAt.formatted(date: .abbreviated, time: .shortened),
                  systemImage: "clock"
                )
                Image(systemName: "pencil")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.tertiary)
                  .accessibilityHidden(true)
              }
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "Time, \(model.consumedAt.formatted(date: .abbreviated, time: .shortened)). Tap to edit."
            )
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
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 28))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.green)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text("Logged")
              .font(.headline)
            Text("Saved on this device.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Logged. Saved on this device.")

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
                Label("View entry", systemImage: "list.bullet.rectangle")
                  .lineLimit(1)
                  .minimumScaleFactor(0.8)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .controlSize(.regular)
              .accessibilityIdentifier("open-log-entry")
            }
            if let foodID = model.lastSavedRecognizedFoodID {
              Button {
                onOpenFood?(foodID)
              } label: {
                Label("View food", systemImage: "fork.knife")
                  .lineLimit(1)
                  .minimumScaleFactor(0.8)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .controlSize(.regular)
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
        if model.failureKind == .interpretation,
          !model.manualSearchTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          HStack(spacing: 10) {
            Button("Search USDA", systemImage: "magnifyingglass") {
              focusedField = nil
              model.searchManually()
            }
            .buttonStyle(.borderedProminent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityIdentifier("recovery-search-usda")

            Button("Edit message", systemImage: "pencil") {
              performRecoveryAction()
            }
            .buttonStyle(.bordered)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityIdentifier("recovery-edit-message")
          }
          .controlSize(.small)

          Button("Enter nutrition manually", systemImage: "square.and.pencil") {
            focusedField = nil
            model.showManualEntry = true
          }
          .font(.subheadline)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .accessibilityIdentifier("recovery-manual-entry")
        } else {
          // Airplane / offline / no-results: keep manual entry as a first-class CTA.
          VStack(alignment: .leading, spacing: 10) {
            Button(recoveryActionTitle) { performRecoveryAction() }
              .font(.subheadline.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .accessibilityIdentifier("recovery-primary-action")
            Button("Enter nutrition manually", systemImage: "square.and.pencil") {
              focusedField = nil
              model.showManualEntry = true
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityIdentifier("recovery-manual-entry")
            if recoveryOffersSettings {
              Button("Open Settings", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                  UIApplication.shared.open(url)
                }
              }
              .font(.subheadline.weight(.medium))
              .accessibilityIdentifier("recovery-open-settings")
            }
          }
        }

        // Preserve already-confirmed meal items when one component fails to match.
        if model.canSkipActiveCompositeComponent {
          Button {
            focusedField = nil
            model.skipActiveCompositeComponent()
          } label: {
            Label(compositeSkipTitle, systemImage: "forward.fill")
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
          .font(.subheadline)
          .accessibilityIdentifier("composite-skip-component")
        }
      }
    }
  }

  var usdaPickerHeaderAccessibilityLabel: String {
    var parts = ["USDA matches"]
    if let caption = model.compositePickerCaption {
      parts.append(caption)
    }
    parts.append("\(displayedUSDAResults.count) of \(model.results.count)")
    return parts.joined(separator: ", ")
  }

  var compositeSkipTitle: String {
    if model.compositeComponents.isEmpty {
      return model.pendingCompositeNames.isEmpty
        ? "Skip this item"
        : "Skip and continue meal"
    }
    if model.pendingCompositeNames.isEmpty {
      return "Skip and finish meal"
    }
    return "Skip and continue meal"
  }

  var recoveryTitle: String {
    if model.isBuildingComposite, model.activeCompositeComponent != nil {
      switch model.failureKind {
      case .search: return "Couldn’t look up that item"
      case .noResults: return "No match for this item"
      case .details: return "Couldn’t load that item"
      case .interpretation, nil: break
      }
    }
    switch model.failureKind {
    case .interpretation: return "Couldn’t read that"
    case .search: return "Couldn’t reach USDA"
    case .noResults: return "No matches"
    case .details: return "Couldn’t load that food"
    case nil: return "Something went wrong"
    }
  }

  /// Permission denials mention Settings so recovery can deep-link there.
  var recoveryOffersSettings: Bool {
    (model.message ?? "").localizedCaseInsensitiveContains("Settings")
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
      model.input = model.loggingSourceText
      model.cancel()
      focusedField = .composer
    case .search, .noResults:
      focusedField = .composer
    case .details:
      searchManually()
    }
  }

}
