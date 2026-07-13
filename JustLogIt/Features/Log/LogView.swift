import JustLogItCore
import SwiftData
import SwiftUI

struct LogView: View {
  @Environment(\.modelContext) private var modelContext
  @StateObject private var model = LogViewModel()
  @FocusState private var composerFocused: Bool

  private let examples = [
    "Two large scrambled eggs",
    "One cup cooked jasmine rice",
    "About half a 12-ounce bottle of Fairlife chocolate milk",
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        statusContent
      }
      .padding()
    }
    .navigationTitle("Log")
    .safeAreaInset(edge: .bottom) {
      if model.stage == .idle || model.stage == .failed {
        composer
          .background(.bar)
      }
    }
    .sheet(isPresented: $model.showManualEntry) {
      ManualEntryView()
    }
    .animation(.snappy, value: model.stage)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("What did you eat?")
        .font(.largeTitle.bold())
      Text(
        "Describe one food. JustLogIt interprets the wording on device, then lets you choose the USDA match."
      )
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    if let message = model.message {
      Label(
        message, systemImage: model.stage == .completed ? "checkmark.circle.fill" : "info.circle"
      )
      .foregroundStyle(model.stage == .completed ? .green : .secondary)
      .accessibilityIdentifier("status-message")
    }

    switch model.stage {
    case .idle:
      examplesView
    case .parsing:
      progress("Understanding your description…")
    case .searching:
      progress("Searching FoodData Central…")
    case .choosing:
      parsedSummary
      resultList
    case .loadingDetails:
      progress("Loading nutrition details…")
    case .clarifying:
      quantityClarification
    case .reviewing:
      review
    case .completed:
      completed
    case .failed:
      manualRecovery
    }
  }

  private var composer: some View {
    VStack(spacing: 12) {
      TextField("Example: Two large scrambled eggs", text: $model.input, axis: .vertical)
        .lineLimit(2...5)
        .textFieldStyle(.roundedBorder)
        .focused($composerFocused)
        .submitLabel(.search)
        .onSubmit(model.submit)
        .accessibilityIdentifier("food-description")

      HStack {
        Button("Enter manually") { model.showManualEntry = true }
          .buttonStyle(.bordered)
        Spacer()
        Button("Continue", systemImage: "arrow.right") {
          composerFocused = false
          model.submit()
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("continue-button")
      }

      Text(
        "Parsing happens on device. Derived food search terms are sent to the configured USDA service; saved entries stay on this device."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding()
  }

  private var examplesView: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Try an example").font(.headline)
      ForEach(examples, id: \.self) { example in
        Button {
          model.input = example
          model.submit()
        } label: {
          Label(example, systemImage: "sparkles")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func progress(_ title: String) -> some View {
    VStack(spacing: 16) {
      ProgressView()
      Text(title).foregroundStyle(.secondary)
      Button("Cancel", role: .cancel, action: model.cancel)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
    .accessibilityElement(children: .combine)
  }

  private var parsedSummary: some View {
    GroupBox("Understood") {
      VStack(alignment: .leading, spacing: 4) {
        if let brand = model.parsed?.brand {
          Text(brand).font(.subheadline).foregroundStyle(.secondary)
        }
        Text(model.parsed?.productName ?? model.manualSearchTerms).font(.headline)
        if let quantity = model.parsed?.quantityText { Text(quantity).foregroundStyle(.secondary) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var resultList: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose the matching food").font(.title2.bold())
      ForEach(model.results) { result in
        Button {
          model.select(result)
        } label: {
          USDAResultRow(result: result)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("usda-result-\(result.fdcID)")
      }
      Button("Edit search") {
        model.manualSearchTerms =
          model.parsed.map { FoodSearchQueryBuilder().build(from: $0).query } ?? model.input
        model.cancel()
      }
      Button("Enter nutrition manually") { model.showManualEntry = true }
    }
  }

  private var quantityClarification: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("How much did you eat?").font(.title2.bold())
      if let details = model.details {
        LabeledContent("USDA serving", value: details.householdServing ?? servingText(details))
      }
      TextField("USDA servings", text: $model.clarificationServings)
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
      Button("Use servings", action: model.resolveWithServings)
        .buttonStyle(.borderedProminent)
      Text("or").frame(maxWidth: .infinity).foregroundStyle(.secondary)
      TextField("Consumed grams", text: $model.clarificationGrams)
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
      Button("Use grams", action: model.resolveWithGrams)
        .buttonStyle(.bordered)
      Divider()
      Button("Choose a different food") { model.searchManually() }
      Button("Enter nutrition manually") { model.showManualEntry = true }
    }
  }

  private var review: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Review entry").font(.title2.bold())
      if let details = model.details, let resolution = model.resolution {
        GroupBox {
          VStack(alignment: .leading, spacing: 6) {
            Text(details.description).font(.headline)
            if let brand = details.brandOwner { Text(brand).foregroundStyle(.secondary) }
            Text(resolution.displayText)
            if model.parsed?.isApproximate == true { Label("Approximate", systemImage: "tilde") }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      NutrientSummaryView(nutrients: model.nutrients)
      Text("USDA FoodData Central • FDC \(model.details?.fdcID ?? 0)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Save entry", systemImage: "checkmark") {
        do {
          modelContext.insert(try model.makeRecord())
          try modelContext.save()
          model.markSaved()
        } catch {
          model.markSaveFailed()
        }
      }
      .buttonStyle(.borderedProminent)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("save-entry")
      Button("Choose a different food") { model.searchManually() }
    }
  }

  private var completed: some View {
    ContentUnavailableView {
      Label("Logged", systemImage: "checkmark.circle.fill")
    } description: {
      Text("Your nutrition snapshot is saved locally.")
    } actions: {
      Button("Log another food", action: model.reset)
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("log-another")
    }
  }

  private var manualRecovery: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("USDA search terms", text: $model.manualSearchTerms)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("manual-search")
      Button("Search USDA", action: model.searchManually)
        .buttonStyle(.borderedProminent)
      Button("Enter nutrition manually") { model.showManualEntry = true }
    }
  }

  private func servingText(_ food: FoodDetails) -> String {
    guard let size = food.servingSize, let unit = food.servingSizeUnit else {
      return "Not provided"
    }
    return "\(size.formatted()) \(unit)"
  }
}

private struct USDAResultRow: View {
  let result: FoodSearchResult

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(result.description).font(.headline).foregroundStyle(.primary)
      if let brand = result.brandName ?? result.brandOwner {
        Text(brand).font(.subheadline).foregroundStyle(.secondary)
      }
      HStack {
        if let household = result.householdServing {
          Text(household)
        } else if let size = result.servingSize, let unit = result.servingSizeUnit {
          Text("\(size.formatted()) \(unit)")
        }
        Spacer()
        Text(result.dataType)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: .rect(cornerRadius: 14))
  }
}

struct NutrientSummaryView: View {
  let nutrients: [NutrientAmount]

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
      ForEach(nutrients) { nutrient in
        GridRow {
          Text(nutrient.key.displayName)
          Text(
            "\(nutrient.amount.formatted(.number.precision(.fractionLength(0...1)))) \(nutrient.unit)"
          )
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
  }
}
