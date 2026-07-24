import CoreTransferable
import JustLogItCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Owns the asynchronous PhotosPicker transfer so only the newest selection can
/// reach the logging pipeline. Cancellation is advisory for transferable loads,
/// so a generation check also rejects loaders that finish after cancellation.
@MainActor
final class LatestPhotoSelectionCoordinator: ObservableObject {
  enum LoadFailure {
    case unavailable
    case error
  }

  @Published private(set) var isLoading = false

  private var generation: UInt = 0
  private var loadTask: Task<Void, Never>?

  func select(
    load: @escaping @MainActor () async throws -> Data?,
    onLoaded: @escaping @MainActor (Data) async -> Void,
    onFailure: @escaping @MainActor (LoadFailure) -> Void,
    onFinished: @escaping @MainActor () -> Void
  ) {
    cancel()
    let selectionGeneration = generation
    isLoading = true

    loadTask = Task { [weak self] in
      do {
        guard let data = try await load(), !data.isEmpty else {
          guard self?.isCurrent(selectionGeneration) == true else { return }
          onFailure(.unavailable)
          self?.finish(selectionGeneration, onFinished: onFinished)
          return
        }
        guard self?.isCurrent(selectionGeneration) == true else { return }
        await onLoaded(data)
      } catch is CancellationError {
        return
      } catch {
        guard self?.isCurrent(selectionGeneration) == true else { return }
        onFailure(.error)
      }

      self?.finish(selectionGeneration, onFinished: onFinished)
    }
  }

  func cancel() {
    generation &+= 1
    loadTask?.cancel()
    loadTask = nil
    isLoading = false
  }

  private func isCurrent(_ selectionGeneration: UInt) -> Bool {
    !Task.isCancelled && generation == selectionGeneration
  }

