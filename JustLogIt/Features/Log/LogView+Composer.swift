import CoreTransferable
import JustLogItCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension LogView {
  // MARK: - Composer

  var composerMode: ComposerMode {
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
  var composerBar: some View {
    // While thinking, stop lives on the bubble — no empty dock strip.
    if composerMode == .busy || composerMode == .hidden {
      EmptyView()
    } else {
      composerBarContent
    }
  }

  @ViewBuilder
  var composerBarContent: some View {
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

  func standardComposer(
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

  var composerAccessories: some View {
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

  var quantityAmountIsValid: Bool {
    let t = quantityAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    // Accept locale-friendly decimals without blocking send on empty unit menus.
    return Double(t.replacingOccurrences(of: ",", with: ".")) != nil
      || t.range(of: #"^\d+([.,]\d+)?$"#, options: .regularExpression) != nil
  }

  var quantityComposer: some View {
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

  func assistantCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 0) {
      content()
        .padding(14)
        .frame(maxWidth: 340, alignment: .leading)
        .background(ChatPalette.assistantFill, in: .rect(cornerRadius: 18))
      Spacer(minLength: 36)
    }
  }

  func suggestionChips(
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

  func submitComposer() {
    focusedField = nil
    model.submit()
  }

  func handlePhotoSelection(_ item: PhotosPickerItem) async {
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

  func handlePhotoData(_ data: Data) async {
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

  func searchManually() {
    focusedField = nil
    model.searchManually()
  }

  func confirmLog() {
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

  func servingText(_ food: FoodDetails) -> String {
    guard let size = food.servingSize, let unit = food.servingSizeUnit else {
      return "Not provided"
    }
    return "\(size.formatted()) \(unit)"
  }
}
