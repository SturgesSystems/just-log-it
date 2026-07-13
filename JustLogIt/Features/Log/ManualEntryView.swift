import JustLogItCore
import SwiftData
import SwiftUI

struct ManualEntryView: View {
  private enum Field: Hashable, CaseIterable {
    case name
    case amount
    case calories
    case protein
    case carbohydrates
    case fat
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  let onSaved: () -> Void

  @State private var name = ""
  @State private var amount = ""
  @State private var calories = ""
  @State private var protein = ""
  @State private var carbohydrates = ""
  @State private var fat = ""
  @State private var consumedAt = Date.now
  @State private var approximate = false
  @State private var errorMessage: String?
  @FocusState private var focusedField: Field?

  init(onSaved: @escaping () -> Void = {}) {
    self.onSaved = onSaved
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Food") {
          TextField("Food name", text: $name)
            .submitLabel(.next)
            .focused($focusedField, equals: .name)
            .onSubmit { focusedField = .amount }
            .accessibilityIdentifier("manual-name")
          TextField("Amount eaten", text: $amount)
            .submitLabel(.next)
            .focused($focusedField, equals: .amount)
            .onSubmit { focusedField = .calories }
            .accessibilityIdentifier("manual-amount")
          DatePicker("Date and time", selection: $consumedAt)
          Toggle("Approximate", isOn: $approximate)
        }
        Section {
          numericField("Calories", text: $calories, unit: "kcal", field: .calories)
          numericField("Protein", text: $protein, unit: "g", field: .protein)
          numericField(
            "Carbohydrates", text: $carbohydrates, unit: "g", field: .carbohydrates)
          numericField("Total fat", text: $fat, unit: "g", field: .fat)
        } header: {
          Text("Nutrition")
        } footer: {
          Text("Calories are required. Other nutrients are optional.")
        }

        if let displayedError = validationMessage ?? errorMessage {
          Section {
            Label(displayedError, systemImage: "exclamationmark.circle")
              .foregroundStyle(.red)
          }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Manual Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            focusedField = nil
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(!canSave)
            .accessibilityIdentifier("manual-save")
        }
        ToolbarItemGroup(placement: .keyboard) {
          Button("Previous", systemImage: "chevron.up") { moveFocus(by: -1) }
            .disabled(focusedField == Field.allCases.first)
          Button("Next", systemImage: "chevron.down") { moveFocus(by: 1) }
            .disabled(focusedField == Field.allCases.last)
          Spacer()
          Button("Done") { focusedField = nil }
        }
      }
    }
  }

  private func numericField(
    _ title: String, text: Binding<String>, unit: String, field: Field
  ) -> some View {
    LabeledContent(title) {
      HStack {
        TextField("0", text: text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .focused($focusedField, equals: field)
          .accessibilityLabel(title)
          .accessibilityIdentifier("manual-\(fieldIdentifier(field))")
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && parseNonnegative(calories) != nil
      && validationMessage == nil
  }

  private var validationMessage: String? {
    for (label, value) in [
      ("Protein", protein), ("Carbohydrates", carbohydrates), ("Total fat", fat),
    ] where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      if parseNonnegative(value) == nil {
        return "\(label) must be a nonnegative number."
      }
    }
    if !calories.isEmpty, parseNonnegative(calories) == nil {
      return "Calories must be a nonnegative number."
    }
    return nil
  }

  private func save() {
    focusedField = nil
    guard let calorieValue = parseNonnegative(calories), validationMessage == nil else {
      errorMessage = "Calories must be a nonnegative number."
      return
    }
    var nutrients = [NutrientAmount(key: .energy, amount: calorieValue)]
    for (key, text) in [
      (NutrientKey.protein, protein), (.carbohydrate, carbohydrates), (.totalFat, fat),
    ] {
      if let value = parseNonnegative(text) {
        nutrients.append(NutrientAmount(key: key, amount: value))
      }
    }
    do {
      let entry = try FoodLogEntryRecord(
        consumedAt: consumedAt,
        originalText: name,
        displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
        quantityDisplay: amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "Amount not specified" : amount.trimmingCharacters(in: .whitespacesAndNewlines),
        isApproximate: approximate,
        source: .manual,
        calculationBasis: .manual,
        nutrients: nutrients
      )
      modelContext.insert(entry)
      try modelContext.save()
      onSaved()
      dismiss()
      Task {
        await HealthSyncCoordinator.syncIfEnabled(entry, modelContext: modelContext)
      }
    } catch {
      errorMessage = "The entry could not be saved."
    }
  }

  private func parseNonnegative(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let groupingSeparator = Locale.current.groupingSeparator ?? ","
    let decimalSeparator = Locale.current.decimalSeparator ?? "."
    let normalized =
      trimmed
      .replacingOccurrences(of: groupingSeparator, with: "")
      .replacingOccurrences(of: decimalSeparator, with: ".")
    guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
    return value
  }

  private func moveFocus(by offset: Int) {
    guard let focusedField, let index = Field.allCases.firstIndex(of: focusedField) else { return }
    let destination = index + offset
    guard Field.allCases.indices.contains(destination) else { return }
    self.focusedField = Field.allCases[destination]
  }

  private func fieldIdentifier(_ field: Field) -> String {
    switch field {
    case .name: "name"
    case .amount: "amount"
    case .calories: "calories"
    case .protein: "protein"
    case .carbohydrates: "carbohydrates"
    case .fat: "fat"
    }
  }
}