  private func finish(
    _ selectionGeneration: UInt,
    onFinished: @MainActor () -> Void
  ) {
    guard isCurrent(selectionGeneration) else { return }
    loadTask = nil
    isLoading = false
    onFinished()
  }
}

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
  @Environment(\.usesVolatileStore) var usesVolatileStore
  @EnvironmentObject var appNavigation: AppNavigation
  @Query(sort: \RecognizedFoodRecord.lastUsedAt, order: .reverse)
  var recentRecognizedFoods: [RecognizedFoodRecord]
  @StateObject var model = LogViewModel()
  @FocusState var focusedField: Field?
  @State var editingTurnID: UUID?
  @State var editDraft = ""
  @State var photoPickerItem: PhotosPickerItem?
  @StateObject var photoSelectionCoordinator = LatestPhotoSelectionCoordinator()
  @StateObject var voiceInput = VoiceInputController()
  @State var showPhotoLibraryPicker = false
  @State var showCameraPicker = false
  /// Client-side typeahead filter over the current USDA page (composer stays visible).
  @State var usdaFilter = ""
  /// Amount + unit for post-USDA quantity entry (dock).
  @State var quantityAmountText = ""
  @State var quantityUnit = "serving"
  /// Bumps on composer send so `.sensoryFeedback` can fire a light impact without keystroke spam.
  @State var sendHapticTick = 0
  /// Siri/Shortcut/in-app handoff deferred while a log conversation is already in progress.
  @State var offeredPendingFoodLog: PendingFoodLog?

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
          // Prefer seeds set by editAmountFromReview (current amount) when present.
          if !model.clarificationServings.isEmpty {
            quantityAmountText = model.clarificationServings
            quantityUnit = "serving"
          } else if !model.clarificationGrams.isEmpty {
            quantityAmountText = model.clarificationGrams
            quantityUnit = "g"
          } else {
            quantityAmountText = ""
            quantityUnit = "serving"
          }
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
    .background {
      ZStack {
        ChatPalette.canvas
        ChatPalette.canvasGradient(for: colorScheme)
      }
      .ignoresSafeArea()
    }
    .navigationTitle("JustLogIt")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .top, spacing: 0) {
      if let pending = offeredPendingFoodLog {
        siriPendingBanner(pending)
      }
    }
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
      handlePhotoSelection(item)
    }
    .onChange(of: voiceInput.transcript) { _, transcript in
      // Dictation fills the ordinary composer; the user still explicitly taps Send.
      model.input = transcript
    }
    .alert(
      "Voice input unavailable",
      isPresented: Binding(
        get: { voiceInput.errorMessage != nil },
        set: { if !$0 { voiceInput.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { voiceInput.errorMessage = nil }
    } message: {
      Text(voiceInput.errorMessage ?? "")
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
    .onAppear(perform: consumePendingFoodLog)
    .onChange(of: appNavigation.pendingFoodLog) { _, _ in
      consumePendingFoodLog()
    }
    .onDisappear {
      photoSelectionCoordinator.cancel()
      voiceInput.cancel()
    }
    .task {
      // Speculative FM prewarm is async and detached inside the parser pool, but still
      // yield a beat so the first Log layout / first keystroke is not contending for it.
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(250))
      await model.prewarmParser()
    }
    // Subtle haptics: success on save, warning once on pipeline fail, light impact on send.
    // Bound to discrete transitions/ticks — never keystrokes. Haptics stay on with reduceMotion.
    .sensoryFeedback(.success, trigger: model.stage) { _, new in
      new == .completed
    }
    .sensoryFeedback(.warning, trigger: model.stage) { _, new in
      new == .failed
    }
    .sensoryFeedback(.impact(weight: .light), trigger: sendHapticTick)
  }

  /// Light impact when the user commits a composer send (not mid-typing).
  func pulseSendHaptic() {
    sendHapticTick &+= 1
  }

  func startNewConversation() {
    photoSelectionCoordinator.cancel()
    voiceInput.cancel()
    editingTurnID = nil
    editDraft = ""
    usdaFilter = ""
    photoPickerItem = nil
    focusedField = nil
    model.reset()
  }

  /// True when applying a pending handoff would wipe a mid-flow review/conversation.
  var isConversationInProgress: Bool {
    switch model.stage {
    case .idle, .completed:
      return false
    default:
      return !model.transcript.isEmpty
    }
  }

  func consumePendingFoodLog() {
    guard let pending = appNavigation.takePendingFoodLog() else { return }
    // Protect in-progress review: queue for an explicit Start instead of model.reset().
    if isConversationInProgress {
      offeredPendingFoodLog = pending
      return
    }
    applyPendingFoodLog(pending)
  }

  func applyPendingFoodLog(_ pending: PendingFoodLog) {
    offeredPendingFoodLog = nil
    photoSelectionCoordinator.cancel()
    voiceInput.cancel()
    editingTurnID = nil
    editDraft = ""
    model.reset()
    model.input = pending.description
    if let consumedAt = pending.consumedAt {
      model.consumedAt = consumedAt
      model.consumedAtInference = MealTimeInference(
        date: consumedAt,
        displayLabel: "From Siri",
        isClear: true
      )
    }
    switch pending.source {
    case .siri, .shortcut:
      // Voice / Shortcut handoff: run the same submit path as typing Enter.
      submitComposer()
    case .inApp:
      focusedField = .composer
    }
  }

  func startOfferedPendingFoodLog() {
    guard let pending = offeredPendingFoodLog else { return }
    applyPendingFoodLog(pending)
  }

  func dismissOfferedPendingFoodLog() {
    offeredPendingFoodLog = nil
  }

  @ViewBuilder
  func siriPendingBanner(_ pending: PendingFoodLog) -> some View {
    let lead: String = {
      switch pending.source {
      case .siri, .shortcut:
        return "Siri wants to log"
      case .inApp:
        return "Ready to log"
      }
    }()

    HStack(alignment: .center, spacing: 10) {
      Image(systemName: "mic.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)

      Text("\(lead): \(pending.description)")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(lead): \(pending.description)")
        .accessibilityHint(
          "From Siri or Shortcuts. Start to review this food log; nothing is saved until you confirm."
        )

      Button("Start") {
        startOfferedPendingFoodLog()
      }
      .font(.subheadline.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .accessibilityHint("Begins logging the food phrase from Siri")
      .accessibilityIdentifier("siri-pending-start")

      Button("Dismiss") {
        dismissOfferedPendingFoodLog()
      }
      .font(.subheadline.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityHint("Discards this Siri food phrase")
      .accessibilityIdentifier("siri-pending-dismiss")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial)
    .overlay(alignment: .bottom) {
      Divider()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("siri-pending-banner")
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

  /// True while the live typing bubble is for an on-device photo proposal.
  var isProposingFromPhoto: Bool {
    model.transcript.last(where: \.isUser)?.imageData != nil
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
          // Only the original food description can be safely reinterpreted from
          // scratch. Later user turns are quantities, preparation answers, or
          // meal times and need stage-specific rewind semantics before they can
          // be made editable.
          onEdit: imageData == nil && id == editableFoodDescriptionTurnID
            ? { beginEditing(id: id, text: text) }
            : nil
        )
      case .system(_, let text):
        ChatAssistantBubble(text: text)
      }
    }
  }

  private var editableFoodDescriptionTurnID: UUID? {
    model.transcript.lazy.compactMap { turn -> UUID? in
      guard case .user(let id, _, let imageData) = turn, imageData == nil else { return nil }
      return id
    }.first
  }

  @ViewBuilder
  var liveAssistantContent: some View {
    switch model.stage {
    case .idle, .completed:
      EmptyView()
    case .parsing:
      ChatTypingBubble(
        label: isProposingFromPhoto
          ? "Looking at your photo…"
          : "Understanding your food…",
        onStop: { model.cancel() }
      )
    case .awaitingClarification:
      clarificationAttachments
    case .searching:
      ChatTypingBubble(
        label: model.compositeMatchingStatusLabel ?? "Searching USDA…",
        onStop: { model.cancel() }
      )
    case .choosing:
      resultPickerCard
    case .loadingDetails:
      if let selection = model.selectedResult {
        assistantCard {
          FoodSelectionReceipt(result: selection)
        }
      }
      ChatTypingBubble(label: "Loading nutrition…", onStop: { model.cancel() })
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

  /// Up to 5 local recents for quick-start chips. Prefer SwiftData recognized foods;
  /// fall back to remembered USDA selections. Empty → section is hidden.
  var recentFoodQuickStarts: [RecentFoodItem] {
    RecentFoodsSource.items(
      recognized: recentRecognizedFoods,
      rememberedStore: model.rememberedFoods,
      limit: 5
    )
  }

  var emptyState: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: "fork.knife.circle.fill")
          .font(.system(size: 40))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)

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
          .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
          )
      }

      RecentFoodsBar(foods: recentFoodQuickStarts) { food in
        startLogFromRecentFood(food)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Try saying")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        ForEach(examples, id: \.self) { example in
          Button {
            model.input = example
            submitComposer()
          } label: {
            HStack(spacing: 12) {
              Text(example)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.85)
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(ChatPalette.assistantFill, in: RoundedRectangle(cornerRadius: ChatPalette.chipCornerRadius, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: ChatPalette.chipCornerRadius, style: .continuous)
                .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
            }
          }
          .buttonStyle(.plain)
          .accessibilityHint("Uses this example as your food description")
        }
      }

      siriTipCard

      Label("Food interpretation stays on this iPhone", systemImage: "lock.shield.fill")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ChatPalette.chipFill, in: Capsule())
        .accessibilityLabel("Food interpretation stays on this iPhone")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 8)
  }

  /// Featured empty-state tip for Siri/Shortcuts handoff. Decorative mic + sparkles only;
  /// VoiceOver uses a single combined label and the review-before-save hint.
  var siriTipCard: some View {
    let shadow = ChatPalette.cardShadow(colorScheme: colorScheme, reduceMotion: reduceMotion)
    let accentWash = Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10)

    return HStack(alignment: .center, spacing: 14) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "mic.fill")
          .font(.title3.weight(.semibold))
          .foregroundStyle(Color.accentColor)
          .symbolRenderingMode(.hierarchical)
          .frame(width: 44, height: 44)
          .background(
            accentWash,
            in: Circle()
          )

        Image(systemName: "sparkles")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(Color.accentColor)
          .padding(4)
          .background(ChatPalette.assistantFill, in: Circle())
          .overlay {
            Circle()
              .strokeBorder(ChatPalette.hairline, lineWidth: 0.5)
          }
          .offset(x: 4, y: -4)
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text("Try with Siri")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.accentColor)
          .textCase(.uppercase)

        Text("Say “Log food in JustLogIt”")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)

        Text("Siri asks what you ate, then opens for review")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .background {
      RoundedRectangle(cornerRadius: ChatPalette.cardCornerRadius, style: .continuous)
        .fill(ChatPalette.assistantFill)
      RoundedRectangle(cornerRadius: ChatPalette.cardCornerRadius, style: .continuous)
        .fill(
          LinearGradient(
            colors: [accentWash, Color.accentColor.opacity(0.02)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: ChatPalette.cardCornerRadius, style: .continuous)
        .strokeBorder(
          Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.18),
          lineWidth: 0.5
        )
    }
    .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Say Log food in JustLogIt with Siri")
    .accessibilityHint(
      "Siri asks what you ate. JustLogIt then opens for review and never saves nutrition without your confirmation."
    )
    .accessibilityIdentifier("siri-tip")
  }

  /// Seeds the composer with a recent food name and starts the reviewed log flow.
  /// Does not save or skip confirmation.
  func startLogFromRecentFood(_ food: RecentFoodItem) {
    let text = food.composerText
    guard !text.isEmpty else { return }
    model.input = text
    submitComposer()
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
    pulseSendHaptic()
    editingTurnID = nil
    editDraft = ""
    focusedField = nil
    model.editUserMessage(id: id, newText: text)
  }
}
