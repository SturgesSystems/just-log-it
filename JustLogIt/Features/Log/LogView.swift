import CoreTransferable
import JustLogItCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Chat-style food logging surface.
///
/// Layout contract:
/// - Transcript is a message list (user right, assistant left).
/// - All free-form typing happens in the bottom composer — never inside bubbles.
/// - Rich choices (USDA rows, chips, nutrition) appear as assistant cards in the stream.
struct LogView: View {
  private enum Field: Hashable {
    case composer
    case quantity
  }

  private enum ComposerMode: Equatable {
    case compose
    case reply
    case whenEaten
    case quantity
    case search
    case edit
    case busy
    /// Compact actions while picking a USDA match (filter lives in the card).
    case choosingActions
    case primaryAction(title: String, systemImage: String, id: String)
    case completed
    case hidden
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext
  @StateObject private var model = LogViewModel()
  @FocusState private var focusedField: Field?
  @State private var editingTurnID: UUID?
  @State private var editDraft = ""
  @State private var photoPickerItem: PhotosPickerItem?
  @State private var showPhotoLibraryPicker = false
  @State private var showCameraPicker = false
  /// Client-side typeahead filter over the current USDA page (composer stays visible).
  @State private var usdaFilter = ""
  /// Amount + unit for post-USDA quantity entry (dock).
  @State private var quantityAmountText = ""
  @State private var quantityUnit = "serving"

  var onOpenEntry: ((UUID) -> Void)?
  var onOpenFood: ((UUID) -> Void)?

  private let configuration = AppConfiguration.current
  private let scrollAnchor = "chat-bottom"
  private let examples = [
    "Two large scrambled eggs",
    "One cup cooked jasmine rice",
    "About half a 12-ounce bottle of Fairlife chocolate milk",
  ]

