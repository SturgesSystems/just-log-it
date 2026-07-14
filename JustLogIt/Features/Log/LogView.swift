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
  enum Field: Hashable {
    case composer
    case quantity
  }

  enum ComposerMode: Equatable {
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

  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.modelContext) var modelContext
  @StateObject var model = LogViewModel()
  @FocusState var focusedField: Field?
  @State var editingTurnID: UUID?
  @State var editDraft = ""
  @State var photoPickerItem: PhotosPickerItem?
  @State var showPhotoLibraryPicker = false
  @State var showCameraPicker = false
  /// Client-side typeahead filter over the current USDA page (composer stays visible).
  @State var usdaFilter = ""
  /// Amount + unit for post-USDA quantity entry (dock).
  @State var quantityAmountText = ""
  @State var quantityUnit = "serving"

  var onOpenEntry: ((UUID) -> Void)?
  var onOpenFood: ((UUID) -> Void)?

  let configuration = AppConfiguration.current
  let scrollAnchor = "chat-bottom"
  let examples = [
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

  func startNewConversation() {
    editingTurnID = nil
    editDraft = ""
    usdaFilter = ""
    photoPickerItem = nil
    focusedField = nil
    model.reset()
  }

  func scrollToBottom(_ proxy: ScrollViewProxy) {
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
      proxy.scrollTo(scrollAnchor, anchor: .bottom)
    }
  }

  /// Programmatic scroll dismisses the keyboard when `.scrollDismissesKeyboard` is on.
  /// Skip auto-scroll while the user is typing so keystrokes aren't stolen.
  func scrollToBottomIfSafe(_ proxy: ScrollViewProxy) {
    guard focusedField == nil else { return }
    Task { @MainActor in scrollToBottom(proxy) }
  }

  /// Results shown in the USDA widget: optional local typeahead filter.
  var displayedUSDAResults: [FoodSearchResult] {
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
  var transcriptMessages: some View {
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
  var liveAssistantContent: some View {
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

  var emptyState: some View {
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

  func beginEditing(id: UUID, text: String) {
    editingTurnID = id
    editDraft = text
    model.input = text
    focusedField = .composer
  }

  func cancelEditing() {
    editingTurnID = nil
    editDraft = ""
    if model.stage == .idle {
      // keep whatever is in input
    }
    focusedField = nil
  }

  func commitEdit() {
    guard let id = editingTurnID else { return }
    let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    editingTurnID = nil
    editDraft = ""
    focusedField = nil
    model.editUserMessage(id: id, newText: text)
  }
}
