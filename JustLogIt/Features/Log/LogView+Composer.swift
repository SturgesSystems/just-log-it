import AVFoundation
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
      // Filled checkmark matches the post-save completion card and reads as the commit step.
      return .primaryAction(title: "Confirm log", systemImage: "checkmark.circle.fill", id: "save-entry")
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
            onSend: submitComposer,
            supportsVoiceInput: true
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
              pulseSendHaptic()
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
            onSend: submitWhenEatenComposer
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("usda-start-over")

            Button {
              focusedField = nil
              model.showManualEntry = true
            } label: {
              Label("Manual", systemImage: "square.and.pencil")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("manual-entry-button")

            Spacer(minLength: 0)
          }
        case .quantity:
          quantityComposer
        case .primaryAction(let title, let systemImage, let id):
          let isConfirmCommit = model.stage == .confirming
          Button {
            focusedField = nil
            if model.stage == .reviewing {
              pulseSendHaptic()
              model.continueFromReview()
            } else if isConfirmCommit {
              pulseSendHaptic()
              confirmLog()
            }
          } label: {
            Label(title, systemImage: systemImage)
              // Confirm is the only commit control in the dock — heavier type + height.
              .font(isConfirmCommit ? .headline : .body.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
              .padding(.vertical, isConfirmCommit ? 10 : 4)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          // Confirm is the commit step — success tint so it reads as final, not just "next".
          .tint(isConfirmCommit ? Color.green : Color.accentColor)
          .disabled(usesVolatileStore && isConfirmCommit)
          .accessibilityIdentifier(id)
          .accessibilityHint(
            isConfirmCommit
              ? "Saves this food log on this device"
              : "Continues to final confirmation"
          )
        case .completed:
          Button(action: model.reset) {
            Label("Log another food", systemImage: "plus")
              .font(.body.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 4)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(.green)
          .accessibilityIdentifier("log-another")
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 12)
    }
    .background {
      Rectangle()
        .fill(.ultraThinMaterial)
        .overlay(alignment: .top) {
          Rectangle()
            .fill(ChatPalette.hairline)
            .frame(height: 0.5)
        }
        .ignoresSafeArea(edges: .bottom)
    }
  }

  func standardComposer(
    text: Binding<String>,
    placeholder: String,
    accessibilityID: String,
    showAccessories: Bool,
    sendEnabled: Bool,
    sendAccessibilityID: String,
    sendSystemImage: String = "arrow.up",
    onSend: @escaping () -> Void,
    supportsVoiceInput: Bool = false
  ) -> some View {
    HStack(alignment: .bottom, spacing: 10) {
      if showAccessories {
        composerAccessories
      }

      TextField(placeholder, text: text, axis: .vertical)
        .lineLimit(1...5)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
          ChatPalette.composerField,
          in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
        }
        .focused($focusedField, equals: .composer)
        .submitLabel(.send)
        .onSubmit {
          // Return must not submit underneath a live voice session either.
          if sendEnabled && !(supportsVoiceInput && voiceInput.state.hasActiveSession) {
            onSend()
          }
        }
        .accessibilityIdentifier(accessibilityID)
        // Stable id so mode switches remount cleanly without mid-type focus thrash.
        .id(accessibilityID)

      let trimmedTextIsEmpty = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      let voiceSessionIsActive = supportsVoiceInput && voiceInput.state.hasActiveSession
      let showsMicrophone = supportsVoiceInput && trimmedTextIsEmpty && !voiceSessionIsActive
      Button {
        if voiceSessionIsActive {
          voiceInput.stop()
        } else if showsMicrophone {
          focusedField = nil
          voiceInput.start()
        } else {
          onSend()
        }
      } label: {
        Image(systemName: voiceSessionIsActive ? "stop.fill" : (showsMicrophone ? "mic.fill" : sendSystemImage))
          .font(.body.weight(.semibold))
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.borderedProminent)
      .clipShape(Circle())
      .tint(voiceSessionIsActive ? .red : .accentColor)
      .disabled(!sendEnabled && !showsMicrophone && !voiceSessionIsActive)
      .accessibilityLabel(voiceSessionIsActive ? "Stop listening" : (showsMicrophone ? "Speak food description" : "Send"))
      .accessibilityHint(showsMicrophone ? "Transcribes speech on this device without submitting it" : "")
      .accessibilityIdentifier(voiceSessionIsActive ? "stop-voice-input" : (showsMicrophone ? "start-voice-input" : sendAccessibilityID))
    }
  }

  var isPhotoInputBusy: Bool {
    photoSelectionCoordinator.isLoading
      || model.stage == .parsing
      || model.stage == .searching
      || model.stage == .loadingDetails
  }

  var composerAccessories: some View {
    Menu {
      Button("Enter nutrition manually", systemImage: "square.and.pencil") {
        focusedField = nil
        model.showManualEntry = true
      }
      .accessibilityIdentifier("manual-entry-button")

      Section {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
          Button("Take photo", systemImage: "camera") {
            focusedField = nil
            presentCameraPicker()
          }
          .disabled(isPhotoInputBusy)
          .accessibilityIdentifier("take-photo-button")
        }

        Button("Choose photo", systemImage: "photo.on.rectangle") {
          focusedField = nil
          showPhotoLibraryPicker = true
        }
        .disabled(isPhotoInputBusy)
        .accessibilityIdentifier("photo-picker-button")
      } header: {
        Text("On-device only — never uploaded")
      }
    } label: {
      Image(systemName: "plus")
        .font(.body.weight(.semibold))
        .frame(width: 40, height: 40)
    }
    .menuOrder(.fixed)
    .buttonStyle(.bordered)
    .clipShape(Circle())
    .disabled(isPhotoInputBusy)
    .accessibilityLabel("Add")
    .accessibilityHint(
      isPhotoInputBusy
        ? "Photo input is busy"
        : "Manual entry, take photo, or choose photo. On-device only — never uploaded."
    )
    .accessibilityIdentifier("composer-plus-menu")
  }

  /// Requests camera access just-in-time, with a clear denial path into Settings.
  func presentCameraPicker() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      showCameraPicker = true
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        Task { @MainActor in
          if granted {
            showCameraPicker = true
          } else {
            model.reportPhotoUnavailable(Self.cameraPermissionDeniedMessage)
          }
        }
      }
    case .denied, .restricted:
      model.reportPhotoUnavailable(Self.cameraPermissionDeniedMessage)
    @unknown default:
      showCameraPicker = true
    }
  }

  static let cameraPermissionDeniedMessage =
    "Camera access is off. Enable Camera for JustLogIt in Settings, or describe the food in text."

  var quantityAmountIsValid: Bool {
    let t = quantityAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    // Accept locale-friendly decimals without blocking send on empty unit menus.
    return Double(t.replacingOccurrences(of: ",", with: ".")) != nil
      || t.range(of: #"^\d+([.,]\d+)?$"#, options: .regularExpression) != nil
  }

  var quantityComposer: some View {
    VStack(spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        TextField("Amount", text: $quantityAmountText)
          .keyboardType(.decimalPad)
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .background(
            ChatPalette.composerField,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
          }
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
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption2.weight(.semibold))
              .accessibilityHidden(true)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .background(
            ChatPalette.composerField,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
          }
        }
        .accessibilityLabel("Unit")
        .accessibilityValue(quantityUnit)
        .accessibilityIdentifier("quantity-unit")

        Button {
          pulseSendHaptic()
          focusedField = nil
          model.resolveQuantityEntry(amountText: quantityAmountText, unit: quantityUnit)
        } label: {
          Image(systemName: "arrow.up")
            .font(.body.weight(.semibold))
            .frame(width: 40, height: 40)
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
        Spacer(minLength: 8)
        Text("Converts using USDA serving when needed")
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
          .multilineTextAlignment(.trailing)
      }
    }
  }

  // MARK: - Shared bits

  func assistantCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 0) {
      content()
        .padding(14)
        .frame(maxWidth: 340, alignment: .leading)
        .chatCardChrome()
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
          .lineLimit(2)
          .minimumScaleFactor(0.85)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(ChatPalette.chipFill, in: Capsule())
          .overlay {
            Capsule()
              .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
          }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(idPrefix)
    }
  }

  func submitComposer() {
    pulseSendHaptic()
    focusedField = nil
    model.submit()
  }

  /// Ends editing before reading the when-eaten binding. Accessibility-driven
  /// value changes (and a final IME/dictation commit) can arrive in the next main
  /// actor turn when focus resigns. Reading synchronously here can therefore see
  /// the previous value and silently submit the empty-answer default ("Just now").
  func submitWhenEatenComposer() {
    pulseSendHaptic()
    focusedField = nil
    Task { @MainActor in
      await Task.yield()
      model.submitWhenEaten()
    }
  }

  func handlePhotoSelection(_ item: PhotosPickerItem) {
    focusedField = nil
    photoSelectionCoordinator.select(
      load: {
        try await item.loadTransferable(type: Data.self)
      },
      onLoaded: { data in
        await handlePhotoData(data)
      },
      onFailure: { failure in
        switch failure {
        case .unavailable:
          model.reportPhotoUnavailable(
            "That photo could not be loaded. Describe the food in text instead."
          )
        case .error:
          // PHPicker rarely surfaces a pure permission error; still steer toward Settings
          // when the library transfer fails so the person has a clear recovery path.
          model.reportPhotoUnavailable(Self.photoLoadFailureMessage)
        }
      },
      onFinished: {
        photoPickerItem = nil
      }
    )
  }

  static let photoLoadFailureMessage =
    "That photo could not be loaded. If Photos access is off, enable it for JustLogIt in Settings. "
    + "Otherwise describe the food in text or enter nutrition manually."

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
    pulseSendHaptic()
    focusedField = nil
    model.searchManually()
  }

  func confirmLog() {
    guard model.stage == .confirming else { return }
    guard !usesVolatileStore else { return }
    do {
      let entry = try model.makeRecord()
      // Shared UI + Siri persistence boundary (Spike B). HealthKit stays post-save.
      let result = try FoodLogRepository(context: modelContext).save(entry)
      model.markSaved(entryID: result.entryID, recognizedFoodID: result.recognizedFoodID)
      // Capture value types before async work; never block UX on Health or donation.
      let donateDescription = entry.originalText
      let donateConsumedAt = entry.consumedAt
      Task {
        await HealthSyncCoordinator.syncIfEnabled(entry, modelContext: modelContext)
      }
      Task {
        await FoodLogIntentDonation.donateSuccessfulLog(
          foodDescription: donateDescription,
          consumedAt: donateConsumedAt
        )
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