  // MARK: - Body

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          if model.stage == .idle && model.transcript.isEmpty && editingTurnID == nil {
            emptyState
              .padding(.top, 8)
          } else {
            transcriptMessages
            liveAssistantContent
          }
          Color.clear.frame(height: 8).id(scrollAnchor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      // Dismiss only when the user drags the transcript — never while typing.
      .scrollDismissesKeyboard(.interactively)
      .defaultScrollAnchor(.bottom)
      .onChange(of: model.stage) { _, stage in
        if stage != .choosing {
          usdaFilter = ""
        }
        if stage == .clarifying {
          quantityAmountText = ""
          quantityUnit = "serving"
        }
        // Do not force-focus here: re-asserting @FocusState while the field
        // is mounting (or mid-keystroke) drops characters and feels broken.
        scrollToBottomIfSafe(proxy)
      }
      .onChange(of: model.transcript.count) { _, _ in
        scrollToBottomIfSafe(proxy)
      }
      .onChange(of: model.message) { _, _ in
        scrollToBottomIfSafe(proxy)
      }
    }
    .background(ChatPalette.canvas.ignoresSafeArea())
    .navigationTitle("JustLogIt")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      composerBar
    }
    .sheet(isPresented: $model.showManualEntry) {
      ManualEntryView(onSaved: model.markManualSaved)
    }
    .photosPicker(
      isPresented: $showPhotoLibraryPicker,
      selection: $photoPickerItem,
      matching: .images,
      photoLibrary: .shared()
    )
    .onChange(of: photoPickerItem) { _, item in
      guard let item else { return }
      Task { await handlePhotoSelection(item) }
    }
    .fullScreenCover(isPresented: $showCameraPicker) {
      CameraImagePicker(
        onImageData: { data in
          showCameraPicker = false
          Task { await handlePhotoData(data) }
        },
        onCancel: { showCameraPicker = false }
      )
      .ignoresSafeArea()
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          startNewConversation()
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.body.weight(.semibold))
        }
        .accessibilityLabel("New conversation")
        .accessibilityHint("Clears the current log chat and starts over")
        .accessibilityIdentifier("new-conversation")
        .disabled(model.stage == .idle && model.transcript.isEmpty && editingTurnID == nil)
      }
    }
  }

  private func startNewConversation() {
    editingTurnID = nil
    editDraft = ""
    usdaFilter = ""
    photoPickerItem = nil
    focusedField = nil
    model.reset()
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
      proxy.scrollTo(scrollAnchor, anchor: .bottom)
    }
  }

  /// Programmatic scroll dismisses the keyboard when `.scrollDismissesKeyboard` is on.
  /// Skip auto-scroll while the user is typing so keystrokes aren't stolen.
  private func scrollToBottomIfSafe(_ proxy: ScrollViewProxy) {
    guard focusedField == nil else { return }
    Task { @MainActor in scrollToBottom(proxy) }
  }

  /// Results shown in the USDA widget: optional local typeahead filter.
  private var displayedUSDAResults: [FoodSearchResult] {
    let q = usdaFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return model.results }
    return model.results.filter { result in
      result.description.localizedCaseInsensitiveContains(q)
        || (result.brandName?.localizedCaseInsensitiveContains(q) == true)
        || (result.brandOwner?.localizedCaseInsensitiveContains(q) == true)
        || result.dataType.localizedCaseInsensitiveContains(q)
        || String(result.fdcID).contains(q)
    }
  }

  // MARK: - Transcript

  @ViewBuilder
  private var transcriptMessages: some View {
    ForEach(model.transcript) { turn in
      switch turn {
      case .user(let id, let text, let imageData):
        ChatUserBubble(
          text: text,
          imageData: imageData,
          isEditing: editingTurnID == id,
          onEdit: imageData == nil
            ? { beginEditing(id: id, text: text) }
            : nil
        )
      case .system(_, let text):
        ChatAssistantBubble(text: text)
      }
    }
  }

  @ViewBuilder
  private var liveAssistantContent: some View {
    switch model.stage {
    case .idle, .completed:
      EmptyView()
    case .parsing:
      ChatTypingBubble(label: "Thinking…", onStop: { model.cancel() })
    case .awaitingClarification:
      clarificationAttachments
    case .searching:
      ChatTypingBubble(label: "Thinking…", onStop: { model.cancel() })
    case .choosing:
      resultPickerCard
    case .loadingDetails:
      if let selection = model.selectedResult {
        assistantCard {
          FoodSelectionReceipt(result: selection)
        }
      }
      ChatTypingBubble(label: "Thinking…", onStop: { model.cancel() })
    case .clarifying:
      quantityAttachments
    case .reviewing:
      nutritionReviewCard
    case .whenEaten:
      whenEatenAttachments
    case .confirming:
      confirmationCard
    case .failed:
      recoveryCard
    }
  }

  // MARK: - Empty state

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("What did you eat?")
          .font(.title2.bold())
        Text("Chat like you would with a friend. I’ll find a USDA match and ask only when I need a detail.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if configuration.providerDescription == "Not configured" {
        Label("USDA matching isn’t configured — manual entry still works.", systemImage: "exclamationmark.triangle.fill")
          .font(.footnote)
          .foregroundStyle(.orange)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Try saying")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        ForEach(examples, id: \.self) { example in
          Button {
            model.input = example
            submitComposer()
          } label: {
            Text(example)
              .font(.subheadline)
              .multilineTextAlignment(.leading)
              .foregroundStyle(.primary)
              .padding(.horizontal, 14)
              .padding(.vertical, 12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(ChatPalette.assistantFill, in: .rect(cornerRadius: 16))
          }
          .buttonStyle(.plain)
          .accessibilityHint("Uses this example as your food description")
        }
      }

      Label("On-device chat · log stays on this iPhone", systemImage: "lock.shield")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 8)
  }

  // MARK: - Edit via composer (not in-bubble)

  private func beginEditing(id: UUID, text: String) {
    editingTurnID = id
    editDraft = text
    model.input = text
    focusedField = .composer
  }

  private func cancelEditing() {
    editingTurnID = nil
    editDraft = ""
    if model.stage == .idle {
      // keep whatever is in input
    }
    focusedField = nil
  }

  private func commitEdit() {
    guard let id = editingTurnID else { return }
    let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    editingTurnID = nil
    editDraft = ""
    focusedField = nil
    model.editUserMessage(id: id, newText: text)
  }

  // MARK: - Live assistant cards (no text fields)

  @ViewBuilder
  private var clarificationAttachments: some View {
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
  private var whenEatenAttachments: some View {
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

  private var quantityAttachments: some View {
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
  private var quantityUnitChoices: [String] {
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

  private var resultPickerCard: some View {
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

  private func requeryUSDAFromFilter() {
    let q = usdaFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    model.manualSearchTerms = q
    usdaFilter = ""
    focusedField = nil
    searchManually()
  }

  private var nutritionReviewCard: some View {
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
          Button("Choose a different food") {
            model.searchManually()
          }
          .font(.subheadline)
        }
      }
    }
  }

  private var confirmationCard: some View {
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

  private var completionCard: some View {
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

  private var recoveryCard: some View {
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

  private var recoveryTitle: String {
    switch model.failureKind {
    case .interpretation: "Couldn’t read that"
    case .search: "Couldn’t reach USDA"
    case .noResults: "No matches"
    case .details: "Couldn’t load that food"
    case nil: "Something went wrong"
    }
  }

  private var recoveryActionTitle: String {
    switch model.failureKind {
    case .interpretation, nil: "Edit message"
    case .search, .noResults: "Edit search"
    case .details: "Search again"
    }
  }

  private func performRecoveryAction() {
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

  // MARK: - Composer

  private var composerMode: ComposerMode {
    if editingTurnID != nil { return .edit }
    switch model.stage {
    case .idle:
      return .compose
    case .parsing, .searching, .loadingDetails:
      return .busy
    case .awaitingClarification:
      return .reply
    case .whenEaten:
      return .whenEaten
    case .clarifying:
      return .quantity
    case .failed:
      // Interpretation failures need another description; search failures need a USDA query.
      switch model.failureKind {
      case .search, .noResults:
        return .search
      case .interpretation, .details, nil:
        return .compose
      }
    case .reviewing:
      return .primaryAction(title: "Continue", systemImage: "arrow.right", id: "continue-from-review")
    case .confirming:
      return .primaryAction(title: "Confirm log", systemImage: "checkmark", id: "save-entry")
    case .completed:
      return .completed
    case .choosing:
      // Filter lives in the USDA card; dock is for session actions only.
      return .choosingActions
    }
  }

  @ViewBuilder
  private var composerBar: some View {
    // While thinking, stop lives on the bubble — no empty dock strip.
    if composerMode == .busy || composerMode == .hidden {
      EmptyView()
    } else {
      composerBarContent
    }
  }

  @ViewBuilder
  private var composerBarContent: some View {
    VStack(spacing: 0) {
      if model.stage == .completed {
        completionCard
          .padding(.horizontal, 14)
          .padding(.top, 8)
      }

      Divider()

      Group {
        switch composerMode {
        case .busy, .hidden:
          EmptyView()
        case .compose:
          standardComposer(
            text: $model.input,
            placeholder: "What did you eat?",
            accessibilityID: "food-description",
            showAccessories: true,
            sendEnabled: !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            sendAccessibilityID: "continue-button",
            onSend: submitComposer
          )
        case .reply:
          standardComposer(
            text: $model.clarificationAnswer,
            placeholder: "Reply…",
            accessibilityID: "clarification-answer",
            showAccessories: false,
            sendEnabled: model.canSubmitClarificationAnswer,
            sendAccessibilityID: "clarification-continue",
            onSend: {
              focusedField = nil
              model.submitClarificationAnswer()
            }
          )
        case .whenEaten:
          standardComposer(
            text: $model.whenEatenAnswer,
            placeholder: "e.g. 2 hours ago",
            accessibilityID: "when-eaten-answer",
            showAccessories: false,
            sendEnabled: true,
            sendAccessibilityID: "when-eaten-continue",
            onSend: {
              focusedField = nil
              model.submitWhenEaten()
            }
          )
        case .edit:
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Label("Editing message", systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Spacer()
              Button("Cancel") { cancelEditing() }
                .font(.caption.weight(.medium))
            }
            standardComposer(
              text: $editDraft,
              placeholder: "Edit your message",
              accessibilityID: "edit-user-message",
              showAccessories: false,
              sendEnabled: !editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sendAccessibilityID: "save-edit-user-message",
              onSend: commitEdit
            )
          }
        case .search:
          standardComposer(
            text: $model.manualSearchTerms,
            placeholder: "Search USDA…",
            accessibilityID: "manual-search",
            showAccessories: false,
            sendEnabled: !model.manualSearchTerms.trimmingCharacters(in: .whitespacesAndNewlines)
              .isEmpty,
            sendAccessibilityID: "search-usda-button",
            sendSystemImage: "magnifyingglass",
            onSend: searchManually
          )
        case .choosingActions:
          HStack(spacing: 10) {
            Button {
              startNewConversation()
            } label: {
              Label("Start over", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("usda-start-over")

            Button {
              focusedField = nil
              model.showManualEntry = true
            } label: {
              Label("Manual", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("manual-entry-button")

            Spacer(minLength: 0)
          }
        case .quantity:
          quantityComposer
        case .primaryAction(let title, let systemImage, let id):
          Button {
            focusedField = nil
            if model.stage == .reviewing {
              model.continueFromReview()
            } else if model.stage == .confirming {
              confirmLog()
            }
          } label: {
            Label(title, systemImage: systemImage)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .accessibilityIdentifier(id)
        case .completed:
          Button(action: model.reset) {
            Label("Log another food", systemImage: "plus")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .accessibilityIdentifier("log-another")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
    .background(.bar)
  }

  private func standardComposer(
    text: Binding<String>,
    placeholder: String,
    accessibilityID: String,
    showAccessories: Bool,
    sendEnabled: Bool,
    sendAccessibilityID: String,
    sendSystemImage: String = "arrow.up",
    onSend: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .bottom, spacing: 8) {
      if showAccessories {
        composerAccessories
      }

      TextField(placeholder, text: text, axis: .vertical)
        .lineLimit(1...5)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(ChatPalette.composerField, in: .rect(cornerRadius: 20))
        .focused($focusedField, equals: .composer)
        .submitLabel(.send)
        .onSubmit {
          if sendEnabled { onSend() }
        }
        .accessibilityIdentifier(accessibilityID)
        // Stable id so mode switches remount cleanly without mid-type focus thrash.
        .id(accessibilityID)

      Button(action: onSend) {
        Image(systemName: sendSystemImage)
          .font(.body.weight(.semibold))
          .frame(width: 34, height: 34)
      }
      .buttonStyle(.borderedProminent)
      .clipShape(Circle())
      .disabled(!sendEnabled)
      .accessibilityLabel("Send")
      .accessibilityIdentifier(sendAccessibilityID)
    }
  }

  private var composerAccessories: some View {
    Menu {
      Button("Enter nutrition manually", systemImage: "square.and.pencil") {
        focusedField = nil
        model.showManualEntry = true
      }
      .accessibilityIdentifier("manual-entry-button")

      if UIImagePickerController.isSourceTypeAvailable(.camera) {
        Button("Take photo", systemImage: "camera") {
          focusedField = nil
          showCameraPicker = true
        }
        .accessibilityIdentifier("take-photo-button")
      }

      Button("Choose photo", systemImage: "photo.on.rectangle") {
        focusedField = nil
        showPhotoLibraryPicker = true
      }
      .accessibilityIdentifier("photo-picker-button")
    } label: {
      Image(systemName: "plus")
        .font(.body.weight(.semibold))
        .frame(width: 34, height: 34)
    }
    .menuOrder(.fixed)
    .buttonStyle(.bordered)
    .clipShape(Circle())
    .accessibilityLabel("Add")
    .accessibilityHint("Manual entry, take photo, or choose photo")
    .accessibilityIdentifier("composer-plus-menu")
  }

  private var quantityAmountIsValid: Bool {
    let t = quantityAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    // Accept locale-friendly decimals without blocking send on empty unit menus.
    return Double(t.replacingOccurrences(of: ",", with: ".")) != nil
      || t.range(of: #"^\d+([.,]\d+)?$"#, options: .regularExpression) != nil
  }

  private var quantityComposer: some View {
    VStack(spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        TextField("Amount", text: $quantityAmountText)
          .keyboardType(.decimalPad)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .background(ChatPalette.composerField, in: .rect(cornerRadius: 18))
          .focused($focusedField, equals: .quantity)
          .accessibilityIdentifier("quantity-value")
          .id("quantity-value")

        Menu {
          ForEach(quantityUnitChoices, id: \.self) { unit in
            Button(unit) { quantityUnit = unit }
          }
        } label: {
          HStack(spacing: 4) {
            Text(quantityUnit)
              .font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption2.weight(.semibold))
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(ChatPalette.composerField, in: .rect(cornerRadius: 14))
        }
        .accessibilityLabel("Unit")
        .accessibilityIdentifier("quantity-unit")

        Button {
          focusedField = nil
          model.resolveQuantityEntry(amountText: quantityAmountText, unit: quantityUnit)
        } label: {
          Image(systemName: "arrow.up")
            .font(.body.weight(.semibold))
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(Circle())
        .disabled(!quantityAmountIsValid)
        .accessibilityLabel("Send amount")
        .accessibilityIdentifier("quantity-send")
      }

      HStack {
        Menu {
          Button("Choose a different food", systemImage: "arrow.uturn.backward") {
            model.searchManually()
          }
          Button("Enter nutrition manually", systemImage: "square.and.pencil") {
            model.showManualEntry = true
          }
        } label: {
          Label("Options", systemImage: "ellipsis.circle")
            .font(.caption)
        }
        Spacer()
        Text("Converts using USDA serving when needed")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
  }

  // MARK: - Shared bits

  private func assistantCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 0) {
      content()
        .padding(14)
        .frame(maxWidth: 340, alignment: .leading)
        .background(ChatPalette.assistantFill, in: .rect(cornerRadius: 18))
      Spacer(minLength: 36)
    }
  }

  private func suggestionChips(
    _ items: [String],
    idPrefix: String,
    action: @escaping (String) -> Void
  ) -> some View {
    FlowChips(items: items) { item in
      Button {
        focusedField = nil
        action(item)
      } label: {
        Text(item)
          .font(.subheadline)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(ChatPalette.chipFill, in: .capsule)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(idPrefix)
    }
  }

  private func submitComposer() {
    focusedField = nil
    model.submit()
  }

  private func handlePhotoSelection(_ item: PhotosPickerItem) async {
    focusedField = nil
    defer { photoPickerItem = nil }
    do {
      guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
        model.reportPhotoUnavailable(
          "That photo could not be loaded. Describe the food in text instead."
        )
        return
      }
      await handlePhotoData(data)
    } catch {
      model.reportPhotoUnavailable(
        "That photo could not be loaded. Describe the food in text or enter nutrition manually."
      )
    }
  }

  private func handlePhotoData(_ data: Data) async {
    focusedField = nil
    guard !data.isEmpty else {
      model.reportPhotoUnavailable(
        "That photo could not be loaded. Describe the food in text instead."
      )
      return
    }
    let caption = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
    await model.proposeFromImage(
      data: data,
      caption: caption.isEmpty ? nil : caption
    )
  }

  private func searchManually() {
    focusedField = nil
    model.searchManually()
  }

  private func confirmLog() {
    guard model.stage == .confirming else { return }
    do {
      let entry = try model.makeRecord()
      modelContext.insert(entry)
      let recognized = try RecognizedFoodRecord.upsert(from: entry, in: modelContext)
      entry.recognizedFoodID = recognized.id
      try modelContext.save()
      model.markSaved(entryID: entry.id, recognizedFoodID: recognized.id)
      Task {
        await HealthSyncCoordinator.syncIfEnabled(entry, modelContext: modelContext)
      }
    } catch {
      model.markSaveFailed()
    }
  }

  private func servingText(_ food: FoodDetails) -> String {
    guard let size = food.servingSize, let unit = food.servingSizeUnit else {
      return "Not provided"
    }
    return "\(size.formatted()) \(unit)"
  }
}

// MARK: - System camera (UIImagePickerController)

/// Thin wrapper around the system camera picker.
private struct CameraImagePicker: UIViewControllerRepresentable {
  var onImageData: (Data) -> Void
  var onCancel: () -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.cameraCaptureMode = .photo
    picker.allowsEditing = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onImageData: onImageData, onCancel: onCancel)
  }

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let onImageData: (Data) -> Void
    let onCancel: () -> Void

    init(onImageData: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
      self.onImageData = onImageData
      self.onCancel = onCancel
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
      if let data = image?.jpegData(compressionQuality: 0.9) {
        onImageData(data)
      } else {
        onCancel()
      }
    }
  }
}

// MARK: - Chat chrome

private enum ChatPalette {
  static var canvas: Color {
    Color(.systemGroupedBackground)
  }

  static var assistantFill: Color {
    Color(.secondarySystemGroupedBackground)
  }

  static var chipFill: Color {
    Color(.tertiarySystemFill)
  }

  static var composerField: Color {
    Color(.secondarySystemGroupedBackground)
  }
}

private struct ChatUserBubble: View {
  let text: String
  var imageData: Data? = nil
  var isEditing: Bool = false
  var onEdit: (() -> Void)?

  private var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var uiImage: UIImage? {
    guard let imageData else { return nil }
    return UIImage(data: imageData)
  }

  var body: some View {
    HStack {
      Spacer(minLength: 56)
      VStack(alignment: .trailing, spacing: 6) {
        if let uiImage {
          Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 220, maxHeight: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
        }

        if !trimmedText.isEmpty {
          Text(trimmedText)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              isEditing ? Color.accentColor.opacity(0.55) : Color.accentColor,
              in: ChatBubbleShape(isUser: true)
            )
        }
      }
      .contextMenu {
        if onEdit != nil {
          Button("Edit", systemImage: "pencil") { onEdit?() }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabelText)
    .accessibilityHint(onEdit == nil ? "" : "Edits this message and restarts from here")
    .accessibilityAction(named: "Edit") { onEdit?() }
  }

  private var accessibilityLabelText: String {
    if uiImage != nil {
      return trimmedText.isEmpty ? "You shared a photo" : "You shared a photo: \(trimmedText)"
    }
    return "You said, \(trimmedText)"
  }
}

private struct ChatAssistantBubble: View {
  let text: String

  var body: some View {
    HStack {
      Text(text)
        .font(.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ChatPalette.assistantFill, in: ChatBubbleShape(isUser: false))
        .frame(maxWidth: 320, alignment: .leading)
      Spacer(minLength: 56)
    }
    .accessibilityLabel(text)
  }
}

private struct ChatTypingBubble: View {
  let label: String
  var onStop: (() -> Void)?

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text(label)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(ChatPalette.assistantFill, in: ChatBubbleShape(isUser: false))

      if let onStop {
        Button(action: onStop) {
          Image(systemName: "stop.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
        .accessibilityIdentifier("cancel-operation")
      }

      Spacer(minLength: 40)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct ChatBubbleShape: Shape {
  var isUser: Bool

  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = 18
    let corners: UIRectCorner =
      isUser
      ? [.topLeft, .topRight, .bottomLeft]
      : [.topLeft, .topRight, .bottomRight]
    let path = UIBezierPath(
      roundedRect: rect,
      byRoundingCorners: corners,
      cornerRadii: CGSize(width: radius, height: radius)
    )
    return Path(path.cgPath)
  }
}

/// Simple wrapping chip row without external deps.
private struct FlowChips<Item: Hashable, Content: View>: View {
  let items: [Item]
  @ViewBuilder var content: (Item) -> Content

  var body: some View {
    // Vertical stack is more reliable than custom layout for a11y + tests.
    VStack(alignment: .leading, spacing: 8) {
      ForEach(items, id: \.self) { item in
        content(item)
      }
    }
  }
}

// MARK: - Shared result / nutrition subviews

private struct FoodSelectionReceipt: View {
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

private struct USDAResultRow: View {
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
  fileprivate var displayDescription: String {
    description == description.uppercased() ? description.localizedCapitalized : description
  }

  fileprivate var servingDescription: String? {
    if let householdServing, !householdServing.isEmpty { return householdServing }
    if let servingSize, let servingSizeUnit {
      return "\(servingSize.formatted()) \(servingSizeUnit)"
    }
    return nil
  }

  fileprivate var shortDataType: String {
    if dataType.localizedCaseInsensitiveContains("branded") { return "Branded" }
    if dataType.localizedCaseInsensitiveContains("survey") { return "Survey" }
    if dataType.localizedCaseInsensitiveContains("foundation") { return "Foundation food" }
    return dataType
  }
}

extension NutrientAmount {
  fileprivate var formattedAmount: String {
    "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
  }
}
