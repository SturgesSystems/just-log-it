import JustLogItCore
import SwiftData
import SwiftUI

struct ManualEntryView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var name = ""
  @State private var amount = ""
  @State private var calories = ""
  @State private var protein = ""
  @State private var carbohydrates = ""
  @State private var fat = ""
  @State private var consumedAt = Date.now
  @State private var approximate = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Food") {
          TextField("Food name", text: $name)
          TextField("Amount eaten", text: $amount)
          DatePicker("Date and time", selection: $consumedAt)
          Toggle("Approximate", isOn: $approximate)
        }
        Section("Nutrition") {
          numericField("Calories", text: $calories, unit: "kcal")
          numericField("Protein", text: $protein, unit: "g")
          numericField("Carbohydrates", text: $carbohydrates, unit: "g")
          numericField("Total fat", text: $fat, unit: "g")
        }
        if let errorMessage {
          Text(errorMessage).foregroundStyle(.red)
        }
      }
      .navigationTitle("Manual Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save).disabled(!canSave)
        }
      }
    }
  }

  private func numericField(_ title: String, text: Binding<String>, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && validNonnegative(calories) != nil
  }

  private func save() {
    guard let calorieValue = validNonnegative(calories) else {
      errorMessage = "Calories must be a nonnegative number."
      return
    }
    var nutrients = [NutrientAmount(key: .energy, amount: calorieValue)]
    for (key, text) in [
      (NutrientKey.protein, protein), (.carbohydrate, carbohydrates), (.totalFat, fat),
    ] {
      if let value = validNonnegative(text) {
        nutrients.append(NutrientAmount(key: key, amount: value))
      }
    }
    do {
      let entry = try FoodLogEntryRecord(
        consumedAt: consumedAt,
        originalText: name,
        displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
        quantityDisplay: amount.isEmpty ? "Amount not specified" : amount,
        isApproximate: approximate,
        source: .manual,
        calculationBasis: .manual,
        nutrients: nutrients
      )
      modelContext.insert(entry)
      try modelContext.save()
      dismiss()
    } catch {
      errorMessage = "The entry could not be saved."
    }
  }

  private func validNonnegative(_ text: String) -> Double? {
    guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
    return value
  }
}
