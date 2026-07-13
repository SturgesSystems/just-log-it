import JustLogItCore
import SwiftData
import SwiftUI

struct LogView: View {
  private enum Field: Hashable {
    case description
    case manualSearch
    case quantity
  }

  private enum QuantityMode: String, CaseIterable, Identifiable {
    case servings = "Servings"
    case grams = "Grams"

    var id: Self { self }
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.modelContext) private var modelContext
  @StateObject private var model = LogViewModel()
  @FocusState private var focusedField: Field?
  @State private var resultsExpanded = false
  @State private var quantityMode = QuantityMode.servings

  private let configuration = AppConfiguration.current
  private let currentAnchor = "current-log-state"
  private let examples = [
    "Two large scrambled eggs",
    "One cup cooked jasmine rice",
    "About half a 12-ounce bottle of Fairlife chocolate milk",
  ]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          transcript
          Color.clear.frame(height: 1).id(currentAnchor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
      }
      .contentMargins(.horizontal, 20, for: .scrollContent)
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: model.stage) { _, stage in
        resultsExpanded = false
        if stage == .idle || stage == .parsing {
          quantityMode = .servings
        }
        if stage != .idle && stage != .failed && stage != .clarifying {
          focusedField = nil
        }
        withAnimation(reduceMotion ? nil : .snappy) {
          proxy.scrollTo(currentAnchor, anchor: .bottom)
        }
      }
    }
    .navigationTitle("JustLogIt")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      actionDock
    }
    .sheet(isPresented: $model.showManualEntry) {
      ManualEntryView(onSaved: model.markManualSaved)
    }
    .toolbar { keyboardToolbar }
  }

  @ViewBuilder
  private var transcript: some View {
    if model.stage == .idle {
      emptyPrompt
    } else {
      if !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        UserUtteranceBubble(text: model.input)
      }

      if shouldShowInterpretation {
        interpretationReceipt
      }

      switch model.stage {
      case .idle:
        EmptyView()
      case .parsing:
        ProcessingRow(title: "Understanding your description")
      case .searching:
        ProcessingRow(title: "Finding USDA matches")
      case .choosing:
        resultPicker
      case .loadingDetails:
        if let selection = model.selectedResult {
          FoodSelectionReceipt(result: selection)
        }
        ProcessingRow(title: "Loading nutrition")
      case .clarifying:
        quantityPrompt
      case .reviewing:
        nutritionReview
      case .completed:
        completionReceipt
      case .failed:
        recoveryCard
      }
    }
  }

  private var emptyPrompt: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "fork.knife")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text("What did you eat?")
          .font(.title.bold())
        Text("Describe one food and the amount. You’ll review the match before it’s saved.")
          .foregroundStyle(.secondary)
      }

      if configuration.providerDescription == "Not configured" {
        VStack(alignment: .leading, spacing: 10) {
          Label("USDA matching isn’t configured", systemImage: "exclamationmark.triangle.fill")
            .font(.headline)
          Text("You can still save nutrition with manual entry.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Button("Enter Manually") {
            focusedField = nil
            model.showManualEntry = true
          }
          .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Examples")
          .font(.headline)
        ForEach(examples, id: \.self) { example in
          Button {
            model.input = example
            submitDescription()
          } label: {
            HStack(spacing: 12) {
              Text(example)
                .multilineTextAlignment(.leading)
              Spacer(minLength: 8)
              Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 14))
          .accessibilityHint("Uses this example as your food description")
        }
      }

      Label("Your food log stays on this iPhone", systemImage: "lock.shield")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var shouldShowInterpretation: Bool {
    model.parsed != nil
      && model.stage != .parsing
      && model.stage != .completed
  }

  private var interpretationReceipt: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("INTERPRETED AS")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
      Text(model.parsed?.productName ?? model.manualSearchTerms)
        .font(.headline)
      if let brand = model.parsed?.brand, !brand.isEmpty {
        Text(brand)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      if let quantity = model.parsed?.quantityText, !quantity.isEmpty {
        Label(quantity, systemImage: "scalemass")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      if model.parsed?.containsMultipleFoods == true {
        Label("Matching the principal food from your description", systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
  }

  private var resultPicker: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose a Match")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)
      Text("Nutrition varies by product and preparation.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      ForEach(Array(model.results.prefix(resultsExpanded ? model.results.count : 5))) { result in
        Button {
          model.select(result)
        } label: {
          USDAResultRow(result: result)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("usda-result-\(result.fdcID)")
      }

      if model.results.count > 5 {
        Button(resultsExpanded ? "Show Fewer Matches" : "Show \(model.results.count - 5) More") {
          withAnimation(reduceMotion ? nil : .snappy) {
            resultsExpanded.toggle()
          }
        }
        .buttonStyle(.bordered)
      }

      Divider().padding(.top, 4)
      Menu("Other Options", systemImage: "ellipsis.circle") {
        Button("Edit Description", systemImage: "pencil") {
          model.cancel()
          focusedField = .description
        }
        Button("Enter Nutrition Manually", systemImage: "square.and.pencil") {
          model.showManualEntry = true
        }
      }
    }
  }

  private var quantityPrompt: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("How Much Did You Eat?")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)

      if let details = model.details {
        VStack(alignment: .leading, spacing: 4) {
          Text(details.description)
            .font(.headline)
          LabeledContent("USDA serving", value: details.householdServing ?? servingText(details))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      if let message = model.message {
        Label(message, systemImage: "info.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("status-message")
      }

      Picker("Quantity unit", selection: $quantityMode) {
        ForEach(QuantityMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      LabeledContent(quantityMode == .servings ? "Number of servings" : "Amount (grams)") {
        HStack(spacing: 6) {
          TextField(
            quantityMode == .servings ? "1" : "100",
            text: quantityMode == .servings
              ? $model.clarificationServings : $model.clarificationGrams
          )
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .focused($focusedField, equals: .quantity)
          .frame(minWidth: 56)
          .accessibilityIdentifier("quantity-value")
          Text(quantityMode == .servings ? "servings" : "g")
            .foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .background(.background, in: .rect(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(.separator, lineWidth: 0.5)
      }

      Button("Review Nutrition", systemImage: "arrow.right") {
        focusedField = nil
        if quantityMode == .servings {
          model.resolveWithServings()
        } else {
          model.resolveWithGrams()
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!model.canResolveClarificationQuantity(usingServings: quantityMode == .servings))

      Menu("Other Options", systemImage: "ellipsis.circle") {
        Button("Choose a Different Food", systemImage: "arrow.uturn.backward") {
          model.searchManually()
        }
        Button("Enter Nutrition Manually", systemImage: "square.and.pencil") {
          model.showManualEntry = true
        }
      }
    }
    .padding(16)
    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
  }

  private var nutritionReview: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Review entry")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)

      if let details = model.details, let resolution = model.resolution {
        VStack(alignment: .leading, spacing: 5) {
          Text(details.description)
            .font(.headline)
          if let brand = details.brandOwner, !brand.isEmpty {
            Text(brand)
              .font(.subheadline)
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
      }

      MacroSummaryView(nutrients: model.nutrients)

      if let fdcID = model.details?.fdcID {
        Text("USDA FoodData Central · FDC \(fdcID)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let message = model.message {
        Label(message, systemImage: "exclamationmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.red)
          .accessibilityIdentifier("status-message")
      }

      Button("Choose a Different Food") {
        model.searchManually()
      }
      .font(.subheadline)
    }
    .padding(16)
    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
  }

  private var completionReceipt: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Food Logged", systemImage: "checkmark.circle.fill")
        .font(.title2.bold())
        .foregroundStyle(.green)
      Text("Your nutrition snapshot is saved on this device.")
        .foregroundStyle(.secondary)
      if let message = model.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("status-message")
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.green.opacity(0.1), in: .rect(cornerRadius: 16))
  }

  private var recoveryCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(recoveryTitle, systemImage: "exclamationmark.circle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("recovery-title")

      Text(model.message ?? "Try simpler search terms or enter nutrition manually.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("status-message")

      HStack {
        Button(recoveryActionTitle) {
          performRecoveryAction()
        }
        Spacer()
        Button("Enter Manually") {
          focusedField = nil
          model.showManualEntry = true
        }
      }
      .font(.subheadline)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 16))
  }

  private var recoveryTitle: String {
    switch model.failureKind {
    case .interpretation:
      "Couldn’t Interpret That"
    case .search:
      "Couldn’t Reach USDA"
    case .noResults:
      "No Matches Found"
    case .details:
      "Couldn’t Load This Food"
    case nil:
      "Couldn’t Complete That"
    }
  }

  private var recoveryActionTitle: String {
    switch model.failureKind {
    case .interpretation, nil:
      "Edit Description"
    case .search, .noResults:
      "Edit Search"
    case .details:
      "Search Again"
    }
  }

  private func performRecoveryAction() {
    switch model.failureKind {
    case .interpretation, nil:
      model.cancel()
      focusedField = .description
    case .search, .noResults:
      focusedField = .manualSearch
    case .details:
      searchManually()
    }
  }

  @ViewBuilder
  private var actionDock: some View {
    switch model.stage {
    case .idle:
      dockContainer { descriptionComposer }
    case .parsing, .searching, .loadingDetails:
      dockContainer {
        Button(role: .cancel, action: model.cancel) {
          Text("Cancel")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("cancel-operation")
      }
    case .reviewing:
      dockContainer {
        Button(action: saveEntry) {
          Label("Save Entry", systemImage: "checkmark")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("save-entry")
      }
    case .completed:
      dockContainer {
        Button(action: model.reset) {
          Label("Log Another Food", systemImage: "plus")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("log-another")
      }
    case .failed:
      dockContainer { searchComposer }
    case .choosing, .clarifying:
      EmptyView()
    }
  }

  private var descriptionComposer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      Button {
        focusedField = nil
        model.showManualEntry = true
      } label: {
        Label("Manual", systemImage: "square.and.pencil")
          .font(.subheadline.weight(.medium))
          .frame(minHeight: 32)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityLabel("Enter nutrition manually")
      .accessibilityIdentifier("manual-entry-button")

      TextField("Food and amount", text: $model.input, axis: .vertical)
        .lineLimit(1...4)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background, in: .rect(cornerRadius: 18))
        .overlay {
          RoundedRectangle(cornerRadius: 18)
            .stroke(.separator, lineWidth: 0.5)
        }
        .focused($focusedField, equals: .description)
        .submitLabel(.continue)
        .onSubmit(submitDescription)
        .accessibilityIdentifier("food-description")

      Button(action: submitDescription) {
        Image(systemName: "arrow.up")
          .font(.body.bold())
          .frame(width: 34, height: 34)
      }
      .buttonStyle(.borderedProminent)
      .clipShape(.circle)
      .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Continue")
      .accessibilityIdentifier("continue-button")
    }
  }

  private var searchComposer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Search USDA", text: $model.manualSearchTerms, axis: .vertical)
        .lineLimit(1...3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background, in: .rect(cornerRadius: 18))
        .overlay {
          RoundedRectangle(cornerRadius: 18)
            .stroke(.separator, lineWidth: 0.5)
        }
        .focused($focusedField, equals: .manualSearch)
        .submitLabel(.search)
        .onSubmit(searchManually)
        .accessibilityIdentifier("manual-search")

      Button(action: searchManually) {
        Image(systemName: "magnifyingglass")
          .font(.body.bold())
          .frame(width: 34, height: 34)
      }
      .buttonStyle(.borderedProminent)
      .clipShape(.circle)
      .disabled(model.manualSearchTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Search USDA")
      .accessibilityIdentifier("search-usda-button")
    }
  }

  private func dockContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
      Divider()
      content()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    .background(.bar)
  }

  @ToolbarContentBuilder
  private var keyboardToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button("Done") { focusedField = nil }
    }
  }

  private func submitDescription() {
    focusedField = nil
    model.submit()
  }

  private func searchManually() {
    focusedField = nil
    model.searchManually()
  }

  private func saveEntry() {
    do {
      let entry = try model.makeRecord()
      modelContext.insert(entry)
      try modelContext.save()
      model.markSaved()
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

private struct UserUtteranceBubble: View {
  let text: String

  var body: some View {
    HStack {
      Spacer(minLength: 44)
      Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(.tint, in: .rect(cornerRadius: 18))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("You entered, \(text)")
  }
}

private struct ProcessingRow: View {
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      ProgressView()
      Text(title)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

private struct FoodSelectionReceipt: View {
  let result: FoodSearchResult

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(result.displayDescription)
          .font(.headline)
        if let brand = result.brandName ?? result.brandOwner, !brand.isEmpty {
          Text(brand)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 14))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Selected food, \(result.displayDescription)")
  }
}

private struct USDAResultRow: View {
  let result: FoodSearchResult

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(result.displayDescription)
          .font(.headline)
          .foregroundStyle(.primary)
        if let brand = result.brandName ?? result.brandOwner, !brand.isEmpty {
          Text(brand)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { resultMetadata }
          VStack(alignment: .leading, spacing: 4) { resultMetadata }
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 14))
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Selects this USDA food")
  }

  @ViewBuilder
  private var resultMetadata: some View {
    if let serving = result.servingDescription {
      Text(serving)
    }
    Text(result.shortDataType)
  }
}

private struct MacroSummaryView: View {
  let nutrients: [NutrientAmount]

  private let primaryKeys: [NutrientKey] = [.energy, .protein, .carbohydrate, .totalFat]

  var body: some View {
    let primary = primaryKeys.compactMap { key in nutrients.first(where: { $0.key == key }) }
    let remaining = nutrients.filter { !primaryKeys.contains($0.key) }

    VStack(alignment: .leading, spacing: 14) {
      if primary.isEmpty {
        Label("Nutrition unavailable", systemImage: "questionmark.circle")
          .foregroundStyle(.secondary)
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 10) {
            ForEach(primary) { nutrient in
              MacroValue(nutrient: nutrient)
                .frame(maxWidth: .infinity)
            }
          }
          VStack(spacing: 10) {
            ForEach(primary) { nutrient in
              MacroValue(nutrient: nutrient)
            }
          }
        }
      }

      if !remaining.isEmpty {
        DisclosureGroup("More Nutrients") {
          NutrientSummaryView(nutrients: remaining)
            .padding(.top, 10)
        }
      }
    }
  }
}

private struct MacroValue: View {
  let nutrient: NutrientAmount

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(nutrient.key.displayName)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(nutrient.formattedAmount)
        .font(nutrient.key == .energy ? .title2.bold() : .headline)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
